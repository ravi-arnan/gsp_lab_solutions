#!/usr/bin/env bash
# GSP499 - User Authentication: Identity-Aware Proxy
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp499.sh
#   bash gsp499.sh
#
# Checkpoint:
#   Task 1 - Deploy a Cloud Run service          (1-HelloWorld)
#   Task 1 - Enable and add policy to IAP        (IAP on + IAP-Secured Web App User)
#   Task 2 - Access User Identity Information    (2-HelloUser)
#   Task 3 - Use Cryptographic Verification      (3-HelloVerifiedUser + IAP_AUDIENCE)
#
# Lab aslinya menyalakan/mematikan IAP lewat Console. Semuanya ada padanan
# gcloud-nya, jadi tidak ada langkah Console sama sekali di sini.
#
# JWT audience untuk IAP di Cloud Run TIDAK perlu disalin dari Console:
# formatnya /projects/<PROJECT_NUMBER>/locations/<REGION>/services/<SERVICE>.
#
# Tiga kali deploy from source, masing-masing 2-3 menit. Sabar.

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
#   ask <NAMA_VAR> <default> <pertanyaan>
ask() {
  local _cur="${!1:-}"
  if [[ -n "$_cur" ]]; then echo "$1 = $_cur (dari env)"; return; fi
  if [[ -t 0 ]]; then
    local _v
    read -rp "$3 [$2]: " _v
    printf -v "$1" '%s' "${_v:-$2}"
  else
    printf -v "$1" '%s' "$2"
  fi
  echo "$1 = ${!1}"
}

step() { echo; echo "=== $* ==="; }

SERVICE="user-auth-lab"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "PROJECT = $PROJECT ($PROJECT_NUMBER)"
echo "ACCOUNT = $ACCOUNT"

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"

step "Mengaktifkan API"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com iap.googleapis.com >/dev/null
# Service agent IAP harus ada sebelum bisa diberi run.invoker.
gcloud beta services identity create --service=iap.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true
IAP_SA="service-$PROJECT_NUMBER@gcp-sa-iap.iam.gserviceaccount.com"

# ------------------------------------------------------------------- sumber
step "Mengunduh kode aplikasi"
SRC="$HOME/user-authentication-with-iap"
if [[ -d "$SRC/1-HelloWorld" ]]; then
  echo "kode sudah ada di $SRC"
else
  BUCKET_DEFAULT="$PROJECT-bucket"
  gcloud storage ls "gs://$BUCKET_DEFAULT" >/dev/null 2>&1 || \
    BUCKET_DEFAULT="$(gcloud storage ls | sed -n 's#^gs://\([^/]*\)/.*#\1#p' | head -n1)"
  ask BUCKET "$BUCKET_DEFAULT" "Bucket berisi user-authentication-with-iap.zip"
  cd "$HOME"
  gcloud storage cp "gs://$BUCKET/user-authentication-with-iap.zip" .
  unzip -oq user-authentication-with-iap.zip
fi
[[ -d "$SRC/1-HelloWorld" ]] || { echo "Folder 1-HelloWorld tidak ditemukan di $SRC"; exit 1; }

# ------------------------------------------------------------------- Task 1
step "Task 1 - deploy 1-HelloWorld ke Cloud Run"
cd "$SRC/1-HelloWorld"
gcloud run deploy "$SERVICE" --source . --allow-unauthenticated --region="$REGION" -q

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"
echo "URL = $URL"

step "Task 1 - nyalakan IAP dan beri akses ke $ACCOUNT"
# Padanan gcloud dari toggle IAP di Console. Kalau flag --iap belum ada di
# versi gcloud yang terpasang, pesan errornya dicetak lalu lanjut supaya
# langkah lain tetap jalan.
gcloud beta run services update "$SERVICE" --region="$REGION" --iap -q \
  || echo "PERINGATAN: gagal menyalakan IAP lewat gcloud, nyalakan manual di Console."

# Menyalakan IAP membuat IAP yang memanggil service, bukan publik lagi.
gcloud run services remove-iam-policy-binding "$SERVICE" --region="$REGION" \
  --member=allUsers --role=roles/run.invoker -q >/dev/null 2>&1 || true
gcloud run services add-iam-policy-binding "$SERVICE" --region="$REGION" \
  --member="serviceAccount:$IAP_SA" --role=roles/run.invoker -q >/dev/null

gcloud beta iap web add-iam-policy-binding \
  --resource-type=cloud-run --service="$SERVICE" --region="$REGION" \
  --member="user:$ACCOUNT" --role=roles/iap.httpsResourceAccessor --condition=None >/dev/null
echo "roles/iap.httpsResourceAccessor -> $ACCOUNT"

# ------------------------------------------------------------------- Task 2
step "Task 2 - deploy 2-HelloUser (baca header identitas dari IAP)"
cd "$SRC/2-HelloUser"
gcloud run deploy "$SERVICE" --source . --region="$REGION" -q

# ------------------------------------------------------------------- Task 3
step "Task 3 - deploy 3-HelloVerifiedUser (verifikasi tanda tangan JWT)"
# Tidak perlu "Get JWT audience code" di Console; format audience untuk IAP di
# Cloud Run sudah baku dan bisa disusun dari project number dan nama service.
AUDIENCE="/projects/$PROJECT_NUMBER/locations/$REGION/services/$SERVICE"
echo "IAP_AUDIENCE = $AUDIENCE"

cd "$SRC/3-HelloVerifiedUser"
gcloud run deploy "$SERVICE" --source . --region="$REGION" \
  --set-env-vars IAP_AUDIENCE="$AUDIENCE" -q

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Deploy a Cloud Run service            (Task 1)
  - Enable and add policy to IAP          (Task 1)
  - Access User Identity Information      (Task 2)
  - Use Cryptographic Verification        (Task 3)

Buka aplikasinya di tab baru: $URL
Email dan ID yang terverifikasi tampil tanpa awalan accounts.google.com:.

Kalau muncul halaman "You don't have access", tunggu semenit lalu reload.
Kalau masih, bersihkan cookie IAP: $URL/_gcp_iap/clear_login_cookie
EOF
