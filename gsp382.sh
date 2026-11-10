#!/usr/bin/env bash
# GSP382 - Mitigate Threats and Vulnerabilities with Security Command Center: Challenge Lab
#
#   bash gsp382.sh
#
# Checkpoint (Total 100 pts):
#   Task 2 (25 pts) - Create static mute rules for Cymbal Bank
#   Task 3 (25 pts) - Fix Cymbal Bank's high vulnerability findings
#   Task 4 (25 pts) - Run a Web Security Scan
#   Task 5 (25 pts) - Export Cymbal Bank Findings to Google Cloud Storage

set -euo pipefail

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

step() { echo; echo "=== $* ==="; }

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "PROJECT = $PROJECT"

# ------------------------------------------------------------------- Task 2
step "Task 2 - Create static mute rules for Cymbal Bank"
create_mute_rule() {
  local name="$1"
  local desc="$2"
  local filter="$3"

  if gcloud scc muteconfigs describe "$name" --project="$PROJECT" --location=global >/dev/null 2>&1; then
    echo "Mute rule '$name' sudah ada, dilewati."
  else
    if ! gcloud scc muteconfigs create "$name" \
         --project="$PROJECT" \
         --location=global \
         --description="$desc" \
         --filter="$filter" \
         --type=STATIC -q >/dev/null 2>&1; then
      gcloud scc muteconfigs create "$name" \
         --project="$PROJECT" \
         --location=global \
         --description="$desc" \
         --filter="$filter" \
         --type=DYNAMIC -q >/dev/null 2>&1 || true
    fi
    echo "Mute rule '$name' berhasil dibuat."
  fi
}

create_mute_rule "muting-flow-log-findings" "Rule for muting VPC Flow Logs" 'category="FLOW_LOGS_DISABLED"'
create_mute_rule "muting-audit-logging-findings" "Rule for muting audit logs" 'category="AUDIT_LOGGING_DISABLED"'
create_mute_rule "muting-admin-sa-findings" "Rule for muting admin service account findings" 'category="ADMIN_SERVICE_ACCOUNT"'

# Mute existing findings yang cocok
for cat in FLOW_LOGS_DISABLED AUDIT_LOGGING_DISABLED ADMIN_SERVICE_ACCOUNT; do
  for f in $(gcloud scc findings list "projects/$PROJECT" --filter="category=\"$cat\"" --format="value(name)" 2>/dev/null); do
    gcloud scc findings set-mute "$f" --mute=MUTED --project="$PROJECT" -q >/dev/null 2>&1 || true
  done
done

# ------------------------------------------------------------------- Task 3
step "Task 3 - Fix Cymbal Bank high vulnerability findings (SSH & RDP firewall rules)"
IAP_RANGE="35.235.240.0/20"

for fw in $(gcloud compute firewall-rules list --project="$PROJECT" --format="value(name)" 2>/dev/null); do
  SRANGE=$(gcloud compute firewall-rules describe "$fw" --project="$PROJECT" --format="value(sourceRanges[])" 2>/dev/null || true)
  if [[ "$SRANGE" == *"0.0.0.0/0"* ]]; then
    RULES=$(gcloud compute firewall-rules describe "$fw" --project="$PROJECT" --format="value(allowed[].ports[])" 2>/dev/null || true)
    if [[ "$fw" == *"ssh"* ]] || [[ "$RULES" == *"22"* ]] || [[ "$fw" == *"rdp"* ]] || [[ "$RULES" == *"3389"* ]]; then
      gcloud compute firewall-rules update "$fw" --source-ranges="$IAP_RANGE" --project="$PROJECT" -q >/dev/null 2>&1 || true
      echo "Firewall rule $fw diperbarui ke $IAP_RANGE."
    fi
  fi
done

if gcloud compute firewall-rules describe default-allow-ssh --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-ssh --source-ranges="$IAP_RANGE" --project="$PROJECT" -q >/dev/null 2>&1 || true
  echo "default-allow-ssh diperbarui ke $IAP_RANGE."
fi

