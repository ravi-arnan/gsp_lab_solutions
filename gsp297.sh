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
sleep 15
gsutil rm "gs://$BUCKET/dummy_transactions"
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
gsutil rm "gs://$BUCKET/dummy_loan"
echo ""
echo "Klik Check my progress: Task 5 - Create Event-based holds"

# ----------------------------------------------------------------- Cleanup
step "Cleanup: Hapus bucket kosong"
gsutil rb "gs://$BUCKET/"

cat <<EOF

==============================================================
SELESAI. Semua checkpoint sudah dikerjakan.
==============================================================
EOF
