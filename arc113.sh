#!/usr/bin/env bash
# ARC113 - Implement Event-Driven Messaging and Automation Workflows: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc113.sh
#   bash arc113.sh
#
# Checkpoint (varian schema/topic/function):
#   Task 1 - Pub/Sub schema 'city-temp-schema' (AVRO)
#   Task 2 - Topic 'temp-topic' memakai schema 'temperature-schema' yang sudah ada
#   Task 3 - Cloud Run function 'gcf-pubsub' dipicu topic 'gcf-topic'
#
# ARC113 punya beberapa varian task (Cloud Scheduler, snapshot, Pub/Sub Lite).
# Script ini mengerjakan varian schema + topic + function. Kalau panel lab-mu
# menyebut task lain, lihat docs/arc113.md.
#
# LAMA: ~4 menit, hampir semuanya deploy function gen2.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set."; exit 1; }

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

ask REGION "us-central1" "Region untuk Cloud Run function (cocokkan dengan panel lab)"

SCHEMA_NEW="${SCHEMA_NEW:-city-temp-schema}"
SCHEMA_EXISTING="${SCHEMA_EXISTING:-temperature-schema}"
TOPIC="${TOPIC:-temp-topic}"
GCF_TOPIC="${GCF_TOPIC:-gcf-topic}"
FUNCTION="${FUNCTION:-gcf-pubsub}"
SRC="${TMPDIR:-/tmp}/arc113-fn"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

AVRO_DEF='{"type":"record","name":"Avro","fields":[{"name":"city","type":"string"},{"name":"temperature","type":"double"},{"name":"pressure","type":"int"},{"name":"time_position","type":"string"}]}'

step "Enable API"
gcloud services enable \
  pubsub.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  eventarc.googleapis.com \
  logging.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: schema $SCHEMA_NEW"
if gcloud pubsub schemas describe "$SCHEMA_NEW" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Schema sudah ada."
else
  gcloud pubsub schemas create "$SCHEMA_NEW" \
    --type=AVRO \
    --definition="$AVRO_DEF" \
    --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: topic $TOPIC dengan schema $SCHEMA_EXISTING"
# Schema ini seharusnya sudah disiapkan lab. Guard kalau provisioning meleset.
if ! gcloud pubsub schemas describe "$SCHEMA_EXISTING" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Schema $SCHEMA_EXISTING tidak ada, dibuat sendiri."
  gcloud pubsub schemas create "$SCHEMA_EXISTING" \
    --type=AVRO --definition="$AVRO_DEF" --project="$PROJECT"
fi

if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" >/dev/null 2>&1; then
  # Schema tidak bisa ditempel ke topic yang sudah jadi tanpa schema, jadi kalau
  # topic-nya sudah ada tapi tanpa schema, buang dan bikin ulang.
  if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" \
       --format='value(schemaSettings.schema)' | grep -q "$SCHEMA_EXISTING"; then
    echo "Topic sudah ada dengan schema yang benar."
  else
    echo "Topic ada tapi tanpa schema yang diminta, dibuat ulang."
    gcloud pubsub topics delete "$TOPIC" --project="$PROJECT" -q
    gcloud pubsub topics create "$TOPIC" --project="$PROJECT" \
      --schema="$SCHEMA_EXISTING" --message-encoding=json
  fi
else
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT" \
    --schema="$SCHEMA_EXISTING" --message-encoding=json
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Cloud Run function $FUNCTION dipicu $GCF_TOPIC"
gcloud pubsub topics describe "$GCF_TOPIC" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud pubsub topics create "$GCF_TOPIC" --project="$PROJECT"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Deploy gen2 pertama sering gagal karena service agent Eventarc belum punya
# role-nya. Diberikan di depan supaya tidak perlu satu ronde retry.
for ROLE in roles/eventarc.eventReceiver roles/run.invoker roles/artifactregistry.reader; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$COMPUTE_SA" --role="$ROLE" \
    --condition=None >/dev/null
done
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role=roles/iam.serviceAccountTokenCreator --condition=None >/dev/null 2>&1 || true

mkdir -p "$SRC"
cat > "$SRC/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('helloPubSub', (cloudEvent) => {
  const data = cloudEvent.data && cloudEvent.data.message && cloudEvent.data.message.data;
  const message = data ? Buffer.from(data, 'base64').toString() : 'Hello, World';
  console.log(message);
});
EOF
cat > "$SRC/package.json" << 'EOF'
{
  "name": "gcf-pubsub",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.0"
  }
}
EOF

n=1
until gcloud functions deploy "$FUNCTION" \
        --gen2 \
        --runtime=nodejs20 \
        --region="$REGION" \
        --source="$SRC" \
        --entry-point=helloPubSub \
        --trigger-topic="$GCF_TOPIC" \
        --service-account="$COMPUTE_SA" \
        --project="$PROJECT" \
        --quiet; do
  (( n++ >= 4 )) && { echo "Deploy gagal setelah 3 percobaan."; exit 1; }
  echo "Deploy gagal, kemungkinan IAM/service agent belum propagasi. Tunggu 30 detik (percobaan $n)..."
  sleep 30
done

step "Ringkasan"
gcloud pubsub schemas list --project="$PROJECT" --format='table(name,type)'
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" \
  --format='value(name,schemaSettings.schema,schemaSettings.encoding)'
gcloud functions describe "$FUNCTION" --region="$REGION" --project="$PROJECT" \
  --format='value(name,state,eventTrigger.eventType,eventTrigger.pubsubTopic)'

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Schema $SCHEMA_NEW
  Task 2 - Topic $TOPIC memakai schema $SCHEMA_EXISTING
  Task 3 - Function $FUNCTION ($REGION) dipicu topic $GCF_TOPIC
==============================================================
EOF
