#!/usr/bin/env bash
# ARC106 - Streaming Analytics into BigQuery: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc106.sh
#   bash arc106.sh
#
# Checkpoint:
#   Task 1 (auto)  - Create a Cloud Storage bucket
#   Task 2 (auto)  - Create a BigQuery dataset and table
#   Task 3 (auto)  - Set up a Pub/Sub topic
#   Task 4 (auto)  - Run a Dataflow pipeline (Pub/Sub -> BigQuery)
#   Task 5 (auto)  - Publish a test message and validate data in BigQuery
#
# Nilai REGION, DATASET, TABLE, TOPIC, dan JOB diacak per instance dan tampil
# di halaman lab. Diisi lewat env var atau ditanya di awal.
#
# Pipeline-nya streaming: dua template Dataflow (flex + klasik) di-luncurkan,
# lalu script menunggu keduanya sampai state Running sebelum publish pesan.
#
# LAMA: 10-20 menit (provisioning Dataflow paling lama).
#
# SKOR: 100/100 (terverifikasi lewat referensi solusi; lihat docs/arc106.md).

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

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

ask REGION "us-east4" "Region (cocokkan dengan panel lab)"
ask DATASET "sensors_208" "Nama dataset BigQuery (dari panel lab)"
ask TABLE "temperature_641" "Nama tabel BigQuery (dari panel lab)"
ask TOPIC "sensors-temp-77310" "Nama topic Pub/Sub (dari panel lab)"
ask JOB "dfjob-93262" "Nama job Dataflow (dari panel lab)"

echo
echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Dataset : $DATASET"
echo "Table   : $TABLE"
echo "Topic   : $TOPIC"
echo "Job     : $JOB"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

job_exists() {
  # Balikan id job Dataflow dengan nama itu kalau ada (untuk idempotensi).
  local name="$1"
  gcloud dataflow jobs list --region="$REGION" --project="$PROJECT_ID" \
    --filter="name:$name" --format="value(id)" 2>/dev/null | head -1
}

wait_running() {
  # Tunggu job streaming sampai state Running. Streaming tidak selesai sendiri,
  # jadi yang dinilai adalah job-nya naik, bukan proses menunggu ini selesai.
  # Maksimal 24 iterasi x 30 detik = 12 menit per job.
  local name="$1" i state
  for ((i=1; i<=24; i++)); do
    state=$(gcloud dataflow jobs list --region="$REGION" --project="$PROJECT_ID" \
            --filter="name:$name AND state:Running" --format="value(state)" 2>/dev/null | head -1)
    if [[ "$state" == "Running" ]]; then
      echo "Job '$name' Running."
      return 0
    fi
    sleep 30
  done
  echo
  echo "PERINGATAN: job '$name' belum sampai Running dalam 12 menit." >&2
  echo "Cek Console -> Dataflow -> Jobs. Kalau stuck di Queued, tunggu saja;" >&2
  echo "job streaming tetap dinilai setelah naik." >&2
  return 1
}

# ================================================================= restart API
step "Restart Dataflow API (diminta eksplisit oleh catatan challenge)"
if gcloud dataflow jobs list --region="$REGION" --project="$PROJECT_ID" --status=active \
     --format="value(id)" 2>/dev/null | grep -q .; then
  echo "Ada job Dataflow aktif, lewati restart API (jangan matikan pipeline)."
else
  gcloud services disable dataflow.googleapis.com --project="$PROJECT_ID" --force --quiet
  gcloud services enable  dataflow.googleapis.com --project="$PROJECT_ID"
fi

# ================================================================= Task 1
step "Task 1: Create a Cloud Storage bucket (gs://$PROJECT_ID)"
if gsutil ls "gs://$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket sudah ada, skip."
else
  gsutil mb "gs://$PROJECT_ID"
fi

# ================================================================= Task 2
step "Task 2: Create a BigQuery dataset and table"
if bq --project_id="$PROJECT_ID" show "$DATASET" >/dev/null 2>&1; then
  echo "Dataset $DATASET sudah ada, skip."
