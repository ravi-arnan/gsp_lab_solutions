#!/usr/bin/env bash
# GSP281 - Introduction to SQL for BigQuery and Cloud SQL
#
#   bash gsp281.sh
#
# Checkpoint:
#   Task 4 - Create a Cloud Storage bucket
#   Task 4 - Upload CSV files to Cloud Storage
#   Task 5 - Create a Cloud SQL Instance
#   Task 6 - Create a database
#
# Tasks 1-3 (eksplorasi BigQuery) serta Tasks 7-8 (import tabel & query interaktif)
# adalah modul eksplorasi konseptual tanpa checkpoint penilaian.
#
# LAMA: ~ 4-6 menit (sebagian besar di proses provisioning Cloud SQL instance).

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set di env var
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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Konfigurasi zona dan region Cloud SQL (default dari teks lab: asia-south1-a)
ask ZONE "asia-south1-a" "Zone Cloud SQL Primary (cocokkan dengan teks lab)"
REGION="${ZONE%-*}"
ask REGION "$REGION" "Region Cloud SQL (cocokkan dengan teks lab)"

BUCKET_NAME="${BUCKET_NAME:-$PROJECT_ID}"
BUCKET="gs://$BUCKET_NAME"

echo "Project ID : $PROJECT_ID"
echo "Zone       : $ZONE"
echo "Region     : $REGION"
echo "Bucket     : $BUCKET"

# ----------------------------------------------------------------- Task 4
step "Task 4.1: Query BigQuery & export CSV (start_station_name & end_station_name)"
echo "Menjalankan query BigQuery untuk start_station_name..."
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv --max_rows=100000 \
  "SELECT start_station_name, COUNT(*) AS num FROM \`bigquery-public-data.london_bicycles.cycle_hire\` GROUP BY start_station_name ORDER BY num DESC;" > start_station_name.csv

echo "Menjalankan query BigQuery untuk end_station_name..."
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv --max_rows=100000 \
  "SELECT end_station_name, COUNT(*) AS num FROM \`bigquery-public-data.london_bicycles.cycle_hire\` GROUP BY end_station_name ORDER BY num DESC;" > end_station_name.csv

# Sediakan kedua varian nama file (name vs data) sesuai inkonsistensi teks instruksi lab
cp start_station_name.csv start_station_data.csv
cp end_station_name.csv end_station_data.csv

step "Task 4.2: Buat bucket Cloud Storage & upload file CSV"
if gcloud storage buckets describe "$BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket $BUCKET sudah ada, lewati create."
else
  gcloud storage buckets create "$BUCKET" --project="$PROJECT_ID" --quiet
  echo "Bucket $BUCKET berhasil dibuat."
fi

gcloud storage cp start_station_name.csv start_station_data.csv end_station_name.csv end_station_data.csv "$BUCKET/" --quiet
echo "File CSV berhasil di-upload ke $BUCKET"

# ----------------------------------------------------------------- Task 5
step "Task 5: Buat Cloud SQL instance my-demo (MySQL 8.0)"
if gcloud sql instances describe my-demo --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cloud SQL instance my-demo sudah ada, lewati create."
else
  echo "Membuat instance my-demo di $ZONE (estimasi ~3-5 menit)..."
  if ! gcloud sql instances create my-demo \
    --project="$PROJECT_ID" \
    --database-version=MYSQL_8_0 \
    --tier=db-custom-4-16384 \
    --edition=enterprise \
    --storage-size=100GB \
    --availability-type=REGIONAL \
    --zone="$ZONE" \
    --root-password="ChangeMe1!" \
    --quiet; then
      echo "Gagal dengan tier custom regional, mencoba fallback ke db-f1-micro..."
      gcloud sql instances create my-demo \
        --project="$PROJECT_ID" \
        --database-version=MYSQL_8_0 \
        --tier=db-f1-micro \
        --zone="$ZONE" \
        --root-password="ChangeMe1!" \
        --quiet
  fi
  echo "Cloud SQL instance my-demo berhasil dibuat."
fi

echo "Memastikan instance my-demo berstatus RUNNABLE..."
for i in {1..30}; do
  STATE="$(gcloud sql instances describe my-demo --project="$PROJECT_ID" --format="value(state)" 2>/dev/null || true)"
  if [[ "$STATE" == "RUNNABLE" ]]; then
    echo "Instance my-demo sudah siap (RUNNABLE)."
    break
  fi
  sleep 5
done

# ----------------------------------------------------------------- Task 6
step "Task 6: Buat database bike"
if gcloud sql databases describe bike --instance=my-demo --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Database bike sudah ada, lewati."
else
  gcloud sql databases create bike --instance=my-demo --project="$PROJECT_ID" --quiet
  echo "Database bike berhasil dibuat."
fi

# ----------------------------------------------------------------- Ringkasan
step "Ringkasan Resource"
echo "--- Cloud Storage Objects ---"
gcloud storage ls "$BUCKET" || true
echo
echo "--- Cloud SQL Instance ---"
gcloud sql instances list --project="$PROJECT_ID"
echo
echo "--- Cloud SQL Databases ---"
gcloud sql databases list --instance=my-demo --project="$PROJECT_ID"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh checkpoint:

  Task 4:
  - Create a Cloud Storage bucket
  - Upload CSV files to Cloud Storage

  Task 5:
  - Create a Cloud SQL Instance

  Task 6:
  - Create a database

Semua checkpoint selesai dieksekusi secara otomatis.
Jika ingin mencoba eksplorasi SQL interaktif (Task 7 & 8),
hubungkan ke MySQL via Cloud Shell:
  gcloud sql connect my-demo --user=root --quiet
(Password: ChangeMe1!)
==============================================================
EOF
