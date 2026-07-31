#!/usr/bin/env bash
# ARC104 - Build Serverless Applications with Cloud Run Functions: Challenge Lab
#
#   bash arc104.sh
#
# Checkpoint:
#   Task 1 - Create a Cloud Storage bucket (nama bucket = PROJECT_ID)
#   Task 2 - Create a Cloud Storage function 'cs-logger'
#   Task 3 - Create a HTTP function 'http-responder' (min 1, max 2 instance)

set -euo pipefail

REGION="${REGION:-us-east4}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

BUCKET="gs://$PROJECT"
SRC="/tmp/arc104"
mkdir -p "$SRC/cs-logger" "$SRC/http-responder"

echo "Project: $PROJECT"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

retry() {
  local n=1
  until "$@"; do
    (( n++ >= 4 )) && { echo "Gagal setelah 3 percobaan: $*"; return 1; }
    echo "Gagal, ulangi dalam 30 detik (percobaan $n)..."
    sleep 30
  done
}

# ----------------------------------------------------------------- API + IAM
step "Enable API"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT"

step "IAM: pubsub.publisher untuk service agent Cloud Storage"
# Service agent GCS dibuat lazy; endpoint ini yang mem-provision-nya.
GCS_SA=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://storage.googleapis.com/storage/v1/projects/$PROJECT/serviceAccount" | jq -r '.email_address')
[[ "$GCS_SA" == *@* ]] || { echo "Gagal mendapatkan service agent GCS: $GCS_SA"; exit 1; }
echo "Service agent GCS: $GCS_SA"
retry gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:$GCS_SA" \
  --role roles/pubsub.publisher --condition=None

# ----------------------------------------------------------------- Task 1
step "Task 1: Bucket $BUCKET"
gcloud storage buckets describe "$BUCKET" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud storage buckets create "$BUCKET" --location="$REGION" --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: Cloud Storage function 'cs-logger'"
cat > "$SRC/cs-logger/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('cs-logger', (cloudevent) => {
  console.log('A new event in your Cloud Storage bucket has been logged!');
  console.log(cloudevent);
});
EOF
cat > "$SRC/cs-logger/package.json" << 'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

retry gcloud functions deploy cs-logger \
  --gen2 \
  --runtime nodejs24 \
  --entry-point cs-logger \
  --source "$SRC/cs-logger" \
  --region "$REGION" \
  --trigger-bucket "$BUCKET" \
  --trigger-location "$REGION" \
  --max-instances 2 \
  --project "$PROJECT"

echo "Test: upload file ke bucket"
echo "Hello ARC104" > "$SRC/random.txt"
gcloud storage cp "$SRC/random.txt" "$BUCKET/random.txt"

# ----------------------------------------------------------------- Task 3
step "Task 3: HTTP function 'http-responder'"
cat > "$SRC/http-responder/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('http-responder', (req, res) => {
  res.status(200).send('HTTP function (2nd gen) has been called!');
});
EOF
cp "$SRC/cs-logger/package.json" "$SRC/http-responder/package.json"

retry gcloud functions deploy http-responder \
  --gen2 \
  --runtime nodejs24 \
  --entry-point http-responder \
  --source "$SRC/http-responder" \
  --region "$REGION" \
  --trigger-http \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 2 \
  --project "$PROJECT"

# Grader GSP1089 baru mau hijau setelah min-instances di-set lewat Run API,
# bukan cuma lewat flag deploy. Jadi tegaskan sekali lagi di sini.
gcloud run services update http-responder \
  --region "$REGION" --project "$PROJECT" \
  --min-instances 1 --max-instances 2

gcloud functions call http-responder --gen2 --region "$REGION" --project "$PROJECT" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk:
  - Create a Cloud Storage bucket $PROJECT
  - Create a Cloud Storage function cs-logger
  - Create a HTTP function http-responder
==============================================================
EOF
