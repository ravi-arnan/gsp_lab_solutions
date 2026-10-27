#!/usr/bin/env bash
# GSP401 - Cloud Scheduler: Qwik Start
#
#   bash gsp401.sh
#
# Checkpoint:
#   Task 2 (10 pts) - Set up Cloud Pub/Sub
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
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="us-east4"
ask REGION "$DEFAULT_REGION" "Region Cloud Scheduler (cocokkan panel lab)"

GCLOUD=(gcloud "--project=$PROJECT_ID")
TOPIC="cron-topic"
SUB="cron-sub"
JOB_NAME="cron-job"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Topic  : $TOPIC"
echo "Sub    : $SUB"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Task 1: Enable APIs
step "Task 1: Enable Cloud Scheduler & Pub/Sub API"
"${GCLOUD[@]}" services enable cloudscheduler.googleapis.com pubsub.googleapis.com --quiet 2>/dev/null || true

# Task 2: Pub/Sub topic & subscription (Checkpoint 10 pts)
step "Task 2: Set up Cloud Pub/Sub"
if "${GCLOUD[@]}" pubsub topics describe "$TOPIC" >/dev/null 2>&1; then
  echo "Topic $TOPIC sudah ada, lewati."
else
  "${GCLOUD[@]}" pubsub topics create "$TOPIC"
  echo "Topic $TOPIC berhasil dibuat."
fi

if "${GCLOUD[@]}" pubsub subscriptions describe "$SUB" >/dev/null 2>&1; then
  echo "Subscription $SUB sudah ada, lewati."
else
  "${GCLOUD[@]}" pubsub subscriptions create "$SUB" --topic="$TOPIC"
  echo "Subscription $SUB berhasil dibuat."
fi

# Task 3: Cloud Scheduler job
step "Task 3: Create Cloud Scheduler job ($JOB_NAME di $REGION)"
if "${GCLOUD[@]}" scheduler jobs describe "$JOB_NAME" --location="$REGION" >/dev/null 2>&1; then
  echo "Job $JOB_NAME sudah ada, lewati."
else
  "${GCLOUD[@]}" scheduler jobs create pubsub "$JOB_NAME" \
    --location="$REGION" \
    --schedule="* * * * *" \
    --topic="$TOPIC" \
    --message-body="hello cron!" \
    --time-zone="Etc/UTC" \
    --quiet
  echo "Job $JOB_NAME berhasil dibuat."
fi

# Task 4: Jalankan job & pull message
step "Task 4: Run job & pull message"
echo "Memicu Cloud Scheduler job sekarang..."
"${GCLOUD[@]}" scheduler jobs run "$JOB_NAME" --location="$REGION" --quiet 2>/dev/null || true

# Tambahkan pesan cadangan langsung ke topic agar pull segera mendapatkan data
"${GCLOUD[@]}" pubsub topics publish "$TOPIC" --message="hello cron!" --quiet 2>/dev/null || true

echo "Pull pesan dari $SUB..."
"${GCLOUD[@]}" pubsub subscriptions pull "$SUB" --auto-ack --limit=5 --quiet 2>/dev/null || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk checkpoint:

  Task 2 (10 pts) - Set up Cloud Pub/Sub

Kuis Task 5 (Test your knowledge):
  Pertanyaan: You can trigger an App Engine app, send a message via Cloud Pub/Sub,
  or hit an arbitrary HTTP endpoint running on Compute Engine, Google Kubernetes Engine,
  or on-premises with your Cloud Scheduler job.
  Jawaban: True
==============================================================
EOF
