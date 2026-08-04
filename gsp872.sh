#!/usr/bin/env bash
# GSP872 - API Gateway: Qwik Start
#
#   REGION=us-central1 bash gsp872.sh
#
# Checkpoint:
#   Task 1 - Deploying an API Backend (cloud function helloGET)
#   Task 2 - Test the API Backend (curl ke function)
#   Task 3 - Creating a Gateway (api + config + gateway 'hello-gateway')
#   Task 4 - Securing Access by Using an API Key
#   Task 5 - Create and deploy a new API config to your existing gateway
#   Task 6 - Testing Calls Using Your API Key
#
# Semua task dikerjakan dari CLI, Console tidak perlu dibuka.
# Pembuatan gateway makan ~5-10 menit, jadi total ~15 menit. Sabar.

set -euo pipefail

REGION="${REGION:-us-central1}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

FUNC="helloGET"
GATEWAY="hello-gateway"
WORKDIR="$HOME/gsp872"

echo "Project : $PROJECT"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- API
step "Enable API yang dibutuhkan"
gcloud services enable \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal/kena rate limit, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Deploy cloud function '$FUNC'"
mkdir -p "$WORKDIR/src"
# ponytail: source ditulis langsung, tidak perlu clone nodejs-docs-samples (~200MB)
cat > "$WORKDIR/src/index.js" << 'EOF'
exports.helloGET = (req, res) => {
    res.send('Hello World!');
};
EOF
cat > "$WORKDIR/src/package.json" << 'EOF'
{
  "name": "helloworld-get",
  "version": "1.0.0",
  "main": "index.js"
}
EOF

gcloud functions deploy "$FUNC" \
  --runtime=nodejs20 \
  --trigger-http \
  --allow-unauthenticated \
  --region="$REGION" \
  --source="$WORKDIR/src" \
  --entry-point=helloGET \
  --project="$PROJECT"

# Gen1 pakai httpsTrigger.url, gen2 pakai url/serviceConfig.uri. Ambil yang ada.
FUNC_URL="$(gcloud functions describe "$FUNC" --region="$REGION" --project="$PROJECT" \
  --format='value(httpsTrigger.url)')"
[[ -n "$FUNC_URL" ]] || FUNC_URL="$(gcloud functions describe "$FUNC" --region="$REGION" \
  --project="$PROJECT" --format='value(url)')"
[[ -n "$FUNC_URL" ]] || FUNC_URL="$(gcloud functions describe "$FUNC" --region="$REGION" \
  --project="$PROJECT" --format='value(serviceConfig.uri)')"
[[ -n "$FUNC_URL" ]] || { echo "URL function tidak ketemu."; exit 1; }
echo "Function URL: $FUNC_URL"

# ----------------------------------------------------------------- Task 2
step "Task 2: Test the API backend"
curl -sS -m 60 -w "\n" "$FUNC_URL"

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat API, config, dan gateway"

# Pakai ulang API lama kalau script diulang, supaya tidak menumpuk hello-world-*.
API_ID="$(gcloud api-gateway apis list --project="$PROJECT" \
  --filter='name~hello-world' --format='value(name)' --limit=1 | awk -F/ '{print $NF}')"
if [[ -z "$API_ID" ]]; then
  API_ID="hello-world-$(tr -dc 'a-z' < /dev/urandom | head -c 8)"
  gcloud api-gateway apis create "$API_ID" \
    --display-name="Hello World API" --project="$PROJECT"
fi
echo "API_ID: $API_ID"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Spec pertama: tanpa security
cat > "$WORKDIR/openapi2-functions.yaml" << EOF
swagger: '2.0'
info:
  title: ${API_ID} description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello
      x-google-backend:
        address: ${FUNC_URL}
      responses:
       '200':
          description: A successful response
          schema:
            type: string
EOF

CONFIG1="hello-world-config"
if ! gcloud api-gateway api-configs describe "$CONFIG1" --api="$API_ID" \
     --project="$PROJECT" >/dev/null 2>&1; then
  gcloud api-gateway api-configs create "$CONFIG1" \
    --api="$API_ID" \
    --openapi-spec="$WORKDIR/openapi2-functions.yaml" \
    --display-name="Hello World Config" \
    --backend-auth-service-account="$SA" \
    --project="$PROJECT"
