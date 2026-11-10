#!/usr/bin/env bash
# GSP069 - App Engine: Qwik Start - PHP
#
#   bash gsp069.sh
#
# Checkpoint:
#   Task 4 - Deploy your app

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set di env var
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

DEFAULT_REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="europe-west1"

ask REGION "$DEFAULT_REGION" "Region (cocokkan dengan panel lab)"

# Mapping region Compute Engine ke App Engine location
map_app_region() {
  case "$1" in
    europe-west1) echo "europe-west" ;;
    us-central1) echo "us-central" ;;
    *) echo "$1" ;;
  esac
}

APP_REGION="$(map_app_region "$REGION")"

echo "Project ID  : $PROJECT_ID"
echo "Region      : $REGION"
echo "App Region  : $APP_REGION"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1: Enable App Engine Admin API
step "Task 1: Mengaktifkan App Engine Admin API & Inisialisasi App Engine"

echo "Mengaktifkan service appengine.googleapis.com..."
gcloud services enable appengine.googleapis.com --project="$PROJECT_ID"

if ! gcloud app describe --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Membuat App Engine application di region $APP_REGION..."
  gcloud app create --region="$APP_REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || \
  gcloud app create --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || true
else
  echo "App Engine application sudah ada."
fi

# ----------------------------------------------------------------- Task 2: Setup Hello World App PHP
step "Task 2: Menyiapkan Kode Aplikasi Hello World PHP"

APP_DIR="$HOME/php-docs-samples/appengine/standard/helloworld"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "Menulis app.yaml (runtime: php83)..."
cat << 'EOF_YAML' > app.yaml
runtime: php83
EOF_YAML

echo "Menulis index.php (hello world!)..."
cat << 'EOF_PHP' > index.php
<?php

echo 'hello world!';
EOF_PHP

# ----------------------------------------------------------------- Task 3-4: Deploy App Engine (Checkpoint)
step "Task 3 & 4: Deploy Aplikasi ke App Engine (Checkpoint)"

echo "Men-deploy aplikasi PHP ke App Engine..."
gcloud app deploy app.yaml --project="$PROJECT_ID" --quiet

HOSTNAME="$(gcloud app describe --project="$PROJECT_ID" --format='value(defaultHostname)' 2>/dev/null || echo "${PROJECT_ID}.appspot.com")"
echo "Aplikasi berhasil di-deploy ke: https://${HOSTNAME}"

echo "Menguji akses HTTP aplikasi..."
for i in {1..5}; do
  RESP="$(curl -s -m 5 "https://${HOSTNAME}" || true)"
  if [[ -n "$RESP" ]]; then
    echo "Respons aplikasi: $RESP"
    break
  fi
  sleep 2
done

# ----------------------------------------------------------------- Task 5: Modifikasi Kode & Redeploy
step "Task 5: Memperbarui Kode ke 'goodbye world!' & Redeploy"

cat << 'EOF_PHP2' > index.php
<?php

echo 'goodbye world!';
EOF_PHP2

echo "Men-deploy versi pembaruan aplikasi..."
gcloud app deploy app.yaml --project="$PROJECT_ID" --quiet

echo "Menguji akses HTTP aplikasi terbaru..."
curl -s -m 5 "https://${HOSTNAME}" || true
echo

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Deploy your app (Task 4)

Kuis Pemahaman (Task 6):
  - The App Engine standard environment makes it easy to build and deploy an application that runs reliably under heavy load and with large amounts of data.
    Jawaban: True
==============================================================
EOF
