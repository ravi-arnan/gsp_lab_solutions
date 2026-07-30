#!/usr/bin/env bash
# ARC125 - Use APIs to Work with Cloud Storage: Challenge Lab
#
#   bash arc125.sh            # Task 1-4, lalu berhenti minta konfirmasi
#   bash arc125.sh cleanup    # Task 5 (hapus object + bucket 1)
#
# Checkpoint:
#   1. Create two Cloud Storage buckets
#   2. Upload an image file to a Cloud Storage Bucket
#   3. Copy a file to another bucket
#   4. Make an object (file) publicly accessible
#   5. Delete the file and Cloud Storage bucket (Bucket 1)
#
# WAJIB DUA FASE: Task 5 menghapus bucket-1, sedangkan checkpoint 2 menilai
# file di dalam bucket-1. Hijaukan checkpoint 1-4 dulu, baru jalankan cleanup.
#
# Semua langkah pakai Cloud Storage JSON/REST API lewat curl, sesuai syarat lab.
# LAMA: ~1 menit.

set -euo pipefail

PHASE="${1:-main}"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET1="${PROJECT_ID}-bucket-1"
BUCKET2="${PROJECT_ID}-bucket-2"
OBJECT="${OBJECT:-world-map.png}"
# Pakai file sendiri: OBJECT_FILE=~/gambar.png bash arc125.sh
OBJECT_FILE="${OBJECT_FILE:-$HOME/$OBJECT}"

API="https://storage.googleapis.com/storage/v1"
UPLOAD_API="https://storage.googleapis.com/upload/storage/v1"

echo "Project : $PROJECT_ID"
echo "Bucket 1: $BUCKET1"
echo "Bucket 2: $BUCKET2"
echo "Object  : $OBJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

token() { gcloud auth print-access-token; }

api() {
  # api <method> <url> [file-json]
  local method=$1 url=$2 body=${3:-}
  if [[ -n "$body" ]]; then
    curl -s -X "$method" \
      -H "Authorization: Bearer $(token)" \
      -H "Content-Type: application/json" \
      --data-binary @"$body" "$url"
  else
    curl -s -X "$method" \
      -H "Authorization: Bearer $(token)" \
      -H "Content-Length: 0" "$url"
  fi
}

# ================================================================= cleanup
if [[ "$PHASE" == "cleanup" ]]; then
  step "Task 5: Hapus object lalu bucket 1 (checkpoint 5)"

  echo ">>> DELETE object $OBJECT dari $BUCKET1"
  api DELETE "$API/b/$BUCKET1/o/$OBJECT"

  echo ">>> DELETE bucket $BUCKET1"
  api DELETE "$API/b/$BUCKET1"

  echo ">>> Sisa bucket:"
  gcloud storage ls || true

  echo
  echo "Selesai. Klik Check my progress untuk checkpoint 5."
  exit 0
fi

# ================================================================= Task 1
step "Task 1: Buat dua bucket lewat JSON API (checkpoint 1)"

for BUCKET in "$BUCKET1" "$BUCKET2"; do
  cat > "/tmp/arc125-$BUCKET.json" << EOF
{
  "name": "$BUCKET",
  "location": "us",
  "storageClass": "multi_regional"
}
EOF
  echo ">>> POST bucket $BUCKET"
  api POST "$API/b?project=$PROJECT_ID" "/tmp/arc125-$BUCKET.json" | head -12
  echo
done

# ================================================================= Task 2
step "Task 2: Upload image ke $BUCKET1 (checkpoint 2)"

if [[ -f "$OBJECT_FILE" ]]; then
  echo "Pakai file yang sudah ada: $OBJECT_FILE"
else
  # Lab meminta upload gambar dari komputer. Kalau tidak ada, buat PNG kecil
  # yang valid supaya API tetap menerima content-type image/png.
  echo "File $OBJECT_FILE tidak ada, membuat PNG kecil."
  base64 -d > "$OBJECT_FILE" << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
EOF
fi

echo ">>> POST upload $OBJECT"
curl -s -X POST \
  -H "Authorization: Bearer $(token)" \
  -H "Content-Type: image/png" \
  --data-binary @"$OBJECT_FILE" \
  "$UPLOAD_API/b/$BUCKET1/o?uploadType=media&name=$OBJECT" | head -12
echo

# ================================================================= Task 3
step "Task 3: Copy object ke $BUCKET2 (checkpoint 3)"

echo ">>> POST copyTo"
api POST "$API/b/$BUCKET1/o/$OBJECT/copyTo/b/$BUCKET2/o/$OBJECT" | head -12
echo

# ================================================================= Task 4
step "Task 4: Jadikan object publik (checkpoint 4)"

cat > /tmp/arc125-acl.json << 'EOF'
{
  "entity": "allUsers",
  "role": "READER"
}
EOF

# Dipasang di kedua bucket: bucket 1 dihapus di Task 5, jadi yang tersisa
# untuk dinilai adalah salinan di bucket 2.
for BUCKET in "$BUCKET1" "$BUCKET2"; do
  echo ">>> POST acl allUsers:READER di $BUCKET"
  api POST "$API/b/$BUCKET/o/$OBJECT/acl" /tmp/arc125-acl.json | head -12
  echo
done

echo ">>> Cek akses publik:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "https://storage.googleapis.com/$BUCKET2/$OBJECT"

# ================================================================= jeda
cat <<EOF

--------------------------------------------------------------
Task 1-4 selesai. Klik Check my progress untuk:
  1. Create two Cloud Storage buckets
  2. Upload an image file to a Cloud Storage Bucket
  3. Copy a file to another bucket
  4. Make an object (file) publicly accessible

Checkpoint 2 menilai file di $BUCKET1, dan Task 5 menghapus
bucket itu. Pastikan keempatnya HIJAU dulu.
--------------------------------------------------------------
EOF

if [[ -t 0 ]]; then
  read -r -p "Sudah hijau semua? Tekan Enter untuk lanjut Task 5 (Ctrl-C untuk berhenti)..." _
  exec "$0" cleanup
else
  echo "Lanjutkan dengan: bash $0 cleanup"
fi
