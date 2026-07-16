#!/usr/bin/env bash
# GSP340 - Build a Data Warehouse with BigQuery: Challenge Lab
#
# PERINGATAN: challenge lab ini tasknya DIACAK per instance. Nilai di bawah diambil
# dari satu instance spesifik. Cocokkan dengan teks task di lab-mu sebelum jalan,
# kalau beda tinggal ubah variabel di blok ini saja.

set -euo pipefail

# ----------------------------------------------------------------- parameter
DS_PARTITIONED="covid"        # Task 1: dataset baru untuk tabel partisi
DS_MAIN="covid_data"          # Task 2/3/4: dataset (biasanya sudah dibuat lab)
TBL_TRACKER="oxford_policy_tracker"
TBL_AREA="country_area_data"
TBL_MOBILITY="mobility_data"
TBL_BY_COUNTRIES="oxford_policy_tracker_by_countries"   # Task 4: dibuat oleh lab
EXPIRY_DAYS=2175
EXCLUDE="'GBR','BRA','CAN','USA'"

SRC_TRACKER="bigquery-public-data.covid19_govt_response.oxford_policy_tracker"
SRC_AREA="bigquery-public-data.census_bureau_international.country_names_area"
SRC_MOBILITY="bigquery-public-data.covid19_google_mobility.mobility_report"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"   # dataset publik COVID ada di US, harus sama

[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
echo "Project: $PROJECT"

q() { # q "<judul>" "<sql>"
  echo
  echo "=============================================================="
  echo ">> $1"
  echo "=============================================================="
  bq --project_id="$PROJECT" --location="$LOCATION" query \
     --use_legacy_sql=false --format=pretty "$2"
}

# ----------------------------------------------------------------- Task 1
# Satu DDL sekaligus: schema (SELECT *), partisi, expiry, dan populate.
echo ">> Task 1: dataset $DS_PARTITIONED"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d "$DS_PARTITIONED"

q "Task 1: $DS_PARTITIONED.$TBL_TRACKER (partisi date, expiry ${EXPIRY_DAYS}d, exclude $EXCLUDE)" "
CREATE OR REPLACE TABLE \`$DS_PARTITIONED.$TBL_TRACKER\`
PARTITION BY date
OPTIONS(partition_expiration_days=$EXPIRY_DAYS) AS
SELECT * FROM \`$SRC_TRACKER\`
WHERE alpha_3_code NOT IN ($EXCLUDE)
"

# ----------------------------------------------------------------- Task 2
# Dataset ini biasanya sudah disiapkan lab; mk -f aman kalau ternyata belum ada.
echo ">> Task 2: pastikan dataset $DS_MAIN ada"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d "$DS_MAIN"

q "Task 2: $DS_MAIN.$TBL_AREA" "
CREATE OR REPLACE TABLE \`$DS_MAIN.$TBL_AREA\` AS
SELECT * FROM \`$SRC_AREA\`
"

# ----------------------------------------------------------------- Task 3
q "Task 3: $DS_MAIN.$TBL_MOBILITY (tabel besar, sabar)" "
CREATE OR REPLACE TABLE \`$DS_MAIN.$TBL_MOBILITY\` AS
SELECT * FROM \`$SRC_MOBILITY\`
"

# ----------------------------------------------------------------- Task 4
# Tabel ini TIDAK dibuat task 1-3, lab yang menyiapkannya. Cek dulu biar
# pesan errornya jelas kalau provisioning lab belum selesai.
echo
echo ">> Task 4: cek $DS_MAIN.$TBL_BY_COUNTRIES"
if ! bq --project_id="$PROJECT" show --format=none "$DS_MAIN.$TBL_BY_COUNTRIES" 2>/dev/null; then
  echo "ERROR: tabel $DS_MAIN.$TBL_BY_COUNTRIES belum ada."
  echo "Tabel ini dibuat oleh lab, bukan script. Tunggu provisioning selesai,"
  echo "refresh halaman lab, lalu jalankan ulang script ini."
  exit 1
fi

q "Task 4a: hapus population NULL" "
DELETE FROM \`$DS_MAIN.$TBL_BY_COUNTRIES\` WHERE population IS NULL
"

q "Task 4b: hapus country_area NULL" "
DELETE FROM \`$DS_MAIN.$TBL_BY_COUNTRIES\` WHERE country_area IS NULL
"

# ----------------------------------------------------------------- verifikasi
q "Verifikasi: sisa NULL harus 0 semua" "
SELECT
  COUNTIF(population IS NULL)   AS sisa_population_null,
  COUNTIF(country_area IS NULL) AS sisa_country_area_null,
  COUNT(*)                      AS total_baris
FROM \`$DS_MAIN.$TBL_BY_COUNTRIES\`
"

q "Verifikasi: negara yang di-exclude harus 0" "
SELECT COUNT(*) AS harus_nol
FROM \`$DS_PARTITIONED.$TBL_TRACKER\`
WHERE alpha_3_code IN ($EXCLUDE)
"

echo
echo ">> Verifikasi: partisi & expiry $DS_PARTITIONED.$TBL_TRACKER"
bq --project_id="$PROJECT" show --format=prettyjson "$DS_PARTITIONED.$TBL_TRACKER" \
  | grep -A4 timePartitioning

echo
echo "Selesai. Klik Check my progress untuk keempat task."
