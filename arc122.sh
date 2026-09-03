#!/usr/bin/env bash
# ARC122 - Analyze Images with the Cloud Vision API: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc122.sh
#   bash arc122.sh
#   # atau kalau API_KEY belum auto-kedetek:
#   API_KEY=<key-dari-console> bash arc122.sh
#
# Checkpoint:
#   Task 1 - API key + bucket PROJECT_ID-bucket public
#   Task 2 - TEXT_DETECTION     -> text-response.json     -> gs://BUCKET/
#   Task 3 - LANDMARK_DETECTION -> landmark-response.json -> gs://BUCKET/
#
# LAMA: < 1 menit.

set -euo pipefail

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET="${BUCKET:-${PROJECT}-bucket}"
API_KEY="${API_KEY:-}"
KEY_DISPLAY_NAME="arc122"

echo "Project: $PROJECT"
echo "Bucket : gs://$BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable Vision API"
gcloud services enable vision.googleapis.com apikeys.googleapis.com --project="$PROJECT" -q

# ----------------------------------------------------------------- Task 1: API key
step "Task 1: API key"
if [[ -n "$API_KEY" ]]; then
  echo "Pakai API_KEY dari env (${#API_KEY} karakter)."
else
  KEY_NAME=$(gcloud services api-keys list --project="$PROJECT" --filter="displayName=$KEY_DISPLAY_NAME" --format="value(name)" 2>/dev/null | head -1)
  if [[ -z "$KEY_NAME" ]]; then
    echo "Membuat API key baru ($KEY_DISPLAY_NAME)..."
    gcloud services api-keys create --display-name="$KEY_DISPLAY_NAME" --project="$PROJECT" 2>&1 | cat
    sleep 5
    KEY_NAME=$(gcloud services api-keys list --project="$PROJECT" --filter="displayName=$KEY_DISPLAY_NAME" --format="value(name)" 2>/dev/null | head -1)
  fi
  if [[ -n "$KEY_NAME" ]]; then
    API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)" --project="$PROJECT" 2>/dev/null || true)
  fi
  if [[ -z "$API_KEY" ]]; then
    echo "Gagal auto-dapat API key. Bikin manual: Console -> APIs & Services -> Credentials -> Create API key"
    echo "Lalu jalankan: API_KEY=<key> bash $0"
    exit 1
  fi
  echo "API key didapat lewat gcloud (${#API_KEY} karakter)."
  echo "CATATAN: checkpoint Task 1 kadang hanya hijau kalau key dibuat lewat console."
fi
export API_KEY
[[ -n "$API_KEY" ]] || { echo "API_KEY kosong."; exit 1; }

# ----------------------------------------------------------------- Task 1: bucket & public
step "Task 1: Cek bucket dan image"
if ! gcloud storage ls "gs://$BUCKET/" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket gs://$BUCKET tidak ditemukan. Cek nama bucket di panel lab."
  gcloud storage ls --project="$PROJECT" | head -n 20
  exit 1
fi
gcloud storage ls "gs://$BUCKET/" --project="$PROJECT"

# Ambil file image pertama di bucket (lab hanya ada 1 image)
IMG_URI=$(gcloud storage ls "gs://$BUCKET/**" --project="$PROJECT" 2>/dev/null | head -1)
if [[ -z "$IMG_URI" ]]; then
  IMG_URI=$(gcloud storage ls "gs://$BUCKET/" --project="$PROJECT" 2>/dev/null | head -1)
fi
IMG_URI=$(echo "$IMG_URI" | tr -d '\r' | xargs)
[[ -n "$IMG_URI" ]] || { echo "Tidak ada object di gs://$BUCKET/"; exit 1; }
echo "Image: $IMG_URI"

step "Task 1: Buat object public"
# Coba IAM dulu (bucket uniform), fallback ke ACL
if ! gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member=allUsers --role=roles/storage.objectViewer --project="$PROJECT" 2>/dev/null; then
  echo "IAM binding gagal, coba ACL..."
  gcloud storage objects update "$IMG_URI" --add-acl-grant=entity=AllUsers,role=READER --project="$PROJECT" 2>/dev/null || \
    gsutil acl ch -u AllUsers:R "$IMG_URI" 2>/dev/null || true
fi
echo "Public check done."

# ----------------------------------------------------------------- Task 2: TEXT_DETECTION
step "Task 2: TEXT_DETECTION -> text-response.json"
cat > request.json <<EOF
{
  "requests": [
      {
        "image": {
          "source": {
              "gcsImageUri": "$IMG_URI"
          }
        },
        "features": [
          {
            "type": "TEXT_DETECTION",
            "maxResults": 10
          }
        ]
      }
  ]
}
EOF
cat request.json
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json "https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" -o text-response.json
echo "--- text-response.json (head 800) ---"
head -c 800 text-response.json; echo
if ! grep -q "textAnnotations\|fullTextAnnotation\|responses" text-response.json; then
  echo "WARNING: text-response.json tidak terlihat valid. Isi lengkap:"
  cat text-response.json
fi
gcloud storage cp text-response.json "gs://$BUCKET/" --project="$PROJECT"
echo "Upload text-response.json selesai."
gcloud storage ls "gs://$BUCKET/text-response.json" --project="$PROJECT"

# ----------------------------------------------------------------- Task 3: LANDMARK_DETECTION
step "Task 3: LANDMARK_DETECTION -> landmark-response.json"
cat > request.json <<EOF
{
  "requests": [
      {
        "image": {
          "source": {
              "gcsImageUri": "$IMG_URI"
          }
        },
        "features": [
          {
            "type": "LANDMARK_DETECTION",
            "maxResults": 10
          }
        ]
      }
  ]
}
EOF
cat request.json
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json "https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" -o landmark-response.json
echo "--- landmark-response.json (head 800) ---"
head -c 800 landmark-response.json; echo
if ! grep -q "landmarkAnnotations\|responses" landmark-response.json; then
  echo "WARNING: landmark-response.json tidak terlihat valid. Isi lengkap:"
  cat landmark-response.json
fi
gcloud storage cp landmark-response.json "gs://$BUCKET/" --project="$PROJECT"
echo "Upload landmark-response.json selesai."
gcloud storage ls "gs://$BUCKET/landmark-response.json" --project="$PROJECT"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk:
  Task 1 - Verify resources (API key + public bucket)
  Task 2 - TEXT_DETECTION (text-response.json)
  Task 3 - LANDMARK_DETECTION (landmark-response.json)

File lokal: request.json, text-response.json, landmark-response.json
File di bucket: gs://$BUCKET/text-response.json , gs://$BUCKET/landmark-response.json
==============================================================
EOF
