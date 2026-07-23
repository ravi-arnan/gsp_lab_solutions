#!/usr/bin/env bash
# GSP1164 - Analyze Findings with Security Command Center
#
# Task 1: Create continuous export pipeline to Pub/Sub
#   - Pub/Sub topic + subscription (script)
#   - Continuous export to Pub/Sub (Console UI)
#   - Create VM to generate findings (script)
#
# Task 2: Export and analyze SCC findings with BigQuery
#   - BigQuery dataset + SCC export (script)
#   - Service accounts to generate findings (script)
#
# Task 3: Export findings to GCS + BigQuery table
#   - GCS bucket (script)
#   - Export + Create table (Console UI)
#
# Cara pakai:
#   REGION=europe-west4 bash gsp1164.sh

set -euo pipefail

REGION="${REGION:-europe-west4}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set."; exit 1; }

echo "Project: $PROJECT"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== Task 1a: Pub/Sub topic + subscription
step "Task 1a: Create Pub/Sub topic and subscription"

if gcloud pubsub topics describe export-findings-pubsub-topic --project="$PROJECT" >/dev/null 2>&1; then
  echo "Topic sudah ada, dilewat."
else
  gcloud pubsub topics create export-findings-pubsub-topic --project="$PROJECT"
fi

if gcloud pubsub subscriptions describe export-findings-pubsub-topic-sub --project="$PROJECT" >/dev/null 2>&1; then
  echo "Subscription sudah ada, dilewat."
else
  gcloud pubsub subscriptions create export-findings-pubsub-topic-sub \
    --topic=export-findings-pubsub-topic --project="$PROJECT"
fi

cat <<EOF

Pub/Sub topic dan subscription sudah dibuat.
SEKARANG BUAT CONTINUOUS EXPORT MANUAL DI CONSOLE:

1. Buka Navigation menu > Security > Risk Overview > Vulnerabilities
2. Klik Settings di kiri
3. Klik tab Continuous Exports
4. Klik Create Pub/Sub Export
5. Isi:
   - Name: export-findings-pubsub
   - Description: Continuous exports of Findings to Pub/Sub and BigQuery
   - Project: $PROJECT
   - Topic: projects/$PROJECT/topics/export-findings-pubsub-topic
   - Query: state="ACTIVE" AND NOT mute="MUTED"
6. Klik Save
EOF

# ================================================================== Task 1b: Create VM
step "Task 1b: Create VM instance-1"

if gcloud compute instances describe instance-1 --zone="${REGION}-a" --project="$PROJECT" >/dev/null 2>&1; then
  echo "VM instance-1 sudah ada, dilewat."
else
  gcloud compute instances create instance-1 \
    --zone="${REGION}-a" \
    --machine-type=e2-micro \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --project="$PROJECT"
fi

cat <<EOF

VM instance-1 dibuat. Ini akan generate 3 findings:
- Public IP address
- Default service account used
- Compute secure boot disabled

SEKARANG CEK PUB/SUB MANUAL DI CONSOLE:

1. Buka Navigation menu > Pub/Sub > Subscriptions
2. Klik export-findings-pubsub-topic-sub
3. Klik tab Messages
4. Centang Enable ack messages
5. Klik Pull
6. Harusnya ada 3 messages (findings)

Setelah itu, klik Check my progress untuk Task 1.
EOF

# ================================================================== Task 2: BigQuery + SCC export
step "Task 2: Create BigQuery dataset and SCC export"

# Enable SCC API
gcloud services enable securitycenter.googleapis.com --project="$PROJECT"

# Create BigQuery dataset
echo "Creating BigQuery dataset..."
if bq ls --project_id="$PROJECT" | grep -q continuous_export_dataset; then
  echo "Dataset sudah ada, dilewat."
else
  bq --location="$REGION" --apilog=/dev/null mk --dataset \
    "$PROJECT:continuous_export_dataset"
fi

