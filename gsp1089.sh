#!/usr/bin/env bash
# GSP1089 - Cloud Run Functions: Qwik Start
#
#   bash gsp1089.sh
#
# Checkpoint:
#   Task 2 - Create an HTTP function        (nodejs-http-function)
#   Task 3 - Create a Cloud Storage function (nodejs-storage-function)
#   Task 4 - Create a Cloud Audit Logs function (gce-vm-labeler)
#   Task 4 - Create a VM instance           (instance-1 + label creator)
#   Task 5 - Deploy different revisions     (hello-world-colored, 2 revisi)
#   Task 6 - Set up minimum instances       (slow-function, min-instances 1)
#   Task 7 - Create a function with concurrency (slow-concurrent-function, 100)
#
# Urutan sengaja tidak sama dengan lab: fungsi Audit Log di-deploy lebih awal
# supaya trigger Eventarc punya waktu propagasi (~10 menit) sambil task lain
# jalan. VM baru dibuat di akhir, saat trigger sudah aktif.

set -euo pipefail

REGION="${REGION:-europe-west1}"
ZONE="${ZONE:-europe-west1-b}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')

SRC="/tmp/gsp1089"
BUCKET="gs://gcf-gen2-storage-$PROJECT"
mkdir -p "$SRC"

echo "Project: $PROJECT ($PROJECT_NUMBER)"
echo "Region : $REGION / zone $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Deploy sering gagal beberapa menit pertama karena API baru aktif.
retry() {
  local n=1
  until "$@"; do
    (( n++ >= 4 )) && { echo "Gagal setelah 3 percobaan: $*"; return 1; }
    echo "Gagal, ulangi dalam 30 detik (percobaan $n)..."
    sleep 30
  done
}

# ----------------------------------------------------------------- Task 1
step "Task 1: Enable API"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- IAM
step "IAM: service agent GCS, Eventarc receiver, Audit Logs Compute Engine"

GCS_SA=$(gcloud storage service-agent --project="$PROJECT" 2>/dev/null || gsutil kms serviceaccount -p "$PROJECT_NUMBER")
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:$GCS_SA" \
  --role roles/pubsub.publisher --condition=None >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role roles/eventarc.eventReceiver --condition=None >/dev/null

# Setara langkah manual IAM & Admin > Audit Logs > Compute Engine API
# (Admin Read + Data Read + Data Write). ADMIN_WRITE selalu aktif.
gcloud projects get-iam-policy "$PROJECT" --format=json > "$SRC-policy.json"
jq '.auditConfigs = ((.auditConfigs // [] | map(select(.service != "compute.googleapis.com"))) + [{
      "service": "compute.googleapis.com",
      "auditLogConfigs": [{"logType":"ADMIN_READ"},{"logType":"DATA_READ"},{"logType":"DATA_WRITE"}]
    }])' "$SRC-policy.json" > "$SRC-policy-new.json"
gcloud projects set-iam-policy "$PROJECT" "$SRC-policy-new.json" >/dev/null
echo "Audit Logs Compute Engine aktif."

# ----------------------------------------------------------------- Task 4 (deploy duluan)
step "Task 4: Deploy fungsi Audit Log 'gce-vm-labeler' (dideploy awal, trigger butuh ~10 menit)"
[[ -d "$SRC/eventarc-samples" ]] || git clone -q https://github.com/GoogleCloudPlatform/eventarc-samples.git "$SRC/eventarc-samples"
retry gcloud functions deploy gce-vm-labeler \
  --gen2 \
  --runtime nodejs22 \
  --entry-point labelVmCreation \
  --source "$SRC/eventarc-samples/gce-vm-labeler/gcf/nodejs" \
  --region "$REGION" \
  --trigger-event-filters="type=google.cloud.audit.log.v1.written,serviceName=compute.googleapis.com,methodName=beta.compute.instances.insert" \
  --trigger-location "$REGION" \
  --max-instances 1 \
  --project "$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: HTTP function 'nodejs-http-function'"
mkdir -p "$SRC/hello-http"
cat > "$SRC/hello-http/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloWorld', (req, res) => {
  res.status(200).send('HTTP with Node.js in GCF 2nd gen!');
});
EOF
cat > "$SRC/hello-http/package.json" << 'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF
retry gcloud functions deploy nodejs-http-function \
  --gen2 \
  --runtime nodejs22 \
  --entry-point helloWorld \
  --source "$SRC/hello-http" \
  --region "$REGION" \
  --trigger-http \
  --timeout 600s \
  --max-instances 1 \
  --allow-unauthenticated \
  --project "$PROJECT"

gcloud functions call nodejs-http-function --gen2 --region "$REGION" --project "$PROJECT"

# ----------------------------------------------------------------- Task 3
step "Task 3: Cloud Storage function 'nodejs-storage-function'"
mkdir -p "$SRC/hello-storage"
cat > "$SRC/hello-storage/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('helloStorage', (cloudevent) => {
  console.log('Cloud Storage event with Node.js in GCF 2nd gen!');
  console.log(cloudevent);
});
EOF
cp "$SRC/hello-http/package.json" "$SRC/hello-storage/package.json"

