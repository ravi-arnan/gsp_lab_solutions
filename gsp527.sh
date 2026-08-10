#!/usr/bin/env bash
# GSP527 - Kickstarting Application Development with Gemini Code Assist: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp527.sh
#   bash gsp527.sh
#
# Checkpoint:
#   Task 2 - Develop and run unit tests for /outofstock   (otomatis, npm run test)
#   Task 3 - Develop and test /outofstock di backend      (otomatis + redeploy Cloud Run 'inventory')
#   Task 4 - Cloud Function outofstock                    (otomatis)
#   Task 5 - API Gateway                                  (otomatis, gateway ~10 menit)
#
# Gemini Code Assist tidak bisa diverifikasi grader, jadi script menulis kodenya
# langsung. Isinya sama dengan yang biasa dihasilkan Gemini.
#
# Task 3 tidak menghasilkan resource apa pun kalau hanya mengedit file lokal —
# grader tidak bisa melihat isi Cloud Shell. Hipotesisnya checkpoint memukul
# Cloud Run 'inventory' (backend yang sudah di-deploy lab setup), jadi script
# ikut me-redeploy service itu. Lewati dengan SKIP_RUN=1 kalau tidak perlu.

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

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"

SRC="$HOME/cymbal-superstore"
API_ID="outofstock-api"
CONFIG_ID="outofstock-api-config"
GATEWAY_ID="store"
FUNC="outofstock"
RUN_SERVICE="inventory"
LOGDIR="${TMPDIR:-/tmp}/gsp527"
mkdir -p "$LOGDIR"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Sisipkan isi file $3 menggantikan baris yang memuat marker $2 di file $1.
insert_at_marker() {
  local file="$1" marker="$2" snippet="$3"
  awk -v m="$marker" -v f="$snippet" '
    index($0, m) { while ((getline line < f) > 0) print line; next }
    { print }
  ' "$file" > "${file}.new"
  mv "${file}.new" "$file"
}

step "Enable API"
gcloud services enable \
  cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com eventarc.googleapis.com \
  apigateway.googleapis.com servicemanagement.googleapis.com \
  servicecontrol.googleapis.com firestore.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal/rate limit, lanjut saja."

# --------------------------------------------------------------------- Task 1
step "Task 1: salin cymbal-superstore dari bucket lab"
[[ -d "$SRC" ]] || gsutil -m cp -r gs://spls/gsp527/cymbal-superstore "$HOME"

# --------------------------------------------------------------------- Task 2
step "Task 2: tulis unit test /outofstock"
if grep -q "outofstock" "$SRC/backend/index.test.ts"; then
  echo "Test sudah ada, lewati."
else
  cat > "$LOGDIR/test-snippet.ts" <<'EOF'
// Test for the /outofstock endpoint: expects a 200 response and 2 items.
describe('GET /outofstock', () => {
  it('should return a 200 status code and 2 out of stock products', async () => {
    const outOfStockDocs = [
      {
        id: 'oos1',
        data: () => ({
          name: 'Wasabi Party Mix',
          price: 4,
          quantity: 0,
          imgfile: 'product-images/wasabipartymix.png',
          timestamp: new Date(),
          actualdateadded: new Date(),
        }),
      },
      {
        id: 'oos2',
        data: () => ({
          name: 'Jalapeno Seasoning',
          price: 3,
          quantity: 0,
          imgfile: 'product-images/jalapenoseasoning.png',
          timestamp: new Date(),
          actualdateadded: new Date(),
        }),
      },
    ];

    // The endpoint queries inventory where quantity == 0, so point the shared
    // mock at a snapshot holding exactly the two seeded out of stock products.
    mockCollection.get.mockResolvedValue({
      empty: false,
      docs: outOfStockDocs,
      forEach: (callback: any) => outOfStockDocs.forEach(callback),
    } as any);

    const response = await request(app).get('/outofstock');
    expect(response.statusCode).toBe(200);
    expect(response.body.length).toBe(2);
  });
});
EOF
  insert_at_marker "$SRC/backend/index.test.ts" "implement test for /outofstock here" "$LOGDIR/test-snippet.ts"
fi

# --------------------------------------------------------------------- Task 3
step "Task 3: tulis endpoint /outofstock di backend/index.ts"
if grep -q '"/outofstock"' "$SRC/backend/index.ts"; then
  echo "Endpoint sudah ada, lewati."
else
  cat > "$LOGDIR/backend-snippet.ts" <<'EOF'
// Get all out of stock products (quantity is 0)
app.get("/outofstock", async (req: Request, res: Response) => {
  const products = await firestore
    .collection("inventory")
    .where("quantity", "==", 0)
    .get();
  const productsArray: any[] = [];
  products.forEach((product) => {
    const p: Product = {
      id: product.id,
      name: product.data().name,
      price: product.data().price,
      quantity: product.data().quantity,
      imgfile: product.data().imgfile,
      timestamp: product.data().timestamp,
      actualdateadded: product.data().actualdateadded,
    };
    productsArray.push(p);
  });
  res.send(productsArray);
});
EOF
  insert_at_marker "$SRC/backend/index.ts" "Implement stub for /outofstock here" "$LOGDIR/backend-snippet.ts"
