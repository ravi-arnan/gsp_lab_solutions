#!/usr/bin/env bash
# GSP1124 - Get Started with Security Command Center
#
#   bash gsp1124.sh
#
# Checkpoint:
#   Task 3 - Create a mute rule
#   Task 3 - Create a network
#   Task 3 - Update the firewall rules
#
# Catatan: Task 1 dan Task 2 adalah eksplorasi interface dan konfigurasi module
# di Console tanpa checkpoint. Seluruh penilaian skor (100/100) berada di Task 3
# dan selesai otomatis sekali jalan.

set -euo pipefail

step() { echo; echo "=== $* ==="; }

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "PROJECT = $PROJECT"

# ------------------------------------------------------------------- Task 1
step "Task 1 - Enable Security Health Analytics dan refresh metadata VPC"
gcloud services enable securitycenter.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

gcloud scc manage services update sha \
  --project="$PROJECT" \
  --enablement-state=ENABLED >/dev/null 2>&1 || true

gcloud compute networks update default --bgp-routing-mode=regional >/dev/null 2>&1 || true
gcloud compute networks subnets update default \
  --region=us-central1 \
  --no-enable-private-ip-google-access >/dev/null 2>&1 || true
gcloud compute firewall-rules update default-allow-ssh \
  --description="Allow SSH from anywhere" >/dev/null 2>&1 || true
gcloud compute firewall-rules update default-allow-rdp \
  --description="Allow RDP from anywhere" >/dev/null 2>&1 || true

# ------------------------------------------------------------------- Task 3a
step "Task 3 - Create mute rule mute-flowlogs-findings"
if gcloud scc muteconfigs describe mute-flowlogs-findings \
  --project="$PROJECT" --location=global >/dev/null 2>&1; then
  echo "Mute rule sudah ada, dilewati"
else
  gcloud scc muteconfigs create mute-flowlogs-findings \
    --project="$PROJECT" \
    --location=global \
    --description="Mute rule for VPC Flow Logs" \
    --filter='category="FLOW_LOGS_DISABLED"' \
    --type=DYNAMIC -q
  echo "Mute rule 'mute-flowlogs-findings' berhasil dibuat"
fi

# ------------------------------------------------------------------- Task 3b
step "Task 3 - Create VPC network scc-lab-net"
if gcloud compute networks describe scc-lab-net --project="$PROJECT" >/dev/null 2>&1; then
  echo "Network scc-lab-net sudah ada, dilewati"
else
  gcloud compute networks create scc-lab-net --subnet-mode=auto --project="$PROJECT" -q
  echo "Network scc-lab-net berhasil dibuat"
fi

# ------------------------------------------------------------------- Task 3c
step "Task 3 - Update firewall rules default-allow-rdp dan default-allow-ssh"
IAP_RANGE="35.235.240.0/20"

if gcloud compute firewall-rules describe default-allow-rdp --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-rdp \
    --source-ranges="$IAP_RANGE" \
    --project="$PROJECT" -q
  echo "default-allow-rdp berhasil diperbarui ke $IAP_RANGE"
else
  gcloud compute firewall-rules create default-allow-rdp \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges="$IAP_RANGE" \
    --project="$PROJECT" -q
fi

if gcloud compute firewall-rules describe default-allow-ssh --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules update default-allow-ssh \
    --source-ranges="$IAP_RANGE" \
    --project="$PROJECT" -q
  echo "default-allow-ssh berhasil diperbarui ke $IAP_RANGE"
else
  gcloud compute firewall-rules create default-allow-ssh \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges="$IAP_RANGE" \
    --project="$PROJECT" -q
fi

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create a mute rule
  - Create a network
  - Update the firewall rules
EOF