gcloud storage buckets describe "$BUCKET" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud storage buckets create "$BUCKET" --location="$REGION" --project="$PROJECT"

retry gcloud functions deploy nodejs-storage-function \
  --gen2 \
  --runtime nodejs22 \
  --entry-point helloStorage \
  --source "$SRC/hello-storage" \
  --region "$REGION" \
  --trigger-bucket "$BUCKET" \
  --trigger-location "$REGION" \
  --max-instances 1 \
  --project "$PROJECT"

echo "Hello World" > "$SRC/random.txt"
gcloud storage cp "$SRC/random.txt" "$BUCKET/random.txt"

# ----------------------------------------------------------------- Task 5
step "Task 5: Dua revisi 'hello-world-colored' (orange lalu yellow)"
mkdir -p "$SRC/hello-world-colored"
cat > "$SRC/hello-world-colored/main.py" << 'EOF'
import os

color = os.environ.get('COLOR')

def hello_world(request):
    return f'<body style="background-color:{color}"><h1>Hello World!</h1></body>'
EOF
: > "$SRC/hello-world-colored/requirements.txt"

for COLOR in orange yellow; do
  echo "--- revisi COLOR=$COLOR"
  retry gcloud functions deploy hello-world-colored \
    --gen2 \
    --runtime python311 \
    --entry-point hello_world \
    --source "$SRC/hello-world-colored" \
    --region "$REGION" \
    --trigger-http \
    --allow-unauthenticated \
    --update-env-vars "COLOR=$COLOR" \
    --max-instances 1 \
    --project "$PROJECT"
done

# ----------------------------------------------------------------- Task 6
step "Task 6: 'slow-function' dengan min-instances 1"
mkdir -p "$SRC/min-instances"
cat > "$SRC/min-instances/main.go" << 'EOF'
package p

import (
        "fmt"
        "net/http"
        "time"
)

func init() {
        time.Sleep(10 * time.Second)
}

func HelloWorld(w http.ResponseWriter, r *http.Request) {
        fmt.Fprint(w, "Slow HTTP Go in GCF 2nd gen!")
}
EOF
cat > "$SRC/min-instances/go.mod" << 'EOF'
module example.com/mod

go 1.23
EOF

# ponytail: langsung deploy dengan min-instances 1, dua langkah lab (deploy
# tanpa min lalu edit revisi di Console) cuma buat mendemokan cold start.
retry gcloud functions deploy slow-function \
  --gen2 \
  --runtime go123 \
  --entry-point HelloWorld \
  --source "$SRC/min-instances" \
  --region "$REGION" \
  --trigger-http \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 4 \
  --project "$PROJECT"

# ----------------------------------------------------------------- Task 7
step "Task 7: 'slow-concurrent-function' dengan concurrency 100"
retry gcloud functions deploy slow-concurrent-function \
  --gen2 \
  --runtime go123 \
  --entry-point HelloWorld \
  --source "$SRC/min-instances" \
  --region "$REGION" \
  --trigger-http \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 4 \
  --project "$PROJECT"

# Setara langkah Console: Edit & Deploy New Revision > CPU 1, concurrency 100.
gcloud run services update slow-concurrent-function \
  --region "$REGION" --project "$PROJECT" \
  --cpu 1 --concurrency 100 --max-instances 4

# ----------------------------------------------------------------- Task 4: VM
step "Task 4: Buat VM 'instance-1' supaya fungsi labeler jalan"
echo "Menunggu trigger Eventarc siap..."
gcloud eventarc triggers list --location "$REGION" --project "$PROJECT" \
  --format="table(name,eventFilters)" || true

# Trigger memfilter methodName=beta.compute.instances.insert, jadi VM harus
# dibuat lewat API beta (Console pakai beta). 'gcloud compute' biasa memakai
# v1 dan tidak akan memicu fungsi.
if ! gcloud compute instances describe instance-1 --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud beta compute instances create instance-1 --zone "$ZONE" --project "$PROJECT"
fi

echo "Menunggu label 'creator' muncul (maks 5 menit)..."
for i in $(seq 1 30); do
  LABEL=$(gcloud compute instances describe instance-1 --zone "$ZONE" --project "$PROJECT" \
            --format="value(labels.creator)" 2>/dev/null || true)
  [[ -n "$LABEL" ]] && { echo "Label creator = $LABEL"; break; }
  sleep 10
done

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk:
  - Create an HTTP function
  - Create a Cloud Storage function
  - Create a Cloud Audit Logs function
  - Create a VM instance
  - Deploy different revisions
  - Set up minimum instances
  - Create a function with concurrency

Kalau label 'creator' belum muncul di instance-1, trigger Eventarc belum
aktif waktu VM dibuat. Hapus lalu buat ulang VM-nya:
  gcloud compute instances delete instance-1 --zone $ZONE -q
  gcloud beta compute instances create instance-1 --zone $ZONE
Kalau tetap kosong, buat VM lewat Console (Compute Engine > Create Instance,
nama instance-1, zone $ZONE).

Cek log fungsi Storage:
  gcloud functions logs read nodejs-storage-function --region $REGION --gen2 --limit=100 --format "value(log)"
==============================================================
EOF
