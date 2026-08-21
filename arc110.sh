#!/usr/bin/env bash
# ARC110 - Create a Streaming Data Lake on Cloud Storage: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc110.sh
#   bash arc110.sh            # Task 1-4 (semua yang dinilai)
#   bash arc110.sh cleanup    # bersih-bersih, TIDAK dinilai
#
# Checkpoint:
#   Task 1 - Create a Pub/Sub topic          (mytopic)
#   Task 2 - Create a Cloud Scheduler job    (App Engine + job + dijalankan)
#   Task 3 - Create a Cloud Storage bucket   (<PROJECT_ID>-bucket)
#   Task 4 - Run a Dataflow pipeline         (window 2 menit, pd-standard, e2-standard-2)
#
# Isi challenge ini sama dengan GSP903, beda di nama resource dan di dua
# parameter worker yang diminta eksplisit. Lihat docs/gsp903.md untuk latar
# belakang keputusan teknisnya.
#
# Pipeline-nya streaming: perintahnya tidak pernah selesai sendiri. Script
# menjalankannya di latar belakang lalu menunggu job muncul di Dataflow.
#
# LAMA: 10-15 menit, termasuk menunggu file output window pertama.

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

PHASE="${1:-main}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
ZONE="${ZONE:-${REGION}-a}"

# App Engine memakai nama region sendiri: us-central1 -> us-central,
# europe-west1 -> europe-west. Region lain memakai nama yang sama persis.
case "$REGION" in
  us-central1)   AE_REGION="us-central" ;;
  europe-west1)  AE_REGION="europe-west" ;;
  *)             AE_REGION="$REGION" ;;
esac

BUCKET_NAME="${BUCKET_NAME:-${PROJECT}-bucket}"
BUCKET="gs://$BUCKET_NAME"
TOPIC_ID="${TOPIC_ID:-mytopic}"
JOB="publisher-job"
WORKDIR="$HOME/arc110"
VENV="$WORKDIR/venv"

echo "Project  : $PROJECT"
echo "Region   : $REGION (zone $ZONE, App Engine $AE_REGION)"
echo "Bucket   : $BUCKET"
echo "Topic    : $TOPIC_ID"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================= cleanup
if [[ "$PHASE" == "cleanup" ]]; then
  step "Bersih-bersih: hapus semua resource (TIDAK dinilai)"
  echo "Ini menghapus apa yang dinilai keempat checkpoint. Pastikan sudah hijau."

  gcloud scheduler jobs delete "$JOB" --location="$REGION" --quiet || true

  echo ">>> Batalkan job Dataflow yang masih jalan:"
  for ID in $(gcloud dataflow jobs list --region="$REGION" --status=active \
                --format='value(id)' 2>/dev/null); do
    gcloud dataflow jobs cancel "$ID" --region="$REGION" || true
  done

  gcloud pubsub topics delete "$TOPIC_ID" --quiet || true
  gcloud storage rm -r "$BUCKET/samples" 2>/dev/null || true
  gcloud storage rm -r "$BUCKET/temp" 2>/dev/null || true
  gcloud storage buckets delete "$BUCKET" --quiet || true
  exit 0
fi

# ================================================================= checkpoint 1
step "Restart Dataflow API (diminta eksplisit oleh catatan challenge)"
gcloud services disable dataflow.googleapis.com --project="$PROJECT" --force --quiet
gcloud services enable dataflow.googleapis.com --project="$PROJECT"
# Scheduler API dinyalakan di depan supaya 'jobs create' tidak menanyakannya.
gcloud services enable cloudscheduler.googleapis.com --project="$PROJECT"

# ================================================================= Task 1
step "Task 1-3: topic mytopic, App Engine, scheduler job, bucket (checkpoint 1-3)"

if gcloud storage buckets describe "$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "$BUCKET" --project="$PROJECT"
fi

gcloud pubsub topics describe "$TOPIC_ID" --project="$PROJECT" >/dev/null 2>&1 \
  && echo "Topic sudah ada, dilewat." \
  || gcloud pubsub topics create "$TOPIC_ID" --project="$PROJECT"

# Cloud Scheduler masih menuntut app App Engine ada di project.
if gcloud app describe --project="$PROJECT" >/dev/null 2>&1; then
  echo "App Engine app sudah ada, dilewat."
