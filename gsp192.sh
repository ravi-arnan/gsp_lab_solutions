#!/usr/bin/env bash
# GSP192 - Dataflow: Qwik Start - Templates
#
#   bash gsp192.sh
#
# Checkpoint:
#   Task 1 - Disable and re-enable the Dataflow API
#   Task 2 - Create a BigQuery Dataset (name: taxirides)
#   Task 2 - Create a table in BigQuery Dataset (taxirides.realtime)
#   Task 2 - Create a Cloud Storage bucket (gs://<PROJECT_ID>)
#   Task 4 - Run the Pipeline (Dataflow job iotflow)
#
# LAMA: < 1 menit.

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

DEFAULT_REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="europe-west1"
ask REGION "$DEFAULT_REGION" "Region Dataflow (cocokkan teks Task 4)"

GCLOUD=(gcloud "--project=$PROJECT_ID")
BUCKET="gs://$PROJECT_ID"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Bucket : $BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Task 1: Disable dan re-enable Dataflow API (Checkpoint 1)
step "Task 1: Reset Dataflow API (disable lalu enable)"
"${GCLOUD[@]}" services disable dataflow.googleapis.com --force --quiet
"${GCLOUD[@]}" services enable dataflow.googleapis.com --quiet
echo "Dataflow API berhasil di-reset."
sleep 5

# Task 2: BigQuery Dataset, Table, dan GCS Bucket
step "Task 2a: Create BigQuery Dataset (taxirides)"
if bq show --dataset "$PROJECT_ID:taxirides" >/dev/null 2>&1; then
  echo "Dataset taxirides sudah ada, lewati."
else
  bq --location=US mk --dataset "$PROJECT_ID:taxirides"
  echo "Dataset taxirides berhasil dibuat."
fi

step "Task 2b: Create BigQuery Table (taxirides.realtime)"
if bq show --table "$PROJECT_ID:taxirides.realtime" >/dev/null 2>&1; then
  echo "Table realtime sudah ada, lewati."
else
  bq mk \
    --time_partitioning_field timestamp \
    --schema "ride_id:string,point_idx:integer,latitude:float,longitude:float,timestamp:timestamp,meter_reading:float,meter_increment:float,ride_status:string,passenger_count:integer" \
    -t "$PROJECT_ID:taxirides.realtime"
  echo "Table realtime berhasil dibuat."
fi

step "Task 2c: Create Cloud Storage bucket ($BUCKET)"
if gcloud storage buckets describe "$BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket $BUCKET sudah ada, lewati."
else
  gcloud storage buckets create "$BUCKET/" --project="$PROJECT_ID"
  echo "Bucket $BUCKET berhasil dibuat."
fi

# Task 4: Run the pipeline
step "Task 4: Run Dataflow Pipeline (iotflow di $REGION)"
EXISTING_JOB="$("${GCLOUD[@]}" dataflow jobs list --region="$REGION" --filter="name:iotflow AND state:Running" --format="value(id)" 2>/dev/null | head -1 || true)"
if [[ -n "$EXISTING_JOB" ]]; then
  echo "Dataflow job iotflow sudah berjalan (ID: $EXISTING_JOB), lewati."
else
  "${GCLOUD[@]}" dataflow jobs run iotflow \
    --gcs-location "gs://dataflow-templates-${REGION}/latest/PubSub_to_BigQuery" \
    --region "$REGION" \
    --worker-machine-type e2-medium \
    --staging-location "$BUCKET/temp" \
    --parameters "inputTopic=projects/pubsub-public-data/topics/taxirides-realtime,outputTableSpec=$PROJECT_ID:taxirides.realtime"
  echo "Dataflow job iotflow berhasil di-submit."
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk kelima checkpoint:

  Task 1 - Disable and re-enable the Dataflow API
  Task 2 - Create a BigQuery Dataset (name: taxirides)
  Task 2 - Create a table in BigQuery Dataset
  Task 2 - Create a Cloud Storage bucket
  Task 4 - Run the Pipeline

Kuis Task 6 (Test your understanding):
  Q1: Google Cloud Dataflow supports batch processing.
      Jawaban: True

  Q2: Which Dataflow Template used in the lab to run the pipeline?
      Jawaban: Pub/Sub to BigQuery
==============================================================
EOF
