#!/usr/bin/env bash
# GSP081 - Cloud Run Functions: Qwik Start - Console
#
#   REGION=asia-east1 bash gsp081.sh
#
# Checkpoint:
#   Task 2 (50 pts) - Deploy the function
#   Task 3 (50 pts) - Test the function (script memanggil function-nya)
#   Task 4 (0 pts)  - Baca log (dikerjakan script)
#   Task 5 (0 pts)  - Kuis, jawaban di penutup
#
# Region diacak per peserta. Cocokkan REGION dengan halaman lab-mu.
#
# Dua hal yang wajib, kalau tidak Task 2 tetap nol (terbukti 2026-08-04):
#   - Deploy lewat 'gcloud run deploy --function', BUKAN 'gcloud functions
#     deploy --gen2'. Grader mencari Cloud Run service bikinan "Write a
#     function"; service milik Cloud Functions bentuknya beda.
#   - --execution-environment=gen2. Lab minta "Execution environment: Second
#     generation", dan ini setting Cloud Run yang default-nya gen1.

set -euo pipefail

REGION="${REGION:-asia-east1}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

SERVICE="gcfunction"
WORKDIR="/tmp/gsp081-source"

echo "Project : $PROJECT"
echo "Region  : $REGION"
echo "Service : $SERVICE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- API
step "Enable API yang dibutuhkan"
gcloud services enable \
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
step "Task 2: Deploy '$SERVICE' (~2-3 menit)"
# -q supaya prompt pembuatan repo Artifact Registry 'cloud-run-source-deploy'
# di-iyakan otomatis.
gcloud run deploy "$SERVICE" \
  --source="$WORKDIR" \
  --function=helloHttp \
  --base-image=nodejs22 \
  --region="$REGION" \
  --allow-unauthenticated \
  --max-instances=5 \
  --execution-environment=gen2 \
  --project="$PROJECT" \
  -q

URL="$(gcloud run services describe "$SERVICE" \
  --region="$REGION" --project="$PROJECT" --format='value(status.url)')"
echo "URL: $URL"

# ----------------------------------------------------------------- Task 3
step "Task 3: Test the function"
curl -sS -m 60 -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World!"}'
echo

# ----------------------------------------------------------------- Task 4
step "Task 4: Baca log (bisa telat beberapa menit)"
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE" \
  --limit=20 --project="$PROJECT" --format="value(timestamp, textPayload)" || true

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
