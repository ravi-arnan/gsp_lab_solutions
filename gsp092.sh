#!/usr/bin/env bash
# GSP092 - Monitoring and Logging for Cloud Run Functions
#
#   REGION=us-east4 bash gsp092.sh
#
# Checkpoint:
#   Task 1 - Creating a Cloud Run function (helloworld)
#   Task 2 - Create logs-based metric (CloudRunFunctionLatency-Logs)
#   Task 3-5 - Metrics Explorer, dashboard, kuis: tanpa checkpoint, manual
#
# Deploy Task 1 butuh DUA langkah, dan urutannya penting (diuji 2026-08-04):
#   1. 'gcloud functions deploy --gen2' — grader GSP092 mencari resource
#      Cloud Functions v2. Ini KEBALIKAN gsp081/arc109 yang justru menolak
#      resource itu dan menuntut 'gcloud run deploy --function'. Jangan
#      menyamaratakan lab keluarga Cloud Run functions.
#   2. 'gcloud run services update --execution-environment=gen2 --cpu=1' —
#      lab minta "Execution environment: second generation", dan Cloud
#      Functions tidak menyetelnya. gen2 menolak CPU < 1 (default function
#      0.1666), jadi CPU dan memory ikut dinaikkan ke nilai default console.
#
# LAMA: ~4 menit (deploy ~2 menit + generate traffic ~1 menit).

set -euo pipefail

REGION="${REGION:-us-east4}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

SERVICE="helloworld"
METRIC="CloudRunFunctionLatency-Logs"
WORKDIR="$HOME/gsp092/src"

echo "Project : $PROJECT"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal/kena rate limit, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Deploy Cloud Run function '$SERVICE'"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloWorld', (req, res) => {
  res.status(200).send('Hello World!');
});
EOF
cat > "$WORKDIR/package.json" << 'EOF'
{
  "name": "helloworld",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

gcloud functions deploy "$SERVICE" \
  --gen2 \
  --runtime=nodejs22 \
  --region="$REGION" \
  --source="$WORKDIR" \
  --entry-point=helloWorld \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances=5 \
  --project="$PROJECT"

# Cloud Functions tidak menyetel execution environment gen2; tambahkan lewat
# Cloud Run. CPU wajib >= 1 untuk gen2, function default 0.1666.
gcloud run services update "$SERVICE" \
  --region="$REGION" --project="$PROJECT" \
  --execution-environment=gen2 --cpu=1 --memory=512Mi

CLOUD_RUN_URL="$(gcloud functions describe "$SERVICE" --region="$REGION" \
  --project="$PROJECT" --format='value(serviceConfig.uri)')"
echo "URL: $CLOUD_RUN_URL"
curl -sS -m 60 -w "\n" "$CLOUD_RUN_URL"

# ----------------------------------------------------------------- Task 2
step "Task 2: Logs-based metric '$METRIC' (Distribution)"
if gcloud logging metrics describe "$METRIC" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Metric sudah ada, lewati."
else
  cat > /tmp/gsp092_metric.yaml << EOF
description: Latency dari httpRequest.latency pada log Cloud Run
filter: resource.type="cloud_run_revision" AND resource.labels.service_name="$SERVICE"
valueExtractor: EXTRACT(httpRequest.latency)
metricDescriptor:
  metricKind: DELTA
  valueType: DISTRIBUTION
  unit: s
bucketOptions:
  exponentialBuckets:
    numFiniteBuckets: 64
    growthFactor: 2
    scale: 0.01
EOF
  gcloud logging metrics create "$METRIC" \
    --config-from-file=/tmp/gsp092_metric.yaml --project="$PROJECT"
fi

gcloud logging metrics describe "$METRIC" --project="$PROJECT" \
  --format="yaml(name, valueExtractor, metricDescriptor.valueType)"

# ----------------------------------------------------------------- Traffic
step "Generate traffic supaya metric punya data"
# ponytail: vegeta cuma dipakai buat bikin trafik dan tidak ada checkpoint yang
# memeriksanya, jadi curl paralel saja — hemat unduhan 10MB dari GitHub.
for _ in $(seq 1 20); do
  for _ in $(seq 1 10); do curl -s -o /dev/null -m 20 "$CLOUD_RUN_URL" & done
  wait
done
echo "200 request terkirim."

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 1 dan Task 2.

  URL    : $CLOUD_RUN_URL
  Metric : logging.googleapis.com/user/$METRIC

Task 3-4 tanpa checkpoint (opsional, lewat console):
  Monitoring > Metrics explorer, uncheck "Active", cari
  Cloud Run Revision > Logs-based metric > $METRIC.
  Metric baru butuh beberapa menit sebelum muncul.

Task 5 (Kuis):
  - Dua tipe log-based metrics:
    System logs-based metrics DAN User-defined logs-based metrics
  - Vegeta is a versatile HTTP load testing tool...  -> True
  - Logs-based metrics are based on the content of log entries -> True
==============================================================
EOF
