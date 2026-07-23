#!/usr/bin/env bash
# GSP081 - Cloud Run Functions: Qwik Start - Console
#
# Task 1-2: Deploy Cloud Run function via CLI (bypass Console)
# Task 3-5: Manual (testing, logs, quiz)
#
# Cara pakai:
#   REGION=us-west4 bash gsp081.sh
#
# Cukup satu kali jalan, lalu klik Check my progress di Task 2.

set -euo pipefail

REGION="${REGION:-us-west4}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

FUNC_NAME="gcfunction"
WORKDIR="/tmp/gsp081-source"

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Function: $FUNC_NAME"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Source code
step "Prepare source code (default helloHttp)"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/index.js" << 'EOF'
exports.helloHttp = (req, res) => {
  res.send(`Hello ${req.body.message || req.query.name || 'World'}!`);
};
EOF
cat > "$WORKDIR/package.json" << 'EOF'
{
  "name": "gcfunction",
  "version": "1.0.0",
  "dependencies": {}
}
EOF
echo "index.js + package.json siap di $WORKDIR"

# ----------------------------------------------------------------- Deploy
step "Deploy Cloud Run function '$FUNC_NAME' (gen2, ~2 menit)"
gcloud run functions deploy "$FUNC_NAME" \
  --region="$REGION" \
  --gen2 \
  --source="$WORKDIR" \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --project="$PROJECT"

# ----------------------------------------------------------------- Verify
step "Verifikasi"
gcloud run functions describe "$FUNC_NAME" \
  --region="$REGION" --project="$PROJECT" \
  --format="table(metadata.name, status.url, spec.template.spec.serviceAccount)"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress di Task 2: Deploy the function.

Untuk Task 3 (Test):
  Buka Console > Cloud Run > klik gcfunction > tab TEST
  Masukkan: {"message":"Hello World!"}

Untuk Task 4 (Logs):
  Klik Observability > Logs di halaman service

Task 5 (Quiz):
  - Cloud Run functions is a serverless execution environment...
    Jawaban: True
  - Which type of trigger is used while creating Cloud Run functions?
    Jawaban: HTTPS
==============================================================
EOF
