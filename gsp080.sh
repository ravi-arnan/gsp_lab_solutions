#!/usr/bin/env bash
# GSP080 - Cloud Run Functions: Qwik Start - Command Line
#
#   REGION=us-west4 bash gsp080.sh
#
# Checkpoint:
#   Task 2 (100 pts) - Create + deploy the Cloud Run function
#   Task 3-4 (0 pts) - Publish pesan ke Pub/Sub + baca log (dikerjakan script)
#   Task 5 (0 pts)   - Kuis, jawaban di penutup

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

ask REGION "us-west4" "Region (cocokkan dengan panel lab)"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

FUNC_NAME="nodejs-pubsub-function"
TOPIC="cf-demo"
WORKDIR="/tmp/gsp080-source"

echo "Project : $PROJECT"
echo "Region  : $REGION"
echo "Function: $FUNC_NAME (trigger topic: $TOPIC)"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Siapkan source code"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

// Register a CloudEvent callback with the Functions Framework that will
// be executed when the Pub/Sub trigger topic receives a message.
functions.cloudEvent('helloPubSub', cloudEvent => {
  // The Pub/Sub message is passed as the CloudEvent's data payload.
  const base64name = cloudEvent.data.message.data;

  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';

  console.log(`Hello, ${name}!`);
});
EOF
cat > "$WORKDIR/package.json" << 'EOF'
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF
echo "index.js + package.json siap di $WORKDIR"
# ponytail: npm install dilewati, dependency di-resolve Cloud Build saat deploy

# ----------------------------------------------------------------- Task 2
step "Task 2: Deploy '$FUNC_NAME' (~2-3 menit)"

# Bucket dan service account disiapkan lab; kalau tidak ada, pakai default.
DEPLOY_ARGS=()
if gcloud storage buckets describe "gs://${PROJECT}-bucket" >/dev/null 2>&1; then
  DEPLOY_ARGS+=(--stage-bucket "${PROJECT}-bucket")
else
  echo "Bucket ${PROJECT}-bucket tidak ada, pakai staging bucket default."
fi
SA="cloudfunctionsa@${PROJECT}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA" --project="$PROJECT" >/dev/null 2>&1; then
  DEPLOY_ARGS+=(--service-account "$SA")
else
  echo "Service account $SA tidak ada, pakai service account default."
fi

gcloud functions deploy "$FUNC_NAME" \
  --gen2 \
  --runtime=nodejs22 \
  --region="$REGION" \
  --source="$WORKDIR" \
  --entry-point=helloPubSub \
  --trigger-topic "$TOPIC" \
  --allow-unauthenticated \
  --project="$PROJECT" \
  "${DEPLOY_ARGS[@]}"

gcloud functions describe "$FUNC_NAME" \
  --region="$REGION" --project="$PROJECT" \
  --format="value(state)"

# ----------------------------------------------------------------- Task 3
step "Task 3: Publish pesan ke topic $TOPIC"
gcloud pubsub topics publish "$TOPIC" \
  --message="Cloud Function Gen2" --project="$PROJECT"

# ----------------------------------------------------------------- Task 4
step "Task 4: Baca log (bisa telat sampai ~10 menit)"
gcloud functions logs read "$FUNC_NAME" \
  --region="$REGION" --project="$PROJECT" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress di Task 2: Deploy the function. (100 pts)

Kalau log masih kosong, tunggu beberapa menit lalu ulangi:
  gcloud functions logs read $FUNC_NAME --region=$REGION

Task 5 (Kuis):
  - Serverless lets you write and deploy code without the hassle of
    managing the underlying infrastructure.
    Jawaban: True
==============================================================
EOF