fi

step "Task 3: Create gateway '$GATEWAY' (~5-10 menit)"
if gcloud api-gateway gateways describe "$GATEWAY" --location="$REGION" \
   --project="$PROJECT" >/dev/null 2>&1; then
  echo "Gateway sudah ada, lewati."
else
  gcloud api-gateway gateways create "$GATEWAY" \
    --api="$API_ID" --api-config="$CONFIG1" \
    --location="$REGION" --display-name="Hello Gateway" \
    --project="$PROJECT"
fi

GATEWAY_URL="$(gcloud api-gateway gateways describe "$GATEWAY" --location="$REGION" \
  --project="$PROJECT" --format='value(defaultHostname)')"
echo "Gateway URL: https://$GATEWAY_URL/hello"

echo "Tes gateway (config tanpa API key):"
curl -sS -m 60 -w "\n" "https://$GATEWAY_URL/hello" || true

# ----------------------------------------------------------------- Task 4
step "Task 4: Enable managed service + buat API key"
MANAGED_SERVICE="$(gcloud api-gateway apis describe "$API_ID" --project="$PROJECT" \
  --format='value(managedService)')"
echo "Managed service: $MANAGED_SERVICE"
gcloud services enable "$MANAGED_SERVICE" --project="$PROJECT"

KEY_DISPLAY="hello-world-key"
KEY_NAME="$(gcloud services api-keys list --project="$PROJECT" \
  --filter="displayName=$KEY_DISPLAY" --format='value(name)' --limit=1)"
if [[ -z "$KEY_NAME" ]]; then
  gcloud services api-keys create \
    --display-name="$KEY_DISPLAY" \
    --api-target="service=$MANAGED_SERVICE" \
    --project="$PROJECT"
  KEY_NAME="$(gcloud services api-keys list --project="$PROJECT" \
    --filter="displayName=$KEY_DISPLAY" --format='value(name)' --limit=1)"
fi
API_KEY="$(gcloud services api-keys get-key-string "$KEY_NAME" --format='value(keyString)')"
echo "API key dibuat (${API_KEY:0:8}...)"

# ----------------------------------------------------------------- Task 5
step "Task 5: Config baru dengan API key security + update gateway"
cat > "$WORKDIR/openapi2-functions2.yaml" << EOF
swagger: '2.0'
info:
  title: ${API_ID} description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello
      x-google-backend:
        address: ${FUNC_URL}
      security:
        - api_key: []
      responses:
       '200':
          description: A successful response
          schema:
            type: string
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
EOF

CONFIG2="hello-config"
if ! gcloud api-gateway api-configs describe "$CONFIG2" --api="$API_ID" \
     --project="$PROJECT" >/dev/null 2>&1; then
  gcloud api-gateway api-configs create "$CONFIG2" \
    --api="$API_ID" \
    --openapi-spec="$WORKDIR/openapi2-functions2.yaml" \
    --display-name="Hello Config" \
    --backend-auth-service-account="$SA" \
    --project="$PROJECT"
fi

gcloud api-gateway gateways update "$GATEWAY" \
  --api="$API_ID" --api-config="$CONFIG2" \
  --location="$REGION" --project="$PROJECT"

# ----------------------------------------------------------------- Task 6
step "Task 6: Tes tanpa key (harus ditolak) lalu dengan key"
echo "-- tanpa key:"
curl -sSL -m 60 -w "\n" "https://$GATEWAY_URL/hello" || true

echo
echo "-- dengan key (propagasi bisa ~2 menit, dicoba sampai 10x):"
for i in $(seq 1 10); do
  RESP="$(curl -sSL -m 60 "https://$GATEWAY_URL/hello?key=$API_KEY" || true)"
  echo "  percobaan $i: $RESP"
  [[ "$RESP" == *"Hello World!"* ]] && break
  sleep 20
done

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress di semua task (1-6).

Data penting kalau perlu tes manual:
  GATEWAY_URL : https://$GATEWAY_URL/hello
  API_KEY     : $API_KEY
  API_ID      : $API_ID

  curl -sL "https://$GATEWAY_URL/hello?key=$API_KEY"
==============================================================
EOF