else
  gcloud app create --region="$AE_REGION" --project="$PROJECT"
fi

if gcloud scheduler jobs describe "$JOB" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Scheduler job sudah ada, dilewat."
else
  gcloud scheduler jobs create pubsub "$JOB" \
    --schedule="* * * * *" \
    --topic="$TOPIC_ID" \
    --message-body="Hello Google!" \
    --location="$REGION" \
    --project="$PROJECT"
fi

# ================================================================= checkpoint 3
step "Task 2: jalankan scheduler job"
# RESOURCE_EXHAUSTED sesekali muncul di percobaan pertama, cukup diulang.
for ATTEMPT in 1 2 3; do
  if gcloud scheduler jobs run "$JOB" --location="$REGION" --project="$PROJECT"; then
    break
  fi
  echo "Gagal (percobaan $ATTEMPT), menunggu 20 detik..."
  sleep 20
done

# ================================================================= Task 2-3
step "Task 4: luncurkan pipeline Dataflow (checkpoint 4)"
mkdir -p "$WORKDIR"

# Lab menyuruh clone seluruh python-docs-samples; yang dipakai cuma satu file,
# jadi diambil langsung. Requirements-nya juga cuma apache-beam[gcp].
[[ -f "$WORKDIR/PubSubToGCS.py" ]] || curl -sS -o "$WORKDIR/PubSubToGCS.py" \
  https://raw.githubusercontent.com/GoogleCloudPlatform/python-docs-samples/main/pubsub/streaming-analytics/PubSubToGCS.py

[[ -x "$VENV/bin/python" ]] || python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet 'apache-beam[gcp]==2.72.0'

LOG="$WORKDIR/pipeline.log"
# Pipeline streaming tidak pernah selesai sendiri, jadi dilepas ke latar
# belakang. Yang dinilai adalah job Dataflow-nya sudah naik, bukan proses lokal.
nohup "$VENV/bin/python" "$WORKDIR/PubSubToGCS.py" \
  --project="$PROJECT" \
  --region="$REGION" \
  --input_topic="projects/$PROJECT/topics/$TOPIC_ID" \
  --output_path="$BUCKET/samples/output" \
  --runner=DataflowRunner \
  --window_size=2 \
  --num_shards=2 \
  --temp_location="$BUCKET/temp" \
  --worker_machine_type=e2-standard-2 \
  --worker_disk_type="compute.googleapis.com/projects/$PROJECT/zones/$ZONE/diskTypes/pd-standard" \
  > "$LOG" 2>&1 &
PIPELINE_PID=$!
echo "Pipeline dilepas di latar belakang (PID $PIPELINE_PID), log: $LOG"

echo "Menunggu job muncul di Dataflow (maksimal 10 menit)..."
FOUND=0
for i in $(seq 1 60); do
  STATE=$(gcloud dataflow jobs list --region="$REGION" --project="$PROJECT" \
            --status=active --format='value(state)' --limit=1 2>/dev/null || true)
  if [[ -n "$STATE" ]]; then
    echo "Job Dataflow aktif, state: $STATE"
    FOUND=1
    break
  fi
  if ! kill -0 "$PIPELINE_PID" 2>/dev/null; then
    echo "Proses pipeline berhenti sebelum job naik. 40 baris terakhir log:"
    tail -40 "$LOG"
    exit 1
  fi
  sleep 10
done

gcloud dataflow jobs list --region="$REGION" --project="$PROJECT" \
  --format='table(id,name,state,createTime)' --limit=5

cat <<EOF

--------------------------------------------------------------
$([[ "$FOUND" == "1" ]] && echo "SELESAI!" || echo "Job belum terlihat setelah 10 menit — cek $LOG")

Klik Check my progress untuk keempat task:
  1. Create a Pub/Sub topic
  2. Create a Cloud Scheduler job
  3. Create a Cloud Storage bucket
  4. Run a Dataflow pipeline

Task 4 juga meminta "check which files have been written out". Window-nya
2 menit, jadi file pertama baru muncul beberapa menit setelah job berjalan:

  gcloud storage ls $BUCKET/samples/

Pipeline masih jalan di latar belakang. Setelah semua checkpoint hijau:

  bash $0 cleanup
--------------------------------------------------------------
EOF
