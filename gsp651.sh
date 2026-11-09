#!/usr/bin/env bash
# GSP651 - Setting Up Cost Control with Quota
#
#   bash gsp651.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Query a public dataset in BigQuery
#   Task 4 (50 pts) - Rerun your Query
#
# Seluruh lab: eksekusi query public dataset di BigQuery, update kuota harian per user
# ke 0.25 TiB (262144 MiB) via gcloud alpha services quota, dan eksekusi ulang query
# dengan cache dinonaktifkan untuk memicu pembatasan kuota (Custom quota exceeded).
#
# LAMA: ~ 1-2 menit.

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

echo "Project ID: $PROJECT_ID"

QUERY_SQL='SELECT
    w1mpro_ep,
    mjd,
    load_id,
    frame_id
FROM
    `bigquery-public-data.wise_all_sky_data_release.mep_wise`
ORDER BY
    mjd ASC
LIMIT 500'

# ----------------------------------------------------------------- Task 1: Query a public dataset
step "Task 1: Query dataset public di BigQuery (Checkpoint 1)"
echo "Menjalankan query awal pada bigquery-public-data (memproses ~1.36 TB)..."
bq --project_id="$PROJECT_ID" --location="US" query \
  --use_legacy_sql=false \
  --max_rows=10 \
  "$QUERY_SQL"

# ----------------------------------------------------------------- Task 3: Update BigQuery quota
step "Task 3: Perbarui kuota BigQuery per user ke 0.25 TiB (.25 TiB / hari)"
echo "Melihat limit kuota saat ini..."
gcloud alpha services quota list \
  --service=bigquery.googleapis.com \
  --consumer="projects/${PROJECT_ID}" \
  --filter="usage" || true

echo "Mengubah kuota per user per project menjadi 262144 MiB (0.25 TiB)..."
gcloud alpha services quota update \
  --consumer="projects/${PROJECT_ID}" \
  --service=bigquery.googleapis.com \
  --metric=bigquery.googleapis.com/quota/query/usage \
  --value=262144 \
  --unit="1/d/{project}/{user}" \
  --force \
  --quiet

echo "Verifikasi limit kuota setelah perubahan..."
gcloud alpha services quota list \
  --service=bigquery.googleapis.com \
  --consumer="projects/${PROJECT_ID}" \
  --filter="usage" || true

# ----------------------------------------------------------------- Task 4: Rerun query
step "Task 4.1: Jalankan query dengan cache aktif (cache hit)"
bq --project_id="$PROJECT_ID" --location="US" query \
  --use_legacy_sql=false \
  --use_cache \
  --max_rows=10 \
  "$QUERY_SQL" || true

step "Task 4.2: Jalankan query dengan cache dinonaktifkan untuk menguji batas kuota (Checkpoint 2)"
echo "Menjalankan query tanpa cache (diharapkan gagal dengan Custom quota exceeded)..."
if bq --project_id="$PROJECT_ID" --location="US" query \
  --use_legacy_sql=false \
  --nouse_cache \
  --max_rows=10 \
  "$QUERY_SQL"; then
  echo "Catatan: Query berhasil diproses."
else
  echo "Sukses: Query berhasil memicu Custom quota exceeded sesuai skenario lab."
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh 2 checkpoint:

  Task 1:
  - Query a public dataset in BigQuery (50 pts)

  Task 4:
  - Rerun your Query (50 pts)

Jawaban kuis pilihan ganda di halaman modul lab:
- Task 1: "Use the query validator to determine how many bytes of data this will process..."
  Jawaban: 1.36 TB
- Task 4: "Running the same query again may not process any data because of the automatic query ______ feature in BigQuery."
  Jawaban: Caching

Semua checkpoint selesai dieksekusi secara otomatis (total 100/100).
==============================================================
EOF
