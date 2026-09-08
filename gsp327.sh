#!/usr/bin/env bash
# GSP327 - Engineer Data for Predictive Modeling with BigQuery ML: Challenge Lab
#
#   bash gsp327.sh
#
# Checkpoint:
#   Task 1 - Bersihkan historical_taxi_rides_raw -> tabel baru (dataset taxirides)
#   Task 2 - Model BQML linear_reg bernama Fare, RMSE <= 10
#   Task 3 - ML.PREDICT ke 2015_fare_amount_predictions
#
# Semua operasi BigQuery lewat REST API (jobs.query), bukan CLI bq.
# Beberapa nilai (nama tabel bersih, kolom target, threshold) berbeda per
# instance lab, ikuti angka yang tampil di halaman BigQuery lab.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

DATASET="taxirides"
RAW="historical_taxi_rides_raw"

API="https://bigquery.googleapis.com/bigquery/v2"
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
CT="Content-Type: application/json"

dbg() {
  echo "  >>> $1" >&2
  local summary; summary=$(echo "$2" | jq -r 'if .error then "ERROR: "+.error.message else "OK" end' 2>/dev/null || echo "RAW: $(echo "$2" | head -c 200)")
  echo "  <<< $summary" >&2
}

post() { local r; r=$(curl -s -X POST "$1" -H "$AUTH" -H "$CT" -d "$2"); dbg "POST $1" "$r"; echo "$r"; }
get()  { local r; r=$(curl -s "${API}/$1" -H "$AUTH"); dbg "GET ${API}/$1" "$r"; echo "$r"; }

# wait_job <job-id> — poll jobs.get sampai DONE, batas 40 x 15s = 10 menit.
JOB_MAX_POLL="${JOB_MAX_POLL:-40}"
wait_job() {
  local job_id=$1 st i err
  for (( i = 1; i <= JOB_MAX_POLL; i++ )); do
    st=$(get "projects/${PROJECT_ID}/jobs/${job_id}" | jq -r '.status.state // "UNKNOWN"')
    echo "  -> $st ($i/$JOB_MAX_POLL)"
    case "$st" in
      DONE)
        err=$(get "projects/${PROJECT_ID}/jobs/${job_id}" | jq -r '.status.errorResult.message // empty')
        if [[ -n "$err" ]]; then echo "QUERY FAILED: $err"; return 1; fi
        return 0 ;;
      FAILED) echo "ABORTED: $st"; return 1 ;;
    esac
    sleep 15
  done
  echo "TIMEOUT: job belum DONE setelah $JOB_MAX_POLL polling. Cek manual di Console."
  return 1
}

# run_bq <label> <query> — jalankan query, pasti selesai (sync atau poll).
# DDST: job async butuh jobs.get + queries.get buffered; helper bq_value
# menangani pengembalian hasil, run_bq cukup menjamin selesai.
run_bq() {
  local label=$1 query=$2 r jid
  r=$(post "projects/${PROJECT_ID}/queries" "$(jq -n --arg q "$query" '{query:$q, useLegacySql:false, timeoutMs:10000}')")
  if [[ "$(echo "$r" | jq -r '.jobComplete // false')" == "true" ]]; then
    return 0
  fi
  jid=$(echo "$r" | jq -r '.jobReference.jobId // empty')
  if [[ -z "$jid" ]]; then echo "Tidak dapat jobId: $(echo "$r" | jq -r '.error.message // "?"')"; return 1; fi
  wait_job "$jid"
}

# bq_value <label> <query> — jalankan query, ambil nilai sel (f[0].v) baris pertama.
# Hasil sync ada di response POST; hasil async diambil dari endpoint queries.get.
bq_value() {
  local label=$1 query=$2 r jid
  r=$(post "projects/${PROJECT_ID}/queries" "$(jq -n --arg q "$query" '{query:$q, useLegacySql:false, timeoutMs:10000}')")
  if [[ "$(echo "$r" | jq -r '.jobComplete // false')" == "true" ]]; then
    echo "$r" | jq -r '.rows[0].f[0].v // empty' 2>/dev/null || true
    return 0
  fi
  jid=$(echo "$r" | jq -r '.jobReference.jobId // empty')
  [[ -n "$jid" ]] || { echo "Tidak dapat jobId."; return 1; }
  wait_job "$jid" || return 1
  get "projects/${PROJECT_ID}/queries/${jid}" | jq -r '.rows[0].f[0].v // empty' 2>/dev/null || true
}

