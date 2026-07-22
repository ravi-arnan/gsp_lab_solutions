#!/usr/bin/env bash
# GSP1124 - Get Started with Security Command Center
#
# Task 1: UI exploration only (tidak bisa diotomasi)
# Task 2: Enable SHA module (harus manual di Console)
# Task 3: Mute rules + firewall rules + buat network
#
# Cara pakai:
#   bash gsp1124.sh
#
# Setelah script selesai, klik Check my progress untuk task 2 dan 3.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== Enable SCC API
step "Enable Security Command Center API"
gcloud services enable securitycenter.googleapis.com --project="$PROJECT"
echo "Waiting for API to propagate..."
sleep 30

# ================================================================== Task 2: SHA Module - MANUAL
step "Task 2: SHA Module - MANUAL di Console"

cat <<EOF

Enable SHA module manual di Console:

1. Buka Navigation menu > Security > Settings
2. Pastikan tab Services aktif
3. Klik Manage settings di Security Health Analytics
4. Klik tab Modules
5. Di filter field, ketik: VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED
6. Klik dropdown Status (Disabled) > pilih Enable
7. Tunggu beberapa menit sampai enabled

Setelah itu, klik Check my progress untuk Task 2.
EOF

# ================================================================== Task 3a: Create mute rule
step "Task 3a: Create mute rule for FLOW_LOGS_DISABLED"

if gcloud scc muteconfigs describe mute-flowlogs-findings \
  --project="$PROJECT" --location=global >/dev/null 2>&1; then
  echo "Mute rule sudah ada, dilewat."
else
  gcloud scc muteconfigs create mute-flowlogs-findings \
    --project="$PROJECT" \
    --location=global \
    --description="Mute rule for VPC Flow Logs" \
    --filter='category="FLOW_LOGS_DISABLED"' \
    --type=DYNAMIC
  echo "Mute rule 'mute-flowlogs-findings' created."
fi

# ================================================================== Task 3b: Create VPC network
step "Task 3b: Create VPC network scc-lab-net"

if gcloud compute networks describe scc-lab-net --project="$PROJECT" >/dev/null 2>&1; then
  echo "Network scc-lab-net already exists, skipping."
else
  gcloud compute networks create scc-lab-net --subnet-mode=auto --project="$PROJECT"
fi

# ================================================================== Task 3c: Update firewall rules
step "Task 3c: Update firewall rules (RDP and SSH)"

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
gcloud scc muteconfigs list --project="$PROJECT" --location=global

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk:
  - Task 2: Enable SHA module (manual di Console)
  - Task 3: Create a mute rule
  - Task 3: Create a network
  - Task 3: Update the firewall rules
==============================================================
EOF
