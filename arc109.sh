#!/usr/bin/env bash
# ARC109 - Deploy and Secure Serverless APIs with API Gateway: Challenge Lab
#
#   REGION=us-east1 nohup bash arc109.sh > arc109.log 2>&1 &
#   tail -f ~/arc109.log
#
# Checkpoint:
#   Task 1 - Create a Cloud Run function (gcfunction, nodejs22, unauth)
#   Task 2 - Create an API Gateway (gcfunction-api)
#   Task 3 - Pub/Sub topic demo-topic + publish lewat API backend
#
# Pembuatan gateway ~10 menit, sesi Cloud Shell bisa putus. Jalankan di
# background. Script idempoten, aman diulang.
#
# Catatan deploy (pelajaran dari GSP081): grader lab keluarga ini mencari
# Cloud Run service hasil alur "Write a function", jadi pakai
# 'gcloud run deploy --function', BUKAN 'gcloud functions deploy --gen2',
# dan sertakan --execution-environment=gen2.

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

ask REGION "us-east1" "Region (cocokkan dengan panel lab)"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

SERVICE="gcfunction"
API_ID="gcfunction-api"
CONFIG_ID="gcfunction-api"
GATEWAY="gcfunction-api"
TOPIC="demo-topic"
SUBSCRIPTION="demo-topic-sub"
WORKDIR="$HOME/arc109/src"

echo "Project : $PROJECT"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# ----------------------------------------------------------------- API
step "Enable API yang dibutuhkan"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal/kena rate limit, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Deploy Cloud Run function '$SERVICE' (Hello World!)"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

exports.helloHttp = functions.http('helloHttp', (req, res) => {
  res.status(200).send('Hello World!');
});
EOF
cat > "$WORKDIR/package.json" << 'EOF'
{
  "name": "gcfunction",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

gcloud run deploy "$SERVICE" \
  --source="$WORKDIR" \
  --function=helloHttp \
  --base-image=nodejs22 \
  --region="$REGION" \
  --allow-unauthenticated \
  --execution-environment=gen2 \
  --project="$PROJECT" \
  -q

FUNC_URL="$(gcloud run services describe "$SERVICE" --region="$REGION" \
  --project="$PROJECT" --format='value(status.url)')"
echo "Function URL: $FUNC_URL"
curl -sS -m 60 -w "\n" "$FUNC_URL"

cat <<EOF

**************************************************************
Task 1 SELESAI - klik "Check my progress" untuk Task 1 SEKARANG,
selagi script bikin gateway (~10 menit). Nanti function ini
di-redeploy dengan kode Pub/Sub untuk Task 3.
**************************************************************
EOF

# ----------------------------------------------------------------- Task 3a
step "Task 3 (bagian 1): Pub/Sub topic '$TOPIC' + default subscription"
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud pubsub topics create "$TOPIC" --project="$PROJECT"
gcloud pubsub subscriptions describe "$SUBSCRIPTION" --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud pubsub subscriptions create "$SUBSCRIPTION" --topic="$TOPIC" --project="$PROJECT"

# Service account function harus boleh publish.
gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
  --member="serviceAccount:$SA" --role=roles/pubsub.publisher \
  --project="$PROJECT" >/dev/null

# ----------------------------------------------------------------- Task 2
step "Task 2: API '$API_ID' + config + gateway"
cat > "$HOME/arc109/openapispec.yaml" << EOF
swagger: '2.0'
info:
  title: gcfunction API
  description: Sample API on API Gateway with a Google Cloud Run functions backend
  version: 1.0.0
schemes:
- https
produces:
- application/json
x-google-backend:
  address: ${FUNC_URL}
paths:
  /gcfunction:
    get:
      summary: gcfunction
      operationId: gcfunction
      responses:
       '200':
          description: A successful response
          schema:
            type: string
EOF

gcloud api-gateway apis describe "$API_ID" --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud api-gateway apis create "$API_ID" \
       --display-name="gcfunction API" --project="$PROJECT"

gcloud api-gateway api-configs describe "$CONFIG_ID" --api="$API_ID" \
  --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud api-gateway api-configs create "$CONFIG_ID" \
       --api="$API_ID" \
       --openapi-spec="$HOME/arc109/openapispec.yaml" \
       --display-name="gcfunction API" \
       --backend-auth-service-account="$SA" \
       --project="$PROJECT"

step "Task 2: Create gateway (~10 menit, tidak ada output selama menunggu)"
gcloud api-gateway gateways describe "$GATEWAY" --location="$REGION" \
  --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud api-gateway gateways create "$GATEWAY" \
       --api="$API_ID" --api-config="$CONFIG_ID" \
       --location="$REGION" --display-name="gcfunction API" \
       --project="$PROJECT"

GATEWAY_URL="$(gcloud api-gateway gateways describe "$GATEWAY" --location="$REGION" \
  --project="$PROJECT" --format='value(defaultHostname)')"
echo "Gateway URL: https://$GATEWAY_URL/gcfunction"

# ----------------------------------------------------------------- Task 3b
step "Task 3 (bagian 2): Redeploy function dengan publisher Pub/Sub"
cat > "$WORKDIR/index.js" << 'EOF'
/**
 * Responds to any HTTP request.
 *
 * @param {!express:Request} req HTTP request context.
 * @param {!express:Response} res HTTP response context.
 */
const {PubSub} = require('@google-cloud/pubsub');
const pubsub = new PubSub();
const topic = pubsub.topic('demo-topic');
const functions = require('@google-cloud/functions-framework');

exports.helloHttp = functions.http('helloHttp', (req, res) => {

  // Send a message to the topic
  topic.publishMessage({data: Buffer.from('Hello from Cloud Run functions!')});
  res.status(200).send("Message sent to Topic demo-topic!");
});
EOF
cat > "$WORKDIR/package.json" << 'EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^3.4.1"
  }
}
EOF

gcloud run deploy "$SERVICE" \
  --source="$WORKDIR" \
  --function=helloHttp \
  --base-image=nodejs22 \
  --region="$REGION" \
  --allow-unauthenticated \
  --execution-environment=gen2 \
  --project="$PROJECT" \
  -q

# ----------------------------------------------------------------- Invoke
step "Task 3 (bagian 3): Panggil API Gateway supaya pesan terbit"
for i in $(seq 1 8); do
  RESP="$(curl -sSL -m 60 "https://$GATEWAY_URL/gcfunction" || true)"
  echo "  percobaan $i: $RESP"
  [[ "$RESP" == *"Message sent to Topic"* ]] && break
  sleep 15
done

# Panggil beberapa kali lagi supaya subscription pasti terisi.
for _ in 1 2 3; do curl -sS -m 60 -o /dev/null "https://$GATEWAY_URL/gcfunction" || true; done

echo
echo "Cek pesan yang masuk (boleh kosong, pesan bisa telat ~5 menit):"
gcloud pubsub subscriptions pull "$SUBSCRIPTION" --limit=5 --project="$PROJECT" \
  --format="value(message.data)" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 1, 2, dan 3.

Endpoint:
  Function : $FUNC_URL
  Gateway  : https://$GATEWAY_URL/gcfunction

Kalau Task 3 belum hijau, panggil lagi lalu tunggu beberapa menit:
  curl -sL "https://$GATEWAY_URL/gcfunction"
==============================================================
EOF
