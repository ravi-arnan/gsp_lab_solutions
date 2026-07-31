#!/usr/bin/env bash
# GSP297 - Google Cloud Storage: Bucket Lock
#
# Cara pakai:
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp297.sh
#   bash gsp297.sh
#
# Checkpoint:
#   Task 1 - Create a storage bucket
#   Task 2 - Set up Retention Policy
#   Task 3 - Lock the Retention Policy
#   Task 4 - Set up Temporary Hold
#   Task 5 - Create Event-based holds

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET="$PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Retention 10 detik belum tentu lewat saat rm dipanggil, jadi ulang beberapa kali.
rm_when_expired() {
  for i in 1 2 3 4 5; do
    gsutil rm "$1" && return 0
    echo "Retention belum lewat, tunggu 10 detik (percobaan $i)..."
    sleep 10
  done
  echo "Gagal menghapus $1 setelah 5 percobaan."
  return 1
}

# ----------------------------------------------------------------- Task 1
step "Task 1: Create bucket gs://$BUCKET"
if gsutil ls "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gsutil mb "gs://$BUCKET"
fi
echo ""
echo "Klik Check my progress: Task 1 - Create a storage bucket"

# ----------------------------------------------------------------- Task 2
step "Task 2: Define Retention Policy (10 detik)"
gsutil retention set 10s "gs://$BUCKET"
gsutil retention get "gs://$BUCKET"

gsutil cp gs://spls/gsp297/dummy_transactions "gs://$BUCKET/"
gsutil ls -L "gs://$BUCKET/dummy_transactions"
echo ""
echo "Klik Check my progress: Task 2 - Set up Retention Policy"

# ----------------------------------------------------------------- Task 3
step "Task 3: Lock Retention Policy"
echo y | gsutil retention lock "gs://$BUCKET/"
echo ""
echo "Klik Check my progress: Task 3 - Lock the Retention Policy"

# ----------------------------------------------------------------- Task 4
step "Task 4a: Set Temporary Hold"
gsutil retention temp set "gs://$BUCKET/dummy_transactions"

step "Task 4b: Verifikasi object tidak bisa dihapus"
gsutil rm "gs://$BUCKET/dummy_transactions" 2>&1 || true

step "Task 4c: Release Temporary Hold & Delete"
gsutil retention temp release "gs://$BUCKET/dummy_transactions"
rm_when_expired "gs://$BUCKET/dummy_transactions"
echo ""
echo "Klik Check my progress: Task 4 - Set up Temporary Hold"

# ----------------------------------------------------------------- Task 5
step "Task 5a: Enable default event-based hold"
gsutil retention event-default set "gs://$BUCKET/"
gsutil cp gs://spls/gsp297/dummy_loan "gs://$BUCKET/"
gsutil ls -L "gs://$BUCKET/dummy_loan"

step "Task 5b: Release event-based hold"
gsutil retention event release "gs://$BUCKET/dummy_loan"
gsutil ls -L "gs://$BUCKET/dummy_loan"

step "Task 5c: Hapus object"
# Release event-based hold me-reset retention expiration ke "sekarang + 10s",
# jadi rm pertama pasti 403.
rm_when_expired "gs://$BUCKET/dummy_loan"
echo ""
echo "Klik Check my progress: Task 5 - Create Event-based holds"

cat <<EOF

==============================================================
SELESAI. Semua checkpoint sudah dikerjakan.

Task 6 (hapus bucket) TIDAK dijalankan otomatis: menghapus bucket
membuat checkpoint Task 1, 2, 3, dan 5 jadi merah kalau belum diklik.
Setelah semua checkpoint hijau, jalankan sendiri:

  gsutil rb "gs://$BUCKET/"
==============================================================
EOF