# Create SCC BigQuery export
echo "Creating SCC BigQuery export..."
if gcloud scc bqexports describe scc-bq-cont-export --project="$PROJECT" >/dev/null 2>&1; then
  echo "Export sudah ada, dilewat."
else
  gcloud scc bqexports create scc-bq-cont-export \
    --dataset="projects/$PROJECT/datasets/continuous_export_dataset" \
    --project="$PROJECT"
fi

# Create service accounts to generate findings
step "Task 2b: Create service accounts to generate findings"
for i in {0..2}; do
  SA_NAME="sccp-test-sa-$i"
  SA_EMAIL="$SA_NAME@$PROJECT.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
    echo "SA $SA_NAME sudah ada, dilewat."
  else
    gcloud iam service-accounts create "$SA_NAME" --project="$PROJECT"
    sleep 5
  fi
  # Create key
  if [[ ! -f "/tmp/sa-key-$i.json" ]]; then
    gcloud iam service-accounts keys create "/tmp/sa-key-$i.json" \
      --iam-account="$SA_EMAIL" || {
      echo "Retry in 10s..."
      sleep 10
      gcloud iam service-accounts keys create "/tmp/sa-key-$i.json" \
        --iam-account="$SA_EMAIL"
    }
  fi
done

cat <<EOF

BigQuery dataset, SCC export, dan service accounts sudah dibuat.
Findings akan di-export ke BigQuery (bisa butuh 10+ menit).

Cek findings di BigQuery (tunggu beberapa menit):

  bq query --apilog=/dev/null --use_legacy_sql=false \\
    "SELECT finding_id, event_time, finding.category FROM continuous_export_dataset.findings"

Klik Check my progress untuk Task 2.
EOF

# ================================================================== Task 3: GCS bucket
step "Task 3: Create GCS bucket"

BUCKET="scc-export-bucket-$PROJECT"
if gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gsutil mb -p "$PROJECT" -l "$REGION" -b on "gs://$BUCKET"
fi

cat <<EOF

Bucket gs://$BUCKET sudah dibuat.
SEKARANG EXPORT + CREATE TABLE MANUAL DI CONSOLE:

1. Buka Navigation menu > Security > Findings
2. Klik Export > Cloud Storage
3. Project: $PROJECT
4. Export path: Browse > pilih bucket > filename: findings.jsonl
5. Format: JSONL
6. Time Range: All time
7. Klik Export

Setelah export selesai, buat tabel di BigQuery:

1. Buka Navigation menu > BigQuery > Studio
2. Klik + Add data > Google Cloud Storage > External or Lakehouse Table
3. Isi:
   - Create table from: Google Cloud Storage
   - File: gs://$BUCKET/findings.jsonl
   - File format: JSONL
   - Dataset: continuous_export_dataset
   - Table: old_findings
   - Table type: Native table
   - Schema: Enable "Edit as text", paste:
     [
       {"mode": "NULLABLE", "name": "resource", "type": "JSON"},
       {"mode": "NULLABLE", "name": "finding", "type": "JSON"}
     ]
4. Klik Create table
5. Klik Preview tab untuk verifikasi

Klik Check my progress untuk Task 3.
EOF

# ================================================================== Verification
step "Verifikasi"

echo "Pub/Sub topics:"
gcloud pubsub topics list --project="$PROJECT"

echo ""
echo "Pub/Sub subscriptions:"
gcloud pubsub subscriptions list --project="$PROJECT"

echo ""
echo "Compute instances:"
gcloud compute instances list --project="$PROJECT"

echo ""
echo "BigQuery datasets:"
bq ls --project_id="$PROJECT"

echo ""
echo "GCS buckets:"
gsutil ls -p "$PROJECT"

cat <<EOF

==============================================================
SELESAI!

Checklist manual di Console:
  Task 1: Continuous export ke Pub/Sub + cek messages
  Task 2: Cek BigQuery findings (tunggu 10+ menit)
  Task 3: Export ke GCS + buat BigQuery table
==============================================================
EOF
