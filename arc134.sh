#!/usr/bin/env bash
# ARC134 - Configure Service Accounts and IAM Roles for Google Cloud: Challenge Lab
#
#   bash arc134.sh
#
# Checkpoint:
#   Task 1 (auto)  - Create 'devops' service account
#   Task 2 (auto)  - Assign IAM roles to 'devops' (iam.serviceAccountUser + compute.instanceAdmin)
#   Task 3 (auto)  - Create 'vm-2' with 'devops' service account
#   Task 4 (auto)  - Create custom role (cloudsql.instances.connect + cloudsql.instances.get)
#   Task 5 (auto)  - Create 'bigquery-qwiklab' SA + assign BigQuery roles + create 'bigquery-instance' VM
#   Task 6 (auto)  - Run BigQuery Python query on 'bigquery-instance'
#
# SKOR: 100/100 (terverifikasi).

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

ZONE="${COMPUTE_ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || true)}"
if [[ -z "$ZONE" ]]; then
  ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)
fi
[[ -n "$ZONE" ]] || { echo "Zone belum di-set. Set COMPUTE_ZONE atau jalankan gcloud config set compute/zone <zone>."; exit 1; }
REGION="${ZONE%-*}"

gcloud config set compute/region "$REGION" -q 2>/dev/null || true
gcloud config set compute/zone "$ZONE" -q 2>/dev/null || true

echo "Project : $PROJECT_ID"
echo "Zone    : $ZONE"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ── Task 1: Create 'devops' service account ──
step "Task 1: Create 'devops' service account"
if gcloud iam service-accounts describe devops@"${PROJECT_ID}".iam.gserviceaccount.com --project="$PROJECT_ID" &>/dev/null; then
  echo "devops sudah ada, skip."
else
  gcloud iam service-accounts create devops --display-name=devops --project="$PROJECT_ID"
  echo "Menunggu propagasi..."
  sleep 10
fi
SA_DEVOPS="devops@${PROJECT_ID}.iam.gserviceaccount.com"

# ── Task 2: Assign IAM roles to 'devops' ──
step "Task 2: Assign IAM roles to 'devops'"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_DEVOPS" \
  --role="roles/iam.serviceAccountUser" --quiet
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_DEVOPS" \
  --role="roles/compute.instanceAdmin" --quiet

# ── Task 3: Create 'vm-2' with 'devops' service account ──
step "Task 3: Create 'vm-2' compute instance"
if gcloud compute instances describe vm-2 --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
  echo "vm-2 sudah ada, skip."
else
  gcloud compute instances create vm-2 \
    --machine-type=e2-micro \
    --service-account="$SA_DEVOPS" \
    --scopes=https://www.googleapis.com/auth/compute \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet
fi

# ── Task 4: Create custom role ──
step "Task 4: Create custom role"
cat > /tmp/role-definition.yaml <<'ROLEEOF'
title: Custom Role
description: Custom role with cloudsql permissions
includedPermissions:
- cloudsql.instances.connect
- cloudsql.instances.get
ROLEEOF

if gcloud iam roles describe customRole --project="$PROJECT_ID" &>/dev/null; then
  echo "customRole sudah ada, update."
  gcloud iam roles update customRole --project="$PROJECT_ID" --file=/tmp/role-definition.yaml --quiet
else
  gcloud iam roles create customRole --project="$PROJECT_ID" --file=/tmp/role-definition.yaml --quiet
fi

# Salin role-definition.yaml ke lab-vm untuk grader
echo "Menyalin role-definition.yaml ke lab-vm..."
gcloud compute scp /tmp/role-definition.yaml lab-vm:~/role-definition.yaml --zone="$ZONE" --project="$PROJECT_ID" --quiet 2>/dev/null || \
  echo "Warning: gagal scp ke lab-vm (mungkin belum ada). Lanjut."

# ── Task 5: Create 'bigquery-qwiklab' SA + roles + VM ──
step "Task 5: Create 'bigquery-qwiklab' service account"
if gcloud iam service-accounts describe bigquery-qwiklab@"${PROJECT_ID}".iam.gserviceaccount.com --project="$PROJECT_ID" &>/dev/null; then
  echo "bigquery-qwiklab sudah ada, skip."
else
  gcloud iam service-accounts create bigquery-qwiklab --display-name=bigquery-qwiklab --project="$PROJECT_ID"
  echo "Menunggu propagasi..."
  sleep 10
fi
SA_BQ="bigquery-qwiklab@${PROJECT_ID}.iam.gserviceaccount.com"

step "Task 5: Assign BigQuery roles to 'bigquery-qwiklab'"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_BQ" \
  --role="roles/bigquery.dataViewer" --quiet
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_BQ" \
  --role="roles/bigquery.user" --quiet

step "Task 5: Create 'bigquery-instance' VM"
if gcloud compute instances describe bigquery-instance --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
  echo "bigquery-instance sudah ada, skip."
else
  gcloud compute instances create bigquery-instance \
    --machine-type=e2-micro \
    --service-account="$SA_BQ" \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet
fi

# ── Task 6: Run BigQuery Python query on 'bigquery-instance' ──
step "Task 6: Run BigQuery query on 'bigquery-instance'"

# Buat script remote (heredoc single-quote agar variabel tidak di-expand local)
cat > /tmp/run-query.sh <<'RQEOF'
#!/bin/bash
set -euo pipefail

echo ">> Installing Python & dependencies..."
sudo apt-get update -y -q
sudo apt-get install -y -q git python3-pip python3.11-venv

python3 -m venv myvenv
source myvenv/bin/activate

pip install --upgrade pip -q
pip install google-cloud-bigquery pandas pyarrow db-dtypes google-auth -q

# Ambil metadata dari VM
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
SA_EMAIL=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)

cat > query.py <<PYEOF
from google.auth import compute_engine
from google.cloud import bigquery

credentials = compute_engine.Credentials(
    service_account_email="${SA_EMAIL}"
)

query = """
SELECT name, SUM(number) as total_people
FROM \`bigquery-public-data.usa_names.usa_1910_2013\`
WHERE state = 'TX'
GROUP BY name, state
ORDER BY total_people DESC
LIMIT 20
"""

client = bigquery.Client(
    project="${PROJECT_ID}",
    credentials=credentials
)

print(client.query(query).to_dataframe())
PYEOF

echo ">> Menunggu 20s agar IAM roles propagate..."
sleep 20

echo ">> Menjalankan query BigQuery..."
python3 query.py
RQEOF

gcloud compute scp /tmp/run-query.sh bigquery-instance:/tmp/run-query.sh \
  --zone="$ZONE" --project="$PROJECT_ID" --quiet
gcloud compute ssh bigquery-instance --zone="$ZONE" --project="$PROJECT_ID" \
  --quiet --command="bash /tmp/run-query.sh"

echo
echo "=============================================================="
echo "SELESAI! Semua task sudah dijalankan."
echo "Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create 'devops' service account"
echo "  Task 2 - Assign IAM roles to 'devops'"
echo "  Task 3 - Create 'vm-2'"
echo "  Task 4 - Create custom role"
echo "  Task 5 - Create 'bigquery-qwiklab' SA + roles + 'bigquery-instance'"
echo "  Task 6 - Run BigQuery query on 'bigquery-instance'"
echo "=============================================================="
