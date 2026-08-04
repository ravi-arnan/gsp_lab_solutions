#!/usr/bin/env bash
# GSP294 - Introduction to APIs in Google Cloud
#
#   bash gsp294.sh
#
# Checkpoint:
#   1. Create a bucket with the Cloud Storage JSON/REST API
#   2. Upload a file using the Cloud Storage JSON/REST API
#
# Lab menyuruh ambil token dari OAuth 2.0 Playground lewat browser. Tidak perlu:
# `gcloud auth print-access-token` di Cloud Shell sudah punya scope
# devstorage.full_control, dan API-nya tidak peduli token itu datang dari mana.
#
# LAMA: <1 menit.

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

ask REGION "us-east1" "Region (cocokkan dengan panel lab)"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET="${PROJECT_ID}-bucket"
OBJECT="demo-image"
# Pakai gambar sendiri: OBJECT_FILE=~/demo-image.png bash gsp294.sh
OBJECT_FILE="${OBJECT_FILE:-$HOME/demo-image.png}"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Bucket : $BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Region + enable Fitness API (tidak dinilai)"
gcloud config set compute/region "$REGION"
gcloud services enable fitness.googleapis.com --project="$PROJECT_ID" || \
  echo "Fitness API gagal di-enable, dilewat (tidak ada checkpoint untuk ini)."

# ----------------------------------------------------------------- Task 2-4
step "Task 2-4: values.json + buat bucket lewat JSON API (checkpoint 1)"

cd "$HOME"
cat > ./values.json << EOF
{
  "name": "$BUCKET",
  "location": "us",
  "storageClass": "multi_regional"
}
EOF
cat values.json

curl -s -X POST --data-binary @values.json \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://www.googleapis.com/storage/v1/b?project=$PROJECT_ID" | head -20
echo

# ----------------------------------------------------------------- Task 5
step "Task 5: Upload object '$OBJECT' lewat JSON API (checkpoint 2)"

if [[ -f "$OBJECT_FILE" ]]; then
  echo "Pakai file yang sudah ada: $OBJECT_FILE"
else
  # Lab menyuruh upload gambar anjing dari komputer. Kalau belum ada, buat PNG
  # kecil yang valid supaya content-type image/png tetap benar.
  echo "File $OBJECT_FILE tidak ada, membuat PNG kecil."
  base64 -d > "$OBJECT_FILE" << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
EOF
fi

curl -s -X POST --data-binary @"$OBJECT_FILE" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: image/png" \
  "https://www.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$OBJECT" | head -20
echo

echo ">>> Isi bucket:"
gcloud storage ls "gs://$BUCKET" || true

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 2 checkpoint:
  1. Create a bucket with the Cloud Storage JSON/REST API
  2. Upload a file using the Cloud Storage JSON/REST API

Kuis pilihan ganda di teks lab tidak menambah skor.
--------------------------------------------------------------
EOF
