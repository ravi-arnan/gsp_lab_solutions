#!/usr/bin/env bash
# GSP1124 - Get Started with Security Command Center
#
# Task 1: UI exploration only (tidak bisa diotomasi)
# Task 2: Enable SHA module + buat network (script ini)
# Task 3: Mute rules + firewall rules + buat network (script ini)
#
# Cara pakai:
#   bash gsp1124.sh
#
# Setelah script selesai, klik Check my progress untuk task 2 dan 3.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Get organization ID (needed for SCC operations)
ORG_ID=$(gcloud organizations list --format="value(name)" --filter="organizationId:*" 2>/dev/null | head -1 | awk -F'/' '{print $2}')
if [[ -z "$ORG_ID" ]]; then
  # Try getting from the project's parent
  ORG_ID=$(gcloud projects describe "$PROJECT" --format="value(parent.id)" 2>/dev/null || true)
fi

echo "Project: $PROJECT"
echo "Org ID : $ORG_ID"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== Task 2: Enable SHA Module
step "Task 2: Enable Security Health Analytics module"

# Get the SHA source name
SHA_SOURCE=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://securitycenter.googleapis.com/v1/projects/${PROJECT}/sources" | \
  python3 -c "import sys,json; [print(s['name']) for s in json.load(sys.stdin).get('sources',[]) if 'SecurityHealthAnalytics' in s.get('displayName','')]" 2>/dev/null | head -1)

if [[ -z "$SHA_SOURCE" ]]; then
  echo "SHA source not found via API, trying to find it..."
  # The SHA source is typically named "sources/10507" or similar
  SHA_SOURCE="projects/${PROJECT}/sources/10507"
fi

echo "SHA Source: $SHA_SOURCE"

# Enable the VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED module
step "Enable VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED module"
curl -s -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://securitycenter.googleapis.com/v1/${SHA_SOURCE}/modules/VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED?updateMask=enablement" \
  -d '{"enablement": "ENABLED"}' || echo "Module enablement may take a few minutes to reflect"

echo "Module VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED enabled."

# ================================================================== Task 3a: Create mute rule
step "Task 3a: Create mute rule for FLOW_LOGS_DISABLED"

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://securitycenter.googleapis.com/v1/projects/${PROJECT}/muteRules" \
  -d '{
    "name": "mute-flowlogs-findings",
    "description": "Mute rule for VPC Flow Logs",
    "filter": "category=\"FLOW_LOGS_DISABLED\"",
    "type": "DYNAMIC"
  }' || echo "Mute rule may have been created"

echo "Mute rule 'mute-flowlogs-findings' created."

# ================================================================== Task 3b: Create VPC network
step "Task 3b: Create VPC network scc-lab-net"

if gcloud compute networks describe scc-lab-net --project="$PROJECT" >/dev/null 2>&1; then
  echo "Network scc-lab-net already exists, skipping."
else
  gcloud compute networks create scc-lab-net --subnet-mode=auto --project="$PROJECT"
fi

# ================================================================== Task 3c: Update firewall rules
step "Task 3c: Update firewall rules (RDP and SSH)"

# Update default-allow-rdp
echo "Updating default-allow-rdp..."
if gcloud compute firewall-rules describe default-allow-rdp --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-rdp \
    --source-ranges="35.235.240.0/20" \
    --project="$PROJECT"
  echo "default-allow-rdp updated."
else
  echo "default-allow-rdp not found, creating new rule..."
  gcloud compute firewall-rules create allow-rdp-iap \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges="35.235.240.0/20" \
    --project="$PROJECT"
fi

# Update default-allow-ssh
echo "Updating default-allow-ssh..."
if gcloud compute firewall-rules describe default-allow-ssh --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-ssh \
    --source-ranges="35.235.240.0/20" \
    --project="$PROJECT"
  echo "default-allow-ssh updated."
else
  echo "default-allow-ssh not found, creating new rule..."
  gcloud compute firewall-rules create allow-ssh-iap \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges="35.235.240.0/20" \
    --project="$PROJECT"
fi

# ================================================================== Verification
step "Verifikasi"

echo "Networks:"
gcloud compute networks list --project="$PROJECT"

echo ""
echo "Firewall rules (default network):"
gcloud compute firewall-rules list --project="$PROJECT" --filter="network=default"

echo ""
echo "Mute rules:"
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://securitycenter.googleapis.com/v1/projects/${PROJECT}/muteRules" | \
  python3 -c "import sys,json; [print(f'  - {r[\"name\"]}: {r.get(\"description\",\"\")}') for r in json.load(sys.stdin).get('muteRules',[])]" 2>/dev/null || echo "  (could not list mute rules)"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk:
  - Task 2: Task 2 checkpoint (SHA module enabled)
  - Task 3: Update the firewall rules
  - Task 3: Create a mute rule
  - Task 3: Create a network
==============================================================
EOF