step() { echo; echo "==== $1 ===="; }

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

ask TABLE "taxi_training_data" "Nama tabel hasil bersih (lihat instruksi lab)"
ask FARE_COL "fare_amount" "Nama kolom target (Fare amount di instruksi)"
ask TRIP_DIST "2" "trip_distance harus lebih besar dari"
ask FARE_MIN "3" "fare_amount minimum dalam dollar"
ask PASS_MIN "2" "passenger_count harus lebih besar dari"
ask MODEL "Fare" "Nama model"

step "Tunggu historical_taxi_rides_raw terisi (1-3 menit)"
for _i in {1..12}; do
  if get "projects/${PROJECT_ID}/datasets/${DATASET}/tables/${RAW}" | jq -e '.id' >/dev/null 2>&1; then
    echo "Tabel raw sudah ada."
    break
  fi
  sleep 10
done

step "Task 1: buat tabel bersih $TABLE"
run_bq "create clean table" "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET.$TABLE\` AS
SELECT
  (tolls_amount + fare_amount) AS $FARE_COL,
  pickup_datetime,
  pickup_longitude AS pickuplon,
  pickup_latitude AS pickuplat,
  dropoff_longitude AS dropofflon,
  dropoff_latitude AS dropofflat,
  passenger_count AS passengers
FROM \`$PROJECT_ID.$DATASET.$RAW\`
WHERE
  RAND() < 0.001
  AND trip_distance > $TRIP_DIST
  AND fare_amount >= $FARE_MIN
  AND pickup_longitude > -78 AND pickup_longitude < -70
  AND dropoff_longitude > -78 AND dropoff_longitude < -70
  AND pickup_latitude > 37 AND pickup_latitude < 45
  AND dropoff_latitude > 37 AND dropoff_latitude < 45
  AND passenger_count > $PASS_MIN
"
_RC=$(bq_value "rowcount clean" "SELECT COUNT(*) FROM \`$PROJECT_ID.$DATASET.$TABLE\`")
echo "Baris tabel bersih: $_RC (harus di bawah 1 juta)"

step "Task 2: buat model $MODEL (linear_reg, RMSE target <= 10)"
run_bq "create model" "
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET.$MODEL\`
TRANSFORM(
  * EXCEPT(pickup_datetime),
  ST_Distance(ST_GeogPoint(pickuplon, pickuplat), ST_GeogPoint(dropofflon, dropofflat)) AS euclidean,
  CAST(EXTRACT(DAYOFWEEK FROM pickup_datetime) AS STRING) AS dayofweek,
  CAST(EXTRACT(HOUR FROM pickup_datetime) AS STRING) AS hourofday
)
OPTIONS(input_label_cols=['$FARE_COL'], model_type='linear_reg')
AS
SELECT * FROM \`$PROJECT_ID.$DATASET.$TABLE\`
"
_RMSE=$(bq_value "evaluate model" "SELECT SQRT(mean_squared_error) FROM ML.EVALUATE(MODEL \`$PROJECT_ID.$DATASET.$MODEL\`)")
echo "RMSE model: $_RMSE"

step "Task 3: batch prediction ke 2015_fare_amount_predictions"
run_bq "predict" "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET.2015_fare_amount_predictions\` AS
SELECT * FROM ML.PREDICT(MODEL \`$PROJECT_ID.$DATASET.$MODEL\`, (
  SELECT * FROM \`$PROJECT_ID.$DATASET.report_prediction_data\`
))
"

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a cleaned copy of the data in $TABLE"
echo "  Task 2 - Create BigQuery ML model $MODEL with RMSE 10 or less"
echo "  Task 3 - Perform batch predictions and store in a new table 2015_fare_amount_predictions"