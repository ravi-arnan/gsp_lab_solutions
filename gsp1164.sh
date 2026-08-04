#!/usr/bin/env bash
# GSP1164 - Analyze Findings with Security Command Center
#
# FULL AUTOMATION SCRIPT
# Region: us-east4 (bisa override: REGION=us-east4 bash gsp1164.sh)
#
# Task 1: Pub/Sub + VM + Continuous Export
# Task 2: BigQuery + SCC Export + Service Accounts
# Task 3: GCS bucket + export

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

ask REGION "us-west1" "Region (cocokkan dengan panel lab)"
ZONE="${REGION}-c"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set."; exit 1; }

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== Enable APIs
step "Enable APIs"
gcloud services enable securitycenter.googleapis.com --project="$PROJECT"
gcloud services enable pubsub.googleapis.com --project="$PROJECT"
gcloud services enable compute.googleapis.com --project="$PROJECT"
gcloud services enable bigquery.googleapis.com --project="$PROJECT"
echo "APIs enabled. Waiting..."
sleep 10

# ================================================================== Task 1a: Pub/Sub
step "Task 1a: Create Pub/Sub topic + subscription"

if gcloud pubsub topics describe export-findings-pubsub-topic --project="$PROJECT" >/dev/null 2>&1; then
  echo "Topic sudah ada."
else
  gcloud pubsub topics create export-findings-pubsub-topic --project="$PROJECT"
fi

if gcloud pubsub subscriptions describe export-findings-pubsub-topic-sub --project="$PROJECT" >/dev/null 2>&1; then
  echo "Subscription sudah ada."
else
  gcloud pubsub subscriptions create export-findings-pubsub-topic-sub \
    --topic=export-findings-pubsub-topic --project="$PROJECT"
fi

# ================================================================== Task 1b: VM
step "Task 1b: Create VM instance-1"

if gcloud compute instances describe instance-1 --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "VM instance-1 sudah ada."
else
  gcloud compute instances create instance-1 \
    --zone="$ZONE" \
    --machine-type=e2-micro \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --project="$PROJECT"
fi

# ================================================================== Task 2a: BigQuery dataset
step "Task 2a: Create BigQuery dataset"

if bq ls --project_id="$PROJECT" 2>/dev/null | grep -q continuous_export_dataset; then
  echo "Dataset sudah ada."
else
  bq --location="$REGION" --apilog=/dev/null mk --dataset "$PROJECT:continuous_export_dataset"
fi

# ================================================================== Task 2b: SCC BigQuery export
step "Task 2b: Create SCC BigQuery export"

if gcloud scc bqexports describe scc-bq-cont-export --project="$PROJECT" >/dev/null 2>&1; then
  echo "SCC export sudah ada."
else
  gcloud scc bqexports create scc-bq-cont-export \
    --dataset="projects/$PROJECT/datasets/continuous_export_dataset" \
    --project="$PROJECT"
fi

# ================================================================== Task 2c: Service accounts
step "Task 2c: Create service accounts + keys"

for i in {0..2}; do
  SA_NAME="sccp-test-sa-$i"
  SA_EMAIL="$SA_NAME@${PROJECT}.iam.gserviceaccount.com"
  
  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
    echo "SA $SA_NAME sudah ada."
  else
    gcloud iam service-accounts create "$SA_NAME" --project="$PROJECT"
    sleep 5
  fi
  
  if [[ ! -f "/tmp/sa-key-$i.json" ]]; then
    gcloud iam service-accounts keys create "/tmp/sa-key-$i.json" \
      --iam-account="$SA_EMAIL" || {
      echo "Retry key creation..."
      sleep 10
      gcloud iam service-accounts keys create "/tmp/sa-key-$i.json" \
        --iam-account="$SA_EMAIL"
    }
  fi
done

# ================================================================== Task 3a: GCS bucket
step "Task 3a: Create GCS bucket"

BUCKET="scc-export-bucket-$PROJECT"
if gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket sudah ada."
else
  gsutil mb -p "$PROJECT" -l "$REGION" -b on "gs://$BUCKET"
fi

# ================================================================== VERIFICATION
step "Verification"

echo ""
echo "Pub/Sub topics:"
gcloud pubsub topics list --project="$PROJECT" --format="table(name)"

echo ""
echo "Compute instances:"
gcloud compute instances list --project="$PROJECT" --format="table(name,zone,status)"

echo ""
echo "BigQuery datasets:"
bq ls --project_id="$PROJECT" 2>/dev/null || true

echo ""
echo "Service accounts:"
gcloud iam service-accounts list --project="$PROJECT" --format="table(email)"

echo ""
echo "GCS bucket contents:"
gsutil ls "gs://$BUCKET/" 2>/dev/null || echo "  (kosong)"

echo ""
echo "SCC BigQuery exports:"
gcloud scc bqexports list --project="$PROJECT" 2>/dev/null || true

cat <<'EOF'

==============================================================
SCRIPT SELESAI - LANGKAH MANUAL DI CONSOLE:

TASK 1 (20 poin):
  1. Buka Navigation menu > Security > Risk Overview > Vulnerabilities
  2. Klik Settings (kiri)
  3. Tab Continuous Exports > Create Pub/Sub Export
  4. Isi:
     - Name: export-findings-pubsub
     - Description: Continuous exports of Findings to Pub/Sub and BigQuery
     - Project: pilih project ID kamu
     - Topic: projects/{project_id}/topics/export-findings-pubsub-topic
     - Query: state="ACTIVE" AND NOT mute="MUTED"
  5. Klik Save
  6. Tunggu 5-10 menit
  7. Buka Pub/Sub > Subscriptions > export-findings-pubsub-topic-sub
  8. Tab Messages > centang Enable ack messages > Pull
  9. Jika tidak ada, buat VM lagi:
     gcloud compute instances create instance-2 --zone=ZONE --machine-type=e2-micro
  10. Tunggu 5-10 menit lalu Pull lagi
  11. Klik Check my progress

TASK 2 (sudah di-script, tapi cek di BigQuery):
  Tunggu 10+ menit lalu jalankan:
  bq query --apilog=/dev/null --use_legacy_sql=false \
    "SELECT finding_id,event_time,finding.category FROM continuous_export_dataset.findings"
  Klik Check my progress

TASK 3 (5 poin):
  1. Buka Security > Findings
  2. Klik Export > Cloud Storage
  3. Project: pilih project ID
  4. Export path: Browse > pilih bucket scc-export-bucket-{project}
  5. Filename: findings.jsonl, Format: JSONL, Time Range: All time
  6. Klik Export
  7. Tunggu export selesai
  8. Buka BigQuery > Explorer > klik + > pilih dataset continuous_export_dataset
  9. Klik old_findings (kalau belum ada, buat table baru dari findings.jsonl)
  10. Klik Check my progress
==============================================================
EOF
