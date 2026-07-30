#!/usr/bin/env bash
# GSP421 - APIs Explorer: Cloud Storage
#
#   bash gsp421.sh            # Task 1-4 (semua yang dinilai)
#   bash gsp421.sh cleanup    # Task 5-6, TIDAK dinilai dan merusak checkpoint 3
#
# Checkpoint:
#   1. Create a Cloud Storage Bucket
#   2. Make a second Cloud Storage bucket
#   3. Upload Files to Your Cloud Storage Bucket (demo-image1.png, demo-image2.png)
#   4. Copy files between Cloud Storage buckets (demo-image1-copy.png)
#
# Task 5 (hapus kedua file) dan Task 6 (hapus bucket 1) tidak punya checkpoint,
# dan menghapus persis yang dinilai checkpoint 3. Karena itu dipisah ke fase
# 'cleanup' yang tidak jalan otomatis.
#
# Lab aslinya lewat APIs Explorer di browser; di sini methodnya dipanggil
# langsung ke endpoint JSON API yang sama pakai curl.
#
# LAMA: <1 menit.

set -euo pipefail

PHASE="${1:-main}"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET1="${PROJECT_ID}-bucket-1"
BUCKET2="${PROJECT_ID}-bucket-2"
IMG1="demo-image1.png"
IMG2="demo-image2.png"
IMG_COPY="demo-image1-copy.png"

API="https://storage.googleapis.com/storage/v1"
UPLOAD_API="https://storage.googleapis.com/upload/storage/v1"

echo "Project : $PROJECT_ID"
echo "Bucket 1: $BUCKET1"
echo "Bucket 2: $BUCKET2"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

token() { gcloud auth print-access-token; }

# ================================================================= cleanup
if [[ "$PHASE" == "cleanup" ]]; then
  step "Task 5-6: hapus kedua object lalu bucket 1 (TIDAK dinilai)"
  echo "Ini menghapus apa yang dinilai checkpoint 3. Pastikan sudah hijau."

  for OBJ in "$IMG1" "$IMG2"; do
    echo ">>> DELETE $OBJ dari $BUCKET1"
    curl -s -X DELETE -H "Authorization: Bearer $(token)" \
      -H "Content-Length: 0" "$API/b/$BUCKET1/o/$OBJ"
  done

  echo ">>> DELETE bucket $BUCKET1"
  curl -s -X DELETE -H "Authorization: Bearer $(token)" \
    -H "Content-Length: 0" "$API/b/$BUCKET1"

  echo ">>> Sisa bucket:"
  gcloud storage ls || true
  exit 0
fi

# ================================================================= Task 1-2
step "Task 1-2: buat dua bucket (buckets.insert) (checkpoint 1 dan 2)"

for BUCKET in "$BUCKET1" "$BUCKET2"; do
  cat > "/tmp/gsp421-$BUCKET.json" << EOF
{
  "name": "$BUCKET"
}
EOF
  echo ">>> POST bucket $BUCKET"
  curl -s -X POST --data-binary @"/tmp/gsp421-$BUCKET.json" \
    -H "Authorization: Bearer $(token)" \
    -H "Content-Type: application/json" \
    "$API/b?project=$PROJECT_ID" | head -12
  echo
done

# ================================================================= Task 3
step "Task 3: upload dua image ke $BUCKET1 (checkpoint 3)"

# Lab menyuruh unduh gambar anjing dan Ada Lovelace lalu upload manual. Isi file
# tidak dinilai, yang dicek namanya, jadi PNG kecil sudah cukup.
make_png() {
  local path=$1
  [[ -f "$path" ]] && { echo "Pakai file yang sudah ada: $path"; return; }
  base64 -d > "$path" << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
EOF
}

for IMG in "$IMG1" "$IMG2"; do
  make_png "$HOME/$IMG"
  echo ">>> POST upload $IMG"
  curl -s -X POST --data-binary @"$HOME/$IMG" \
    -H "Authorization: Bearer $(token)" \
    -H "Content-Type: image/png" \
    "$UPLOAD_API/b/$BUCKET1/o?uploadType=media&name=$IMG" | head -12
  echo
done

# ================================================================= Task 4
step "Task 4: copy $IMG1 ke $BUCKET2 sebagai $IMG_COPY (checkpoint 4)"

curl -s -X POST \
  -H "Authorization: Bearer $(token)" \
  -H "Content-Length: 0" \
  "$API/b/$BUCKET1/o/$IMG1/copyTo/b/$BUCKET2/o/$IMG_COPY" | head -12
echo

echo ">>> Isi $BUCKET1:"
gcloud storage ls "gs://$BUCKET1" || true
echo ">>> Isi $BUCKET2:"
gcloud storage ls "gs://$BUCKET2" || true

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 4 checkpoint:
  1. Create a Cloud Storage Bucket
  2. Make a second Cloud Storage bucket
  3. Upload Files to Your Cloud Storage Bucket
  4. Copy files between Cloud Storage buckets

Skor sudah penuh di sini. Task 5-6 (hapus file dan bucket 1) tidak
menambah poin dan justru menghapus yang dinilai checkpoint 3.
Kalau tetap mau mencobanya setelah semua hijau:

  bash $0 cleanup
--------------------------------------------------------------
EOF