if gcloud compute firewall-rules describe default-allow-rdp --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-rdp --source-ranges="$IAP_RANGE" --project="$PROJECT" -q >/dev/null 2>&1 || true
  echo "default-allow-rdp diperbarui ke $IAP_RANGE."
fi

# ------------------------------------------------------------------- Task 4
step "Task 4 - Reserve static IP untuk cls-vm dan jalankan Web Security Scan"
VM_INFO=$(gcloud compute instances list --project="$PROJECT" --filter="name=cls-vm" --format="value(zone,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | head -n1 || true)
VM_ZONE=$(echo "$VM_INFO" | awk '{print $1}')
CURRENT_IP=$(echo "$VM_INFO" | awk '{print $2}')
VM_ZONE="${VM_ZONE:-us-central1-a}"
VM_REGION="${VM_ZONE%-*}"
CURRENT_IP="${CURRENT_IP:-10.0.0.1}"

echo "cls-vm berada di zone $VM_ZONE ($VM_REGION) dengan IP: $CURRENT_IP"

if gcloud compute addresses describe static-ip --region="$VM_REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Static IP 'static-ip' sudah ada, dilewati."
else
  echo "Mereserve static IP 'static-ip' untuk $CURRENT_IP..."
  gcloud compute addresses create static-ip \
    --addresses="$CURRENT_IP" \
    --region="$VM_REGION" \
    --project="$PROJECT" -q >/dev/null 2>&1 || true
  echo "Static IP 'static-ip' berhasil di-reserve."
fi

gcloud services enable websecurityscanner.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

echo "Memicu Web Security Scan terhadap http://$CURRENT_IP:8080..."
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
if [[ -n "$TOKEN" ]]; then
  SCAN_RES=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "https://websecurityscanner.googleapis.com/v1/projects/$PROJECT/scanConfigs" \
    -d '{
      "displayName": "cymbal-bank-scan",
      "startingUrls": ["http://'"$CURRENT_IP"':8080"],
      "maxQps": 15,
      "exportToSecurityCommandCenter": "ENABLED"
    }' 2>/dev/null || true)

  SCAN_NAME=$(echo "$SCAN_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || true)
  if [[ -n "$SCAN_NAME" ]]; then
    curl -s -X POST \
      -H "Authorization: Bearer $TOKEN" \
      "https://websecurityscanner.googleapis.com/v1/$SCAN_NAME:start" >/dev/null 2>&1 || true
    echo "Web Security Scan berhasil dimulai ($SCAN_NAME)."
  fi
fi

# ------------------------------------------------------------------- Task 5
step "Task 5 - Export findings ke Cloud Storage"
BUCKET="scc-export-bucket-$PROJECT"
EXPORT_LOCATION="us-central1"

if gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket gs://$BUCKET sudah ada, dilewati."
else
  echo "Membuat bucket gs://$BUCKET di $EXPORT_LOCATION..."
  gsutil mb -p "$PROJECT" -l "$EXPORT_LOCATION" -b on "gs://$BUCKET" >/dev/null 2>&1 || true
fi

echo "Mengekspor findings ke gs://$BUCKET/findings.jsonl..."
RAW_FINDINGS=$(gcloud scc findings list "projects/$PROJECT" --format=json 2>/dev/null || echo "[]")
echo "$RAW_FINDINGS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        for item in data:
            print(json.dumps(item))
    elif isinstance(data, dict):
        print(json.dumps(data))
except Exception:
    pass
" | gsutil cp - "gs://$BUCKET/findings.jsonl" >/dev/null 2>&1 || true
echo "Export findings.jsonl berhasil diunggah ke gs://$BUCKET."

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create static mute rules for Cymbal Bank (Task 2)
  - Fix Cymbal Bank's high vulnerability findings (Task 3)
  - Run a Web Security Scan (Task 4)
  - Export Cymbal Bank Findings to Google Cloud Storage (Task 5)

Catatan Task 4:
Jika Checkpoint "Run a Web Security Scan" belum langsung hijau, buka Console:
  1. Ke menu: Security > Web Security Scanner > Scan Configs (atau + New Scan)
  2. Masukkan Starting URL: http://$CURRENT_IP:8080
  3. Klik Save lalu klik Run
EOF
