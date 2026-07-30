#!/usr/bin/env bash
# GSP074 - Cloud Storage: Qwik Start - CLI/SDK
#
#   bash gsp074.sh            # Task 1-7 (semua yang dinilai)
#   bash gsp074.sh cleanup    # Task 8, TIDAK dinilai dan merusak checkpoint 3
#
# Checkpoint:
#   1. Create a Cloud Storage bucket
#   2. Copy an object to a folder in the bucket (ada.jpg)
#   3. Make your object publicly accessible
#
# Task 8 mencabut akses publik dan menghapus ada.jpg — persis yang dinilai
# checkpoint 3. Karena itu dipisah ke fase 'cleanup' yang tidak jalan otomatis.
#
# LAMA: <1 menit.

set -euo pipefail

PHASE="${1:-main}"
REGION="${REGION:-us-east1}"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET="${BUCKET:-${PROJECT_ID}-bucket}"
IMG="ada.jpg"
IMG_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Bucket : gs://$BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================= cleanup
if [[ "$PHASE" == "cleanup" ]]; then
  step "Task 8: cabut akses publik + hapus $IMG (TIDAK dinilai)"
  echo "Ini membatalkan apa yang dinilai checkpoint 3. Pastikan sudah hijau."
  gcloud storage objects update "gs://$BUCKET/$IMG" --remove-acl-grant=allUsers
  gcloud storage rm "gs://$BUCKET/$IMG"
  echo ">>> Sisa isi bucket (salinan di image-folder/ tetap ada):"
  gcloud storage ls -r "gs://$BUCKET" || true
  exit 0
fi

# ================================================================= Task 1
step "Task 1: buat bucket (checkpoint 1)"
gcloud config set compute/region "$REGION"

if gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "gs://$BUCKET"
fi

# ================================================================= Task 2
step "Task 2: unduh $IMG lalu upload ke bucket"
cd "$HOME"
curl -sS "$IMG_URL" --output "$IMG"
gcloud storage cp "$IMG" "gs://$BUCKET"
rm -f "$IMG"

# ================================================================= Task 3
step "Task 3: unduh kembali dari bucket"
gcloud storage cp -r "gs://$BUCKET/$IMG" .

# ================================================================= Task 4
step "Task 4: copy ke folder image-folder/ (checkpoint 2)"
gcloud storage cp "gs://$BUCKET/$IMG" "gs://$BUCKET/image-folder/"

# ================================================================= Task 5-6
step "Task 5-6: list isi bucket dan detail object"
gcloud storage ls "gs://$BUCKET"
gcloud storage ls -l "gs://$BUCKET/$IMG"

# ================================================================= Task 7
step "Task 7: jadikan $IMG publik (checkpoint 3)"
gcloud storage objects update "gs://$BUCKET/$IMG" --add-acl-grant=entity=allUsers,role=READER

echo ">>> Cek akses publik:"
curl -s -o /dev/null -w "HTTP %{http_code}  https://storage.googleapis.com/$BUCKET/$IMG\n" \
  "https://storage.googleapis.com/$BUCKET/$IMG"

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 3 checkpoint:
  1. Create a Cloud Storage bucket
  2. Copy an object to a folder in the bucket (ada.jpg)
  3. Make your object publicly accessible

Skor sudah penuh di sini. Task 8 (cabut akses publik lalu hapus
ada.jpg) tidak menambah poin dan membatalkan checkpoint 3.
Kalau tetap mau mencobanya setelah semua hijau:

  bash $0 cleanup
--------------------------------------------------------------
EOF
