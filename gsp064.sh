#!/usr/bin/env bash
# GSP064 - Manage Access Control with IAM
#
#   bash gsp064.sh
#
# Checkpoint:
#   Task 2 - Create a bucket and upload a sample file
#   Task 3 - Remove project access
#   Task 4 - Add Cloud Storage permissions
#
# LAMA: < 15 detik.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

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

ACCOUNT="${ACCOUNT:-$(gcloud config get-value account 2>/dev/null || true)}"

# Deteksi Username 2 dari IAM policy project (user student-* selain user aktif)
USER2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' --format='value(bindings.members)' \
  --filter='bindings.role=roles/viewer' 2>/dev/null \
  | sed -n 's/^user://p' | grep -v "^$ACCOUNT$" | head -n1 || true)"

if [[ -z "$USER2_DEFAULT" ]]; then
  USER2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null \
    | sed -n 's/^user://p' | grep '^student-' | grep -v "^$ACCOUNT$" | head -n1 || true)"
fi

ask USER_2 "$USER2_DEFAULT" "Email Username 2 (dari Lab Connection panel)"
[[ -n "$USER_2" ]] || { echo "Username 2 tidak terdeteksi. Jalankan dengan: USER_2=<email> bash gsp064.sh"; exit 1; }

BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-bucket}"
BUCKET="gs://$BUCKET_NAME"

echo "Project   : $PROJECT_ID"
echo "Username 1: $ACCOUNT"
echo "Username 2: $USER_2"
echo "Bucket    : $BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Task 2: Buat Cloud Storage bucket & upload sample.txt
step "Task 2: Buat bucket $BUCKET & upload sample.txt"
if gcloud storage buckets describe "$BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket $BUCKET sudah ada, lewati."
else
  gcloud storage buckets create "$BUCKET/" --location=US --project="$PROJECT_ID"
  echo "Bucket $BUCKET berhasil dibuat."
fi

echo "Sample file content for IAM verification." > /tmp/sample.txt
gcloud storage cp /tmp/sample.txt "$BUCKET/sample.txt" 2>/dev/null || gsutil cp /tmp/sample.txt "$BUCKET/sample.txt"
echo "File sample.txt berhasil di-upload ke $BUCKET/sample.txt"

# Task 3: Hapus Project Viewer role untuk Username 2
step "Task 3: Remove Project Viewer role untuk $USER_2"
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER_2" \
  --role="roles/viewer" \
  --quiet 2>/dev/null || true
echo "Role roles/viewer berhasil dihapus dari $USER_2"

# Task 4: Tambahkan Storage Object Viewer role untuk Username 2
step "Task 4: Grant Storage Object Viewer role untuk $USER_2"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER_2" \
  --role="roles/storage.objectViewer" \
  --quiet
echo "Role roles/storage.objectViewer berhasil diberikan ke $USER_2"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk ketiga checkpoint:

  Task 2 - Create a bucket and upload a sample file
  Task 3 - Remove project access
  Task 4 - Add Cloud Storage permissions

Semua langkah selesai dieksekusi dari akun Username 1 (Owner).
==============================================================
EOF
