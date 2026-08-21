#!/usr/bin/env bash
# GSP659 - Deploy Your Website on Cloud Run
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp659.sh
#   bash gsp659.sh            # Task 1-4  -> checkpoint 1, 2, 3
#   # klik Check my progress 1-3 sampai hijau
#   bash gsp659.sh update     # Task 4b-6 -> checkpoint 4, 5
#
# Checkpoint:
#   1. Create Docker Container with Google Cloud Build   (image monolith:1.0.0)
#   2. Deploy Container To Cloud Run                     (service monolith)
#   3. Create new revision with lower concurrency        (revisi concurrency 1)
#   4. Make Changes To The Website                       (image monolith:2.0.0)
#   5. Update website with zero downtime                 (service pakai 2.0.0)
#
# Kenapa dua fase: setelah checkpoint 3, lab menyuruh mengembalikan concurrency
# ke 80. Kalau checkpoint 3 memeriksa revisi yang sedang aktif (bukan sekadar
# ada di riwayat), mengembalikannya duluan bisa membuat poinnya hilang. Jadi
# fase 'update' dipisah dan tidak jalan otomatis.
#
# LAMA: fase 1 sekitar 6-8 menit (npm install + dua build), fase 2 sekitar 4 menit.

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

PHASE="${1:-main}"
ask REGION "us-west1" "Region (cocokkan dengan panel lab)"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

REPO="monolith-demo"
SERVICE="monolith"
SRC="$HOME/monolith-to-microservices"
IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE}"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Image  : $IMAGE_BASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# React app menghasilkan monolith/public. Dipakai di fase main (sebelum build
# 1.0.0) dan fase update (setelah index.js diganti).
build_react() {
  cd "$SRC/react-app"
  npm run build:monolith
}

# ================================================================= fase update
if [[ "$PHASE" == "update" ]]; then
  [[ -d "$SRC" ]] || { echo "$SRC tidak ada. Jalankan dulu: bash $0"; exit 1; }

  step "Task 4b: kembalikan concurrency ke 80 (tidak dinilai)"
  echo "Pastikan checkpoint 3 sudah hijau sebelum ini."
  gcloud run deploy "$SERVICE" \
    --image "${IMAGE_BASE}:1.0.0" \
    --region "$REGION" --platform managed \
    --concurrency 80 --quiet

  step "Task 5: ganti homepage lalu build image 2.0.0 (checkpoint 4)"
  HOME_DIR="$SRC/react-app/src/pages/Home"
  if [[ -f "$HOME_DIR/index.js.new" ]]; then
    mv "$HOME_DIR/index.js.new" "$HOME_DIR/index.js"
    echo "index.js.new -> index.js"
  else
    echo "index.js.new sudah dipindah sebelumnya, dilewat."
  fi
  grep -q "Fancy Fashion" "$HOME_DIR/index.js" || { echo "Isi index.js tidak sesuai harapan, berhenti."; exit 1; }

  build_react

  cd "$SRC/monolith"
  gcloud builds submit --tag "${IMAGE_BASE}:2.0.0"

  step "Task 6: deploy 2.0.0 tanpa downtime (checkpoint 5)"
  gcloud run deploy "$SERVICE" \
    --image "${IMAGE_BASE}:2.0.0" \
    --region "$REGION" --platform managed --quiet

  URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --platform managed --format='value(status.url)')

  cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk verifikasi:
  4. Make Changes To The Website
  5. Update website with zero downtime

Buka $URL — homepage sekarang berjudul
"Fancy Fashion & Style Online". Kalau masih versi lama, hard refresh
(Ctrl+Shift+R), revisi barunya butuh beberapa detik menerima trafik.
--------------------------------------------------------------
EOF
  exit 0
fi

# ================================================================= Task 2 prep
step "Aktifkan API dan buat repository Artifact Registry"
gcloud services enable artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com

if gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1; then
  echo "Repository $REPO sudah ada, dilewat."
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Monolith demo"
fi

gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# ================================================================= Task 1
step "Task 1: clone source dan build React app"
if [[ -d "$SRC" ]]; then
  echo "$SRC sudah ada, clone dilewat."
else
  git clone https://github.com/googlecodelabs/monolith-to-microservices.git "$SRC"
fi

# Lab menyuruh ./setup.sh, yang meng-install dependency monolith, microservices,
# dan react-app. Yang benar-benar dibutuhkan cuma react-app: monolith/public
# dihasilkan dari build React, sedangkan dependency monolith di-install di dalam
# container oleh Dockerfile. Melewati sisanya menghemat beberapa menit dan
# menjaga upload ke Cloud Build tetap kecil (node_modules tidak ikut terkirim).
cd "$SRC/react-app"
npm install --no-audit --no-fund
build_react

# ================================================================= Task 2
step "Task 2: build image 1.0.0 dengan Cloud Build (checkpoint 1)"
cd "$SRC/monolith"
gcloud builds submit --tag "${IMAGE_BASE}:1.0.0"

# ================================================================= Task 3
step "Task 3: deploy ke Cloud Run (checkpoint 2)"
gcloud run deploy "$SERVICE" \
  --image "${IMAGE_BASE}:1.0.0" \
  --region "$REGION" --platform managed \
  --allow-unauthenticated --quiet

gcloud run services list --platform managed

# ================================================================= Task 4
step "Task 4: revisi baru dengan concurrency 1 (checkpoint 3)"
gcloud run deploy "$SERVICE" \
  --image "${IMAGE_BASE}:1.0.0" \
  --region "$REGION" --platform managed \
  --concurrency 1 --quiet

URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --platform managed --format='value(status.url)')

cat <<EOF

--------------------------------------------------------------
Fase 1 selesai. Klik Check my progress untuk:
  1. Create Docker Container with Google Cloud Build
  2. Deploy Container To Cloud Run
  3. Create new revision with lower concurrency

Website: $URL

Setelah ketiganya HIJAU, lanjutkan fase kedua (concurrency kembali
80, ganti homepage, build 2.0.0, deploy tanpa downtime):

  bash $0 update
--------------------------------------------------------------
EOF
