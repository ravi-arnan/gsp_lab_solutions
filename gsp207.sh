#!/usr/bin/env bash
# GSP207 - Dataflow: Qwik Start - Python
#
#   bash gsp207.sh
#
# Checkpoint:
#   Task 1 - Create a Cloud Storage bucket    (<PROJECT_ID>-bucket, multi-region US)
#   Task 4 - Run an Example Pipeline Remotely (job wordcount SUCCEEDED)
#
# Task 2 (jalankan wordcount lokal) dan Task 5 (kuis) tidak dinilai.
#
# LAMA: 10-15 menit. Sebagian besar di pip install apache-beam dan di job
# Dataflow-nya sendiri; perintah pipeline memang menunggu sampai job selesai.

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "asia-southeast1" "Region Dataflow (cocokkan dengan teks lab)"

BUCKET_NAME="${BUCKET_NAME:-${PROJECT}-bucket}"
BUCKET="gs://$BUCKET_NAME"
BEAM_VERSION="2.67.0"
VENV="$HOME/gsp207-venv"

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Bucket : $BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: buat bucket $BUCKET (checkpoint 1)"
# Teks lab minta Multi-region / us.
if gcloud storage buckets describe "$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "$BUCKET" --location=US --project="$PROJECT"
fi

# ----------------------------------------------------------------- API
step "Restart Dataflow API (disable lalu enable, sesuai instruksi lab)"
# Project lab kadang punya API yang terdaftar aktif tapi belum benar-benar
# siap. Mematikan lalu menyalakan ulang memaksa penyediaannya diulang.
gcloud services disable dataflow.googleapis.com --project="$PROJECT" --force --quiet
gcloud services enable dataflow.googleapis.com --project="$PROJECT"
sleep 20

# ----------------------------------------------------------------- Task 2
step "Task 2: siapkan Apache Beam SDK $BEAM_VERSION"

BEAM_ARGS=(
  --project "$PROJECT"
  --runner DataflowRunner
  --staging_location "$BUCKET/staging"
  --temp_location "$BUCKET/temp"
  --output "$BUCKET/results/output"
  --region "$REGION"
  --worker_machine_type=e2-standard-2
)

# Lab menyuruh masuk ke container python:3.12 karena apache-beam belum tentu
# mendukung Python versi terbaru. Kalau Python di Cloud Shell sudah didukung
# (3.9-3.12), venv lebih cepat: tidak perlu menarik image dulu.
PYMINOR=$(python3 -c 'import sys; print(sys.version_info[1])')
if [[ "$PYMINOR" -ge 9 && "$PYMINOR" -le 12 ]]; then
  echo "Python 3.$PYMINOR didukung, pakai venv."
  USE_DOCKER=0
  [[ -x "$VENV/bin/python" ]] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "apache-beam[gcp]==$BEAM_VERSION"
else
  echo "Python 3.$PYMINOR belum didukung apache-beam, pakai container python:3.12."
  USE_DOCKER=1
  docker pull -q python:3.12
fi

run_pipeline() {
  if [[ "$USE_DOCKER" == "0" ]]; then
    "$VENV/bin/python" -m apache_beam.examples.wordcount "${BEAM_ARGS[@]}"
  else
    docker run --rm -e DEVSHELL_PROJECT_ID="$PROJECT" python:3.12 bash -c \
      "pip install --quiet 'apache-beam[gcp]==$BEAM_VERSION' && python -m apache_beam.examples.wordcount ${BEAM_ARGS[*]}"
  fi
}

# ----------------------------------------------------------------- Task 3
step "Task 3: jalankan wordcount di Dataflow (checkpoint 2, ~8 menit)"
# Perintah ini menunggu sampai job selesai, jadi diamnya lama itu normal.
# Lab sendiri menyuruh mengulang kalau job gagal start — API baru saja
# dinyalakan ulang dan kadang belum siap di percobaan pertama.
for ATTEMPT in 1 2 3; do
  echo ">>> percobaan $ATTEMPT"
  if run_pipeline; then
    break
  fi
  [[ "$ATTEMPT" == "3" ]] && { echo "Tiga percobaan gagal, berhenti."; exit 1; }
  echo "Gagal. Menunggu 45 detik lalu mencoba lagi..."
  sleep 45
done

# ----------------------------------------------------------------- Task 4
step "Task 4: cek hasil"
gcloud dataflow jobs list --region="$REGION" --project="$PROJECT" \
  --format='table(id,name,state,createTime)' --limit=5
echo ">>> Isi $BUCKET/results/:"
gcloud storage ls "$BUCKET/results/" --project="$PROJECT" || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create a Cloud Storage bucket
  2. Run an Example Pipeline Remotely

Pastikan state job di tabel di atas SUCCEEDED sebelum mengklik
checkpoint kedua.

Task 5 (Kuis): "Dataflow temp_location must be a valid Cloud Storage
URL." Jawaban: True
==============================================================
EOF
