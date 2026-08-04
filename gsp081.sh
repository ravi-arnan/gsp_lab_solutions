#!/usr/bin/env bash
# GSP081 - Cloud Run Functions: Qwik Start - Console
#
#   REGION=asia-east1 bash gsp081.sh
#
# Checkpoint:
#   Task 2 - Deploy the function
#   Task 3 - Test the function (script memanggil function-nya)
#   Task 4 (0 pts) - Baca log (dikerjakan script)
#   Task 5 (0 pts) - Kuis, jawaban di penutup
#
# Region diacak per peserta. Cocokkan REGION dengan halaman lab-mu.

set -euo pipefail

REGION="${REGION:-asia-east1}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

FUNC_NAME="gcfunction"
WORKDIR="/tmp/gsp081-source"

echo "Project : $PROJECT"
echo "Region  : $REGION"
echo "Function: $FUNC_NAME"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- API
step "Enable API yang dibutuhkan"
gcloud services enable \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal/kena rate limit, lanjut saja (biasanya sudah aktif)."

# ----------------------------------------------------------------- Task 1
step "Task 1: Siapkan source code (default helloHttp)"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.send(`Hello ${req.query.name || req.body.name || 'World'}!`);
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
echo "index.js + package.json siap di $WORKDIR"

# ----------------------------------------------------------------- Task 2
step "Task 2: Deploy '$FUNC_NAME' (~2-3 menit)"
gcloud functions deploy "$FUNC_NAME" \
  --gen2 \
  --runtime=nodejs22 \
  --region="$REGION" \
  --source="$WORKDIR" \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances=5 \
  --project="$PROJECT"

URL="$(gcloud functions describe "$FUNC_NAME" \
  --region="$REGION" --project="$PROJECT" --format='value(serviceConfig.uri)')"
echo "URL: $URL"

# ----------------------------------------------------------------- Task 3
step "Task 3: Test the function"
curl -sS -m 60 -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World!"}'
echo

# ----------------------------------------------------------------- Task 4
step "Task 4: Baca log (bisa telat beberapa menit)"
gcloud functions logs read "$FUNC_NAME" \
  --region="$REGION" --project="$PROJECT" --limit=20 || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress di:
  Task 2 - Deploy the function
  Task 3 - Test the function

Kalau checkpoint Task 3 belum hijau, panggil lagi function-nya:
  curl "$URL"

Task 5 (Kuis):
  - Cloud Run functions is a serverless execution environment for
    event driven services on Google Cloud.
    Jawaban: True
  - Which type of trigger is used while creating Cloud Run functions
    in the lab?
    Jawaban: HTTPS
==============================================================
EOF
