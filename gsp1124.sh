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

# SHA module enablement - MANUAL di Console
step "Task 2: SHA Module - MANUAL di Console"

cat <<EOF

SHA module TIDAK BISA di-enable via API di lab ini.
Enable manual di Console:

1. Buka Navigation menu > Security > Settings
2. Pastikan tab Services aktif
3. Klik Manage settings di Security Health Analytics
4. Klik tab Modules
5. Di filter field, ketik: VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED
6. Klik dropdown Status (Disabled) > pilih Enable
7. Tunggu beberapa menit sampai enabled

Setelah itu, klik Check my progress untuk Task 2.
EOF

# ================================================================== Task 3a: Mute rule - MANUAL di Console
step "Task 3a: Mute rule - HARUS MANUAL di Console"

cat <<EOF

Mute rule TIDAK BISA dibuat via API di lab ini.
Buat manual di Console:

1. Buka Navigation menu > Security > Overview
2. Klik Findings di menu kiri
3. Klik Mute options > Manage mute rules
4. Klik Create mute rule
5. Isi:
   - Mute rule ID: mute-flowlogs-findings
   - Description: Mute rule for VPC Flow Logs
   - Findings query: category="FLOW_LOGS_DISABLED"
6. Klik Save

Setelah itu, klik Check my progress untuk "Create a mute rule"
EOF

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
echo "Mute rules: (check di Console > Findings > Mute options > Manage mute rules)"

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
