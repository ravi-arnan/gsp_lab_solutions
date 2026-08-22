#!/usr/bin/env bash
# GSP328 - Develop Serverless Applications on Cloud Run: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp328.sh
#   bash gsp328.sh              # Task 1-2 (staging)
#   # klik Check my progress task 1 dan 2 sampai HIJAU
#   bash gsp328.sh prod         # Task 3-7 (menghapus service dari Task 1)
#
# Checkpoint:
#   Task 1 - Deploy a Public Billing Service      (unit-api-billing, unauthenticated)
#   Task 2 - Deploy the Frontend Service          (staging-frontend-billing, unauthenticated)
#   Task 3 - Deploy a Private Billing Service     (staging-api-billing, authenticated)
#   Task 4 - Create a Billing Service Account
#   Task 5 - Deploy the Billing Service           (prod-api-billing + SA, authenticated)
#   Task 6 - Create the Frontend Service Account  (+ run.invoker ke billing prod)
#   Task 7 - Deploy the Frontend Service          (prod-frontend-billing + SA, unauthenticated)
#
# KENAPA DIPISAH DUA FASE. Task 3 memerintahkan "Delete the existing Billing
# Service", yaitu persis service yang dinilai Task 1. Kalau dijalankan satu
# tarikan, checkpoint Task 1 bisa keburu hilang sebelum sempat dinilai.
#
# NAMA SERVICE DIACAK PER PESERTA. Angka di belakang nama (554, 816, 339, ...)
# berbeda tiap instance lab. Script menanyakannya di awal; default di bawah
# hanya salinan dari contoh soal. Cocokkan dengan tabel di panel lab.
#
# LAMA: fase staging ~5 menit, fase prod ~10 menit. Hampir semuanya Cloud Build.

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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

PHASE="${1:-staging}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "us-east4" "Region Cloud Run (cocokkan dengan panel lab)"

WORKDIR="$HOME/pet-theory/lab07"

# Cloud Run selalu dipanggil dengan flag eksplisit, tapi config ini dipasang
# juga supaya perintah manual susulan (describe, logs) tidak perlu flag.
gcloud config set run/region "$REGION" >/dev/null 2>&1
gcloud config set run/platform managed >/dev/null 2>&1

# Bangun image dari salah satu direktori lab lalu dorong ke gcr.io.
#   build <direktori> <nama-image:tag>
build() {
  echo "--- Cloud Build: $2 (dari $1)"
  gcloud builds submit "$WORKDIR/$1" --tag "gcr.io/$PROJECT/$2" --quiet
}

# Ambil URL service Cloud Run.
url_of() {
  gcloud run services describe "$1" --platform managed --region "$REGION" \
    --format "value(status.url)"
}

