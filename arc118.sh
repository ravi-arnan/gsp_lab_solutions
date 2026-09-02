#!/usr/bin/env bash
# ARC118 - Build Event-Driven Applications with Eventarc: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc118.sh
#   bash arc118.sh
#
# Checkpoint:
#   Task 1 - Pub/Sub topic + subscription
#   Task 2 - Cloud Run sink (pubsub-events, gcr.io/cloudrun/hello)
#   Task 3 - Eventarc trigger pubsub-events-trigger (transport-topic) + publish test
#
# Region lab minta europe-west4 untuk semua resource.

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "europe-west4" "Region (cocokkan dengan panel lab)"

# Nama topic/subscription diacak per lab (panel menampilkan nama lengkap).
# Defaultnya <PROJECT_ID>-topic sesuai instruksi ARC118 terbaru.
DEFAULT_TOPIC="${PROJECT_ID}-topic"
ask TOPIC "$DEFAULT_TOPIC" "Pub/Sub topic (cocokkan dengan panel lab)"
ask SUB "${TOPIC}-sub" "Pub/Sub subscription (biasanya <topic>-sub)"
ask SERVICE "pubsub-events" "Cloud Run service name"
ask TRIGGER "pubsub-events-trigger" "Eventarc trigger name"

IMAGE="${IMAGE:-gcr.io/cloudrun/hello}"
TRIGGER_LOCATION="$REGION"
RUN_REGION="$REGION"

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Topic   : $TOPIC (sub: $SUB)"
echo "Service : $SERVICE ($IMAGE)"
echo "Trigger : $TRIGGER"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# ------------------------------------------------------------------ Enable API
step "Enable API (Eventarc, Logging, Cloud Build, Cloud Run, Pub/Sub)"
gcloud services enable \
  eventarc.googleapis.com \
  eventarcpublishing.googleapis.com \
  logging.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT_ID"

# Pub/Sub service agent butuh TokenCreator untuk Eventarc transport
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$PUBSUB_SA" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --condition=None >/dev/null 2>&1 || true

# Eventarc trigger butuh invoker + eventReceiver pada compute SA
for ROLE in roles/eventarc.eventReceiver roles/run.invoker roles/pubsub.subscriber; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" --role="$ROLE" --condition=None >/dev/null 2>&1 || true
done

# ------------------------------------------------------------------ Task 1
step "Task 1: Pub/Sub topic $TOPIC + subscription $SUB"
if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Topic sudah ada, dilewat."
else
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT_ID" -q
fi

if gcloud pubsub subscriptions describe "$SUB" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subscription sudah ada, dilewat."
else
  gcloud pubsub subscriptions create "$SUB" --topic="$TOPIC" --project="$PROJECT_ID" -q
fi

gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" --format='value(name)' || true
gcloud pubsub subscriptions describe "$SUB" --project="$PROJECT_ID" --format='value(name)' || true

# ------------------------------------------------------------------ Task 2
step "Task 2: Cloud Run sink $SERVICE ($IMAGE) di $RUN_REGION"
if gcloud run services describe "$SERVICE" --region="$RUN_REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cloud Run service sudah ada, dilewat deploy."
else
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --region="$RUN_REGION" \
    --project="$PROJECT_ID" \
    --allow-unauthenticated \
    --quiet
fi

# Pastikan service allow unauthenticated (grader kadang cek invoker)
gcloud run services add-iam-policy-binding "$SERVICE" \
  --region="$RUN_REGION" --project="$PROJECT_ID" \
  --member="allUsers" --role="roles/run.invoker" >/dev/null 2>&1 || true

gcloud run services describe "$SERVICE" --region="$RUN_REGION" --project="$PROJECT_ID" --format='value(status.url)' || true

# Tunggu service ready sebelum buat trigger (Eventarc validasi destination)
echo "Menunggu Cloud Run service READY..."
for i in $(seq 1 12); do
  READY="$(gcloud run services describe "$SERVICE" --region="$RUN_REGION" --project="$PROJECT_ID" --format='value(status.conditions[0].status)' 2>/dev/null || echo Unknown)"
  [[ "$READY" == "True" ]] && break
  sleep 10
done

# ------------------------------------------------------------------ Task 3
step "Task 3: Eventarc trigger $TRIGGER (transport-topic=$TOPIC)"

# Hapus trigger lama kalau ada supaya idempoten (ganti transport butuh recreate)
if gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Trigger sudah ada, cek apakah sudah pakai transport-topic yang benar..."
  CUR_TOPIC="$(gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" --format='value(transport.pubsub.topic)' 2>/dev/null || true)"
  if echo "$CUR_TOPIC" | grep -q "$TOPIC"; then
    echo "Trigger sudah pakai topic $TOPIC, dilewat."
  else
    echo "Trigger pakai topic berbeda ($CUR_TOPIC), hapus dan buat ulang..."
    gcloud eventarc triggers delete "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" -q || true
    sleep 10
  fi
fi

if ! gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  # Retry karena IAM propagasi eventReceiver/run.invoker bisa 1-2 menit
  n=1
  until gcloud eventarc triggers create "$TRIGGER" \
          --location="$TRIGGER_LOCATION" \
          --destination-run-service="$SERVICE" \
          --destination-run-region="$RUN_REGION" \
          --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
          --transport-topic="projects/${PROJECT_ID}/topics/${TOPIC}" \
          --service-account="$COMPUTE_SA" \
          --project="$PROJECT_ID"; do
    (( n++ >= 4 )) && { echo "Gagal create trigger setelah 3 percobaan."; exit 1; }
    echo "Create trigger gagal (biasanya IAM belum propagasi), tunggu 30 detik (percobaan $n)..."
    sleep 30
  done
fi

echo "Trigger terbuat, tunggu ACTIVE..."
for i in $(seq 1 18); do
  STATE="$(gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || echo UNKNOWN)"
  echo "  percobaan $i: $STATE"
  [[ "$STATE" == "ACTIVE" ]] && break
  sleep 10
done
gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" || true

step "Task 3b: Publish test message ke $TOPIC"
# Publish memicu Eventarc, delivery ke Cloud Run async ~10-30 detik
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT_ID" --message="Hello from ARC118 - $(date -Is)" || \
  gcloud pubsub topics publish "projects/${PROJECT_ID}/topics/${TOPIC}" --message="Hello from ARC118"

echo "Publish selesai. Cek trigger menerima event:"
gcloud eventarc triggers describe "$TRIGGER" --location="$TRIGGER_LOCATION" --project="$PROJECT_ID" --format='value(transport.pubsub.topic)' || true
# Log Cloud Run untuk debug (tidak dinilai)
echo "Log Cloud Run terbaru (jika ada):"
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE" --project="$PROJECT_ID" --limit=5 --format='value(textPayload)' 2>/dev/null | head -20 || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Pub/Sub topic $TOPIC + sub $SUB
  Task 2 - Cloud Run sink $SERVICE ($RUN_REGION)
  Task 3 - Eventarc trigger $TRIGGER + publish test

Region: $REGION (trigger: $TRIGGER_LOCATION, run: $RUN_REGION)
Cek manual:
  gcloud pubsub topics list --project=$PROJECT_ID
  gcloud run services list --project=$PROJECT_ID
  gcloud eventarc triggers list --location=$REGION --project=$PROJECT_ID
  gcloud pubsub topics publish $TOPIC --message="test lagi"
==============================================================
EOF