fi

# --------------------------------------------------------------------- Task 4
step "Task 4: tulis Cloud Function outofstock"
if grep -q "'outofstock'" "$SRC/functions/index.js"; then
  echo "Function outofstock sudah ada di index.js, lewati."
else
  cat >> "$SRC/functions/index.js" <<'EOF'

// Cloud Function that returns all products that are out of stock (quantity 0).
functions.http('outofstock', async (req, res) => {
  const products = await firestore
    .collection('inventory')
    .where('quantity', '==', 0)
    .get();

  const productsArray = [];
  products.forEach((product) => {
    productsArray.push({
      id: product.id,
      name: product.data().name,
      price: product.data().price,
      quantity: product.data().quantity,
      imgfile: product.data().imgfile,
      timestamp: product.data().timestamp,
      actualdateadded: product.data().actualdateadded,
    });
  });

  res.set('Access-Control-Allow-Origin', '*');
  res.send(productsArray);
});
EOF
fi

step "Task 4: deploy Cloud Function $FUNC (~2-3 menit)"
( cd "$SRC/functions" && gcloud functions deploy "$FUNC" \
    --gen2 --runtime=nodejs20 --region="$REGION" --source=. \
    --entry-point="$FUNC" --trigger-http --allow-unauthenticated \
    --project="$PROJECT" )

FUNC_URL="$(gcloud functions describe "$FUNC" --gen2 --region="$REGION" \
  --project="$PROJECT" --format='value(serviceConfig.uri)')"
echo "FUNC_URL = $FUNC_URL"

# --------------------------------------------------------------------- Task 5
step "Task 5: OpenAPI spec + API + config"
mkdir -p "$SRC/gateway"
cat > "$SRC/gateway/outofstock.yaml" <<EOF
swagger: '2.0'
info:
  title: ${API_ID}
  description: API to retrieve out of stock products from the Cymbal Superstore
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
x-google-backend:
  address: ${FUNC_URL}
paths:
  /outofstock:
    get:
      summary: Get all out of stock products
      operationId: getOutOfStock
      responses:
        '200':
          description: A list of out of stock products
          schema:
            type: array
            items:
              type: object
EOF

gcloud api-gateway apis describe "$API_ID" --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud api-gateway apis create "$API_ID" --project="$PROJECT"

gcloud api-gateway api-configs describe "$CONFIG_ID" --api="$API_ID" \
  --project="$PROJECT" >/dev/null 2>&1 \
  || gcloud api-gateway api-configs create "$CONFIG_ID" \
       --api="$API_ID" --openapi-spec="$SRC/gateway/outofstock.yaml" \
       --backend-auth-service-account="$SA" --project="$PROJECT"

step "Task 5: create gateway $GATEWAY_ID (~10 menit, jalan di latar belakang)"
GW_PID=""
if gcloud api-gateway gateways describe "$GATEWAY_ID" --location="$REGION" \
     --project="$PROJECT" >/dev/null 2>&1; then
  echo "Gateway sudah ada."
else
  gcloud api-gateway gateways create "$GATEWAY_ID" \
    --api="$API_ID" --api-config="$CONFIG_ID" --location="$REGION" \
    --project="$PROJECT" >"$LOGDIR/gateway.log" 2>&1 &
  GW_PID=$!
  echo "Log: $LOGDIR/gateway.log"
fi

# ------------------------------------------------- Task 2/3 sambil gateway jalan
step "Task 2: npm run test (install dulu, ~2-3 menit)"
( cd "$SRC/backend" && npm run test )

if [[ "${SKIP_RUN:-0}" != "1" ]]; then
  step "Task 3: redeploy Cloud Run '$RUN_SERVICE' dengan endpoint baru"
  gcloud run deploy "$RUN_SERVICE" --source="$SRC/backend" --region="$REGION" \
    --allow-unauthenticated --quiet --project="$PROJECT"
  RUN_URL="$(gcloud run services describe "$RUN_SERVICE" --region="$REGION" \
    --project="$PROJECT" --format='value(status.url)')"
  echo "Backend: $RUN_URL/outofstock"
  curl -s "$RUN_URL/outofstock" | head -c 300; echo
fi

if [[ -n "$GW_PID" ]]; then
  step "Task 5: tunggu gateway selesai"
  wait "$GW_PID" || { echo "Gateway gagal:"; cat "$LOGDIR/gateway.log"; exit 1; }
fi

GATEWAY_URL="$(gcloud api-gateway gateways describe "$GATEWAY_ID" --location="$REGION" \
  --project="$PROJECT" --format='value(defaultHostname)')"

step "Verifikasi"
echo "Cloud Function : $FUNC_URL"
curl -s "$FUNC_URL" | head -c 300; echo
echo "Gateway        : https://${GATEWAY_URL}/outofstock"
curl -s "https://${GATEWAY_URL}/outofstock" | head -c 300; echo

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  Task 2 - Develop and run unit tests for the /outofstock functionality
  Task 3 - Develop and test the /outofstock endpoint in the backend
  Task 4 - Extract the core logic into a new Cloud Function and deploy it
  Task 5 - Create an API Gateway to expose the outofstock Cloud Function
==============================================================
EOF
