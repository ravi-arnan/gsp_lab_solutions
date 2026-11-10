#!/usr/bin/env bash
# GSP1125 - Detect and Investigate Threats with Security Command Center
#
#   bash gsp1125.sh
#
# Checkpoint (Total 60 pts):
#   Task 1 (20 pts) - Initiate and mitigate a threat with Event Threat Detection
#   Task 2 (20 pts) - Configure a cloud environment to detect threats
#   Task 3 (20 pts) - Manage SCC findings with Event Threat Detection

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "PROJECT = $PROJECT"

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
ask ZONE "${REGION}-f" "Zone (cocokkan dengan panel lab)"

# ------------------------------------------------------------------- Setup: API
step "Setup - Enable Security Command Center API dan Security Health Analytics"
gcloud services enable securitycenter.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true
gcloud scc manage services update sha \
  --project="$PROJECT" \
  --enablement-state=ENABLED >/dev/null 2>&1 || true

# ------------------------------------------------------------------- Task 1
step "Task 1 - Initiate and mitigate a threat with Event Threat Detection"
echo "Menambahkan role BigQuery Admin ke demouser1@gmail.com..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:demouser1@gmail.com" \
  --role="roles/bigquery.admin" \
  --condition=None -q >/dev/null

echo "Menunggu propagasi event (5 detik)..."
sleep 5

echo "Mencabut role BigQuery Admin dari demouser1@gmail.com..."
gcloud projects remove-iam-policy-binding "$PROJECT" \
  --member="user:demouser1@gmail.com" \
  --role="roles/bigquery.admin" \
  --condition=None -q >/dev/null
echo "Akses demouser1@gmail.com berhasil dicabut."

# ------------------------------------------------------------------- Task 2a: Audit Logs
step "Task 2 - Configure Cloud Resource Manager Admin Read audit logs"
TMP_POLICY=$(mktemp)
gcloud projects get-iam-policy "$PROJECT" --format=json > "$TMP_POLICY"
python3 -c "
import json
with open('$TMP_POLICY', 'r') as f:
    policy = json.load(f)
if not isinstance(policy, dict):
    policy = {}
audit_configs = policy.get('auditConfigs', [])
crm_config = next((item for item in audit_configs if item.get('service') == 'cloudresourcemanager.googleapis.com'), None)
if not crm_config:
    audit_configs.append({
        'service': 'cloudresourcemanager.googleapis.com',
        'auditLogConfigs': [{'logType': 'ADMIN_READ'}]
    })
else:
    log_types = [c.get('logType') for c in crm_config.get('auditLogConfigs', [])]
    if 'ADMIN_READ' not in log_types:
        crm_config.setdefault('auditLogConfigs', []).append({'logType': 'ADMIN_READ'})
policy['auditConfigs'] = audit_configs
with open('$TMP_POLICY', 'w') as f:
    json.dump(policy, f)
"
gcloud projects set-iam-policy "$PROJECT" "$TMP_POLICY" -q >/dev/null
rm -f "$TMP_POLICY"
echo "Audit logs ADMIN_READ untuk Cloud Resource Manager berhasil diaktifkan."

# ------------------------------------------------------------------- Task 3a: DNS Policy
step "Task 3 - Create DNS server policy dns-test-policy with logging enabled"
if gcloud dns policies describe dns-test-policy --project="$PROJECT" >/dev/null 2>&1; then
  echo "DNS policy dns-test-policy sudah ada, dilewati."
else
  gcloud dns policies create dns-test-policy \
    --networks="default" \
    --enable-logging \
    --description="DNS policy with logging" \
    --project="$PROJECT" -q
  echo "DNS policy dns-test-policy berhasil dibuat."
fi

# ------------------------------------------------------------------- Task 2b & 3b: VM Trigger
step "Task 2 & 3 - Create VM instance-1 dan jalankan simulasi ancaman"
if gcloud compute instances describe instance-1 --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "VM instance-1 sudah ada."
else
  echo "Membuat VM instance-1 di $ZONE..."
  gcloud compute instances create instance-1 \
    --zone="$ZONE" \
    --machine-type="e2-micro" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --metadata=startup-script='#!/bin/bash
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
gcloud projects get-iam-policy "$PROJECT_ID" >/dev/null 2>&1 || true
curl -m 10 -s http://etd-malware-trigger.goog >/dev/null 2>&1 || true
' \
    --project="$PROJECT" -q
  echo "VM instance-1 berhasil diluncurkan."
fi

echo "Menunggu VM memproses startup script dan mencatat event ancaman (15 detik)..."
sleep 15

# Eksekusi tambahan via SSH sebagai kepastian ganda
if gcloud compute ssh instance-1 --zone="$ZONE" --project="$PROJECT" --quiet < /dev/null --command="
  gcloud projects get-iam-policy \$(gcloud config get-value project) >/dev/null 2>&1 || true
  curl -m 10 -s http://etd-malware-trigger.goog >/dev/null 2>&1 || true
" >/dev/null 2>&1; then
  echo "Simulasi ancaman berhasil diverifikasi via SSH."
else
  echo "Simulasi ancaman selesai dijalankan oleh startup script."
fi

# ------------------------------------------------------------------- Cleanup VM
step "Cleanup - Menghapus VM instance-1 sesuai instruksi Task 3"
gcloud compute instances delete instance-1 --zone="$ZONE" --project="$PROJECT" -q
echo "VM instance-1 berhasil dihapus."

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Initiate and mitigate a threat with Event Threat Detection (Task 1)
  - Configure a cloud environment to detect threats (Task 2)
  - Manage SCC findings with Event Threat Detection (Task 3)
EOF
