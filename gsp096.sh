#!/usr/bin/env bash
# GSP096 - Pub/Sub: Qwik Start - Console
#
#   bash gsp096.sh
#
# Checkpoint:
#   Task 1 - Create a Pub/Sub topic
#   Task 2 - Add a subscription
#
# LAMA: < 1 menit.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

GCLOUD=(gcloud "--project=$PROJECT_ID")
TOPIC="MyTopic"
SUB="MySub"

echo "Project: $PROJECT_ID"
echo "Topic  : $TOPIC"
echo "Sub    : $SUB"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Enable Pub/Sub API jika belum aktif (abaikan bila rate-limited / sudah aktif)
"${GCLOUD[@]}" services enable pubsub.googleapis.com --quiet 2>/dev/null || true

# Task 1: Create Pub/Sub topic
step "Task 1: Create a Pub/Sub topic ($TOPIC)"
if "${GCLOUD[@]}" pubsub topics describe "$TOPIC" >/dev/null 2>&1; then
  echo "Topic $TOPIC sudah ada, lewati."
else
  "${GCLOUD[@]}" pubsub topics create "$TOPIC"
  echo "Topic $TOPIC berhasil dibuat."
fi

# Task 2: Create subscription
step "Task 2: Add a subscription ($SUB)"
if "${GCLOUD[@]}" pubsub subscriptions describe "$SUB" >/dev/null 2>&1; then
  echo "Subscription $SUB sudah ada, lewati."
else
  "${GCLOUD[@]}" pubsub subscriptions create "$SUB" --topic="$TOPIC"
  echo "Subscription $SUB berhasil dibuat."
fi

# Task 4 & 5: Publish & pull message (kelengkapan lab)
step "Task 4 & 5: Publish & pull message"
echo "Publish pesan 'Hello World' ke $TOPIC..."
"${GCLOUD[@]}" pubsub topics publish "$TOPIC" --message="Hello World"

echo "Pull pesan dari $SUB..."
"${GCLOUD[@]}" pubsub subscriptions pull --auto-ack "$SUB"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk kedua checkpoint:

  Task 1 - Create a Pub/Sub topic
  Task 2 - Add a subscription

Kuis Task 3 (Test your understanding):
  Q1: A publisher application creates and sends messages to a ____.
      Subscriber applications create a ____ to a topic to receive messages from it.
      Jawaban: topic, subscription

  Q2: Cloud Pub/Sub is an asynchronous messaging service designed to be highly reliable and scalable.
      Jawaban: True
==============================================================
EOF