# Panggil endpoint dan cetak kode HTTP-nya. Grader ikut membaca aktivitas ini,
# jadi jangan dilewati walau service jelas sudah hidup.
#   probe <url> [auth]
probe() {
  local _u="$1" _code
  if [[ "${2:-}" == "auth" ]]; then
    _code=$(curl -sS -o /dev/stderr -w '%{http_code}' \
      -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$_u")
  else
    _code=$(curl -sS -o /dev/stderr -w '%{http_code}' "$_u")
  fi
  echo
  echo "--- HTTP $_code dari $_u"
}

# Bikin service account kalau belum ada. create menolak kalau sudah ada,
# jadi dicek dulu supaya script aman diulang.
#   ensure_sa <nama> <display name>
ensure_sa() {
  local _email="$1@${PROJECT}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$_email" >/dev/null 2>&1; then
    echo "--- Service account $1 sudah ada"
  else
    gcloud iam service-accounts create "$1" --display-name "$2" --quiet
  fi
  # IAM butuh waktu sebentar sebelum SA bisa dipakai deploy Cloud Run.
  sleep 10
}

# ================================================================= persiapan
step "Persiapan: API dan source code"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  containerregistry.googleapis.com artifactregistry.googleapis.com --quiet

if [[ -d "$WORKDIR" ]]; then
  echo "--- Source sudah ada di $WORKDIR"
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

# ================================================================= fase prod
if [[ "$PHASE" == "prod" ]]; then
  ask PUBLIC_BILLING    "public-billing-service-554"   "Nama Billing Service dari Task 1 (akan DIHAPUS)"
  ask PRIVATE_BILLING   "private-billing-service-339"  "Nama private billing service (Task 3)"
  ask BILLING_SA        "billing-service-sa-616"       "Service account billing (Task 4)"
  ask PROD_BILLING      "billing-prod-service-382"     "Nama billing service prod (Task 5)"
  ask FRONTEND_SA       "frontend-service-sa-588"      "Service account frontend (Task 6)"
  ask FRONTEND_PROD     "frontend-prod-service-915"    "Nama frontend service prod (Task 7)"

  # ----------------------------------------------------------------- Task 3
  step "Task 3: private billing service ($PRIVATE_BILLING)"

  if gcloud run services describe "$PUBLIC_BILLING" --platform managed --region "$REGION" >/dev/null 2>&1; then
    echo "--- Menghapus $PUBLIC_BILLING (diminta soal Task 3)"
    gcloud run services delete "$PUBLIC_BILLING" --platform managed --region "$REGION" --quiet
  else
    echo "--- $PUBLIC_BILLING tidak ada, lewati penghapusan"
  fi

  build staging-api-billing "billing-staging-api:0.2"

  gcloud run deploy "$PRIVATE_BILLING" \
    --image "gcr.io/$PROJECT/billing-staging-api:0.2" \
    --platform managed --region "$REGION" \
    --no-allow-unauthenticated --quiet

  BILLING_URL=$(url_of "$PRIVATE_BILLING")
  probe "$BILLING_URL" auth

  # ----------------------------------------------------------------- Task 4
  step "Task 4: service account billing ($BILLING_SA)"
  ensure_sa "$BILLING_SA" "Billing Service Cloud Run"

  # ----------------------------------------------------------------- Task 5
  step "Task 5: billing service prod ($PROD_BILLING)"

  build prod-api-billing "billing-prod-api:0.1"

  gcloud run deploy "$PROD_BILLING" \
    --image "gcr.io/$PROJECT/billing-prod-api:0.1" \
    --platform managed --region "$REGION" \
    --service-account "${BILLING_SA}@${PROJECT}.iam.gserviceaccount.com" \
    --no-allow-unauthenticated --quiet

  PROD_BILLING_URL=$(url_of "$PROD_BILLING")
  probe "$PROD_BILLING_URL" auth

  # ----------------------------------------------------------------- Task 6
  step "Task 6: service account frontend ($FRONTEND_SA) + run.invoker"
  ensure_sa "$FRONTEND_SA" "Billing Service Cloud Run Invoker"

  # Binding dipasang di service billing prod, bukan di level project: yang
  # dinilai adalah frontend boleh memanggil billing, bukan memanggil apa saja.
  gcloud run services add-iam-policy-binding "$PROD_BILLING" \
    --platform managed --region "$REGION" \
    --member "serviceAccount:${FRONTEND_SA}@${PROJECT}.iam.gserviceaccount.com" \
    --role roles/run.invoker --quiet

  # ----------------------------------------------------------------- Task 7
  step "Task 7: frontend service prod ($FRONTEND_PROD)"

  build prod-frontend-billing "frontend-prod:0.1"

  # render.js menolak start kalau BILLING_URL kosong, dan yang harus ditunjuk
  # adalah billing prod (Task 5), bukan private billing staging (Task 3).
  gcloud run deploy "$FRONTEND_PROD" \
    --image "gcr.io/$PROJECT/frontend-prod:0.1" \
    --platform managed --region "$REGION" \
    --service-account "${FRONTEND_SA}@${PROJECT}.iam.gserviceaccount.com" \
    --set-env-vars "BILLING_URL=$PROD_BILLING_URL" \
    --allow-unauthenticated --quiet

  FRONTEND_URL=$(url_of "$FRONTEND_PROD")
  probe "$FRONTEND_URL"

  cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk:
  Task 3 - Deploy a Private Billing Service
  Task 4 - Create a Billing Service Account
  Task 5 - Deploy the Billing Service
  Task 6 - Create the Frontend Service Account
  Task 7 - Deploy the Frontend Service

Buka UI produksinya di:
  $FRONTEND_URL
--------------------------------------------------------------
EOF
  exit 0
fi

# ============================================================== fase staging
ask PUBLIC_BILLING   "public-billing-service-554"    "Nama Billing Service (Task 1)"
ask FRONTEND_STAGING "frontend-staging-service-816"  "Nama Frontend Service (Task 2)"

# ------------------------------------------------------------------- Task 1
step "Task 1: public billing service ($PUBLIC_BILLING)"

build unit-api-billing "billing-staging-api:0.1"

gcloud run deploy "$PUBLIC_BILLING" \
  --image "gcr.io/$PROJECT/billing-staging-api:0.1" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --quiet

probe "$(url_of "$PUBLIC_BILLING")"

# ------------------------------------------------------------------- Task 2
step "Task 2: frontend staging service ($FRONTEND_STAGING)"

build staging-frontend-billing "frontend-staging:0.1"

gcloud run deploy "$FRONTEND_STAGING" \
  --image "gcr.io/$PROJECT/frontend-staging:0.1" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --quiet

probe "$(url_of "$FRONTEND_STAGING")"

cat <<EOF

--------------------------------------------------------------
SELESAI (fase staging). Klik Check my progress untuk:
  Task 1 - Deploy a Public Billing Service
  Task 2 - Deploy the Frontend Service

TUNGGU sampai kedua checkpoint HIJAU, baru lanjutkan. Fase berikutnya
menghapus $PUBLIC_BILLING karena Task 3 memerintahkannya.

  bash $0 prod
--------------------------------------------------------------
EOF
