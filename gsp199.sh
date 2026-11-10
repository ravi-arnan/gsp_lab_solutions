#!/usr/bin/env bash
# GSP199 - Service Accounts and Roles: Fundamentals
#
#   bash gsp199.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Create and Manage Service Accounts
#   Task 2 (50 pts) - Access BigQuery using a Service Account

set -euo pipefail

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
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

step() { echo; echo "=== $* ==="; }

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "PROJECT_ID = $PROJECT_ID"

ask REGION "us-east4" "Region (cocokkan dengan panel lab)"
ask ZONE "${REGION}-c" "Zone (cocokkan dengan panel lab)"

gcloud config set compute/region "$REGION" >/dev/null 2>&1 || true
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1 || true

# ------------------------------------------------------------------- Task 1
step "Task 1 - Create and manage service account my-sa-123"
SA_1="my-sa-123@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Service account my-sa-123 sudah ada, dilewati."
else
  gcloud iam service-accounts create my-sa-123 \
    --display-name="my service account" \
    --project="$PROJECT_ID" -q
  echo "Service account my-sa-123 berhasil dibuat."
fi

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_1" \
  --role="roles/storage.admin" \
  --condition=None -q >/dev/null
echo "Role roles/storage.admin berhasil diberikan ke my-sa-123."

# ------------------------------------------------------------------- Task 2
step "Task 2a - Create service account bigquery-qwiklab dan berikan BigQuery roles"
SA_BQ="bigquery-qwiklab@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_BQ" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Service account bigquery-qwiklab sudah ada, dilewati."
else
  gcloud iam service-accounts create bigquery-qwiklab \
    --display-name="bigquery-qwiklab" \
    --project="$PROJECT_ID" -q
  echo "Service account bigquery-qwiklab berhasil dibuat."
fi

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_BQ" \
  --role="roles/bigquery.dataViewer" \
  --condition=None -q >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_BQ" \
  --role="roles/bigquery.user" \
  --condition=None -q >/dev/null
echo "Role roles/bigquery.dataViewer dan roles/bigquery.user berhasil diberikan ke bigquery-qwiklab."

step "Task 2b - Create VM instance bigquery-instance"
if gcloud compute instances describe bigquery-instance --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM bigquery-instance sudah ada, dilewati."
else
  gcloud compute instances create bigquery-instance \
    --zone="$ZONE" \
    --machine-type="e2-medium" \
    --image-family="debian-12" \
    --image-project="debian-cloud" \
    --service-account="$SA_BQ" \
    --scopes="https://www.googleapis.com/auth/bigquery,https://www.googleapis.com/auth/cloud-platform" \
    --project="$PROJECT_ID" -q
  echo "VM bigquery-instance berhasil dibuat."
fi

step "Task 2c - Setup Python dependencies dan jalankan query di VM"
echo "Menunggu VM siap menerima koneksi SSH..."
for i in {1..30}; do
  if gcloud compute ssh bigquery-instance --zone="$ZONE" --project="$PROJECT_ID" --quiet < /dev/null --command="echo ready" >/dev/null 2>&1; then
    echo "Koneksi SSH berhasil."
    break
  fi
  sleep 4
done

cat << 'EOF_REMOTE' > /tmp/run_query.sh
#!/bin/bash
set -euo pipefail

sudo apt-get update -y -q
sudo apt-get install -y -q python3 python3-pip python3.11-venv git

python3 -m venv ~/myvenv
source ~/myvenv/bin/activate

pip install --upgrade pip -q
pip install google-cloud-bigquery pyarrow pandas db-dtypes -q

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
SA_EMAIL=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)

cat << PYEOF > ~/query.py
from google.auth import compute_engine
from google.cloud import bigquery

credentials = compute_engine.Credentials(
    service_account_email='${SA_EMAIL}'
)

query = '''
SELECT
  year,
  COUNT(1) as num_babies
FROM
  publicdata.samples.natality
WHERE
  year > 2000
GROUP BY
  year
'''

client = bigquery.Client(
    project='${PROJECT_ID}',
    credentials=credentials
)
print(client.query(query).to_dataframe())
PYEOF

python3 ~/query.py
EOF_REMOTE

echo "Menyalin script query ke VM..."
gcloud compute scp /tmp/run_query.sh bigquery-instance:/tmp/run_query.sh \
  --zone="$ZONE" --project="$PROJECT_ID" --quiet < /dev/null

echo "Menjalankan query BigQuery via client library di VM..."
gcloud compute ssh bigquery-instance --zone="$ZONE" --project="$PROJECT_ID" \
  --quiet < /dev/null --command="bash /tmp/run_query.sh"

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create and Manage Service Accounts (Task 1)
  - Access BigQuery using a Service Account (Task 2)
EOF
