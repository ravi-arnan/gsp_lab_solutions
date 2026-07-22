#!/usr/bin/env bash
# GSP340 - Build a Data Warehouse with BigQuery: Challenge Lab (updated)
#
# PERINGATAN: challenge lab ini tasknya DIACAK per instance. Nilai di bawah
# diambil dari satu instance spesifik. Cocokkan dengan teks task di lab-mu
# sebelum jalan, kalau beda tinggal ubah variabel di blok ini saja.

set -euo pipefail

# ----------------------------------------------------------------- parameter
# Task 1
DS_COVID="covid"
TBL_TRACKER="oxford_policy_tracker"
EXPIRY_DAYS=2175
EXCLUDE="'GBR','BRA','CAN','USA'"

# Task 2/3/4
DS_MAIN="covid_data"
TBL_CONSOLIDATED="consolidate_covid_tracker_data"
TBL_WORLDWIDE="oxford_policy_tracker_worldwide"
TBL_POP="pop_data_2019"

# Source datasets
SRC_TRACKER="bigquery-public-data.covid19_govt_response.oxford_policy_tracker"
SRC_MOBILITY="bigquery-public-data.covid19_google_mobility.mobility_report"
SRC_ECDC="bigquery-public-data.covid19_ecdc.covid19_ecdc_table_14d"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"

[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
echo "Project: $PROJECT"

q() {
  echo
  echo "=============================================================="
  echo ">> $1"
  echo "=============================================================="
  bq --project_id="$PROJECT" --location="$LOCATION" query \
     --use_legacy_sql=false --format=pretty "$2"
}

# ----------------------------------------------------------------- Task 1
# Buat dataset covid + tabel oxford_policy_tracker partisi date, expiry 2175d
echo ">> Task 1: dataset $DS_COVID"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d "$DS_COVID"

q "Task 1: $DS_COVID.$TBL_TRACKER (partisi date, expiry ${EXPIRY_DAYS}d)" "
CREATE OR REPLACE TABLE \`$DS_COVID.$TBL_TRACKER\`
PARTITION BY date
OPTIONS(partition_expiration_days=$EXPIRY_DAYS) AS
SELECT * FROM \`$SRC_TRACKER\`
WHERE alpha_3_code NOT IN ($EXCLUDE)
"

# ----------------------------------------------------------------- Task 2
# Populate consolidate_covid_tracker_data dengan mobility data
echo ">> Task 2: pastikan dataset $DS_MAIN ada"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d "$DS_MAIN"

# Cek apakah tabel sudah ada (dibuat oleh lab)
echo ">> Task 2: cek tabel $DS_MAIN.$TBL_CONSOLIDATED"
if ! bq --project_id="$PROJECT" show --format=none "$DS_MAIN.$TBL_CONSOLIDATED" 2>/dev/null; then
  echo "Tabel $DS_MAIN.$TBL_CONSOLIDATED belum ada. Tunggu provisioning..."
  echo "Jalankan ulang script ini setelah tabel muncul di BigQuery."
  exit 1
fi

q "Task 2: update $DS_MAIN.$TBL_CONSOLIDATED dengan mobility data" "
UPDATE \`$DS_MAIN.$TBL_CONSOLIDATED\` AS main
SET
  mobility_data.avg_retail = m.avg_retail,
  mobility_data.avg_grocery = m.avg_grocery,
  mobility_data.avg_parks = m.avg_parks,
  mobility_data.avg_transit = m.avg_transit,
  mobility_data.avg_workplace = m.avg_workplace,
  mobility_data.avg_residential = m.avg_residential
FROM (
  SELECT
    country_region,
    date,
    AVG(retail_and_recreation_percent_change_from_baseline) AS avg_retail,
    AVG(grocery_and_pharmacy_percent_change_from_baseline) AS avg_grocery,
    AVG(parks_percent_change_from_baseline) AS avg_parks,
    AVG(transit_stations_percent_change_from_baseline) AS avg_transit,
    AVG(workplaces_percent_change_from_baseline) AS avg_workplace,
    AVG(residential_percent_change_from_baseline) AS avg_residential
  FROM \`$SRC_MOBILITY\`
  GROUP BY country_region, date
) AS m
WHERE main.country_name = m.country_region
  AND main.date = m.date
"

# ----------------------------------------------------------------- Task 3
# Query missing population & country_area
q "Task 3: missing population & country_area dari $DS_MAIN.$TBL_WORLDWIDE" "
SELECT country_name, 'population' AS missing_field
FROM \`$DS_MAIN.$TBL_WORLDWIDE\`
WHERE population IS NULL
UNION ALL
SELECT country_name, 'country_area' AS missing_field
FROM \`$DS_MAIN.$TBL_WORLDWIDE\`
WHERE country_area IS NULL
ORDER BY country_name, missing_field
"

# ----------------------------------------------------------------- Task 4
# Buat tabel pop_data_2019 dari ECDC dataset
echo ">> Task 4: buat $DS_MAIN.$TBL_POP dari ECDC dataset"
q "Task 4: $DS_MAIN.$TBL_POP" "
CREATE OR REPLACE TABLE \`$DS_MAIN.$TBL_POP\` AS
SELECT * FROM \`$SRC_ECDC\`
"

# ----------------------------------------------------------------- verifikasi
echo
echo "Verifikasi Task 1: partisi & expiry"
bq --project_id="$PROJECT" show --format=prettyjson "$DS_COVID.$TBL_TRACKER" \
  | grep -A4 timePartitioning

echo
echo "Verifikasi Task 1: negara yang di-exclude harus 0"
q "Verifikasi exclude" "
SELECT COUNT(*) AS harus_nol
FROM \`$DS_COVID.$TBL_TRACKER\`
WHERE alpha_3_code IN ($EXCLUDE)
"

echo
echo "Selesai. Klik Check my progress untuk keempat task."