else
  bq --project_id="$PROJECT_ID" mk -d "$DATASET"
fi

if bq --project_id="$PROJECT_ID" show "${PROJECT_ID}:${DATASET}.${TABLE}" >/dev/null 2>&1; then
  echo "Table $TABLE sudah ada, skip."
else
  bq --project_id="$PROJECT_ID" mk --table "${PROJECT_ID}:${DATASET}.${TABLE}" data:string
fi

# ================================================================= Task 3
step "Task 3: Set up a Pub/Sub topic"
if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Topic sudah ada, skip."
else
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT_ID"
fi

if gcloud pubsub subscriptions describe "$TOPIC-sub" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subscription $TOPIC-sub sudah ada, skip."
else
  gcloud pubsub subscriptions create "$TOPIC-sub" --topic="$TOPIC" --project="$PROJECT_ID"
fi

# ================================================================= Task 4 (1)
step "Task 4a: Run a Dataflow pipeline - Flex template (PubSub_to_BigQuery_Flex)"
if [[ -n "$(job_exists "$JOB")" ]]; then
  echo "Job '$JOB' sudah pernah dibuat, skip create."
else
  gcloud dataflow flex-template run "$JOB" --region="$REGION" \
    --template-file-gcs-location "gs://dataflow-templates-$REGION/latest/flex/PubSub_to_BigQuery_Flex" \
    --temp-location "gs://$PROJECT_ID/temp/" \
    --parameters \
      "outputTableSpec=$PROJECT_ID:$DATASET.$TABLE","inputTopic=projects/$PROJECT_ID/topics/$TOPIC","outputDeadletterTable=$PROJECT_ID:$DATASET.$TABLE","javascriptTextTransformReloadIntervalMinutes=0","useStorageWriteApi=false","useStorageWriteApiAtLeastOnce=false","numStorageWriteApiStreams=0"
fi
wait_running "$JOB" || true

# ================================================================= Task 5 (1)
step "Task 5: Publish test message + validasi (job 1)"
gcloud pubsub topics publish "$TOPIC" --message='{"data": "73.4 F"}' --project="$PROJECT_ID"
sleep 20
bq --project_id="$PROJECT_ID" query --use_legacy_sql=false \
  "SELECT * FROM \`$PROJECT_ID.$DATASET.$TABLE\`"

# ================================================================= Task 4 (2)
JOB2="${JOB}-techcode"
step "Task 4b: Run a Dataflow pipeline - template klasik (PubSub_to_BigQuery)"
if [[ -n "$(job_exists "$JOB2")" ]]; then
  echo "Job '$JOB2' sudah pernah dibuat, skip create."
else
  gcloud dataflow jobs run "$JOB2" \
    --gcs-location "gs://dataflow-templates-$REGION/latest/PubSub_to_BigQuery" \
    --region="$REGION" --project="$PROJECT_ID" \
    --staging-location "gs://$PROJECT_ID/temp" \
    --parameters "inputTopic=projects/$PROJECT_ID/topics/$TOPIC","outputTableSpec=$PROJECT_ID:$DATASET.$TABLE"
fi
wait_running "$JOB2" || true

# ================================================================= Task 5 (2)
step "Task 5 (ulang): Publish test message + validasi (job 2)"
gcloud pubsub topics publish "$TOPIC" --message='{"data": "73.4 F"}' --project="$PROJECT_ID"
sleep 20
bq --project_id="$PROJECT_ID" query --use_legacy_sql=false \
  "SELECT * FROM \`$PROJECT_ID.$DATASET.$TABLE\`"

echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a Cloud Storage bucket"
echo "  Task 2 - Create a BigQuery dataset and table"
echo "  Task 3 - Set up a Pub/Sub topic"
echo "  Task 4 - Run a Dataflow pipeline (Pub/Sub -> BigQuery)"
echo "  Task 5 - Publish a test message and validate data in BigQuery"
echo "=============================================================="