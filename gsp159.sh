#!/usr/bin/env bash
# GSP159 - Create a Custom Network and Apply Firewall Rules
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp159.sh
#   bash gsp159.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Create a custom network and subnetworks
#   Task 2 (50 pts) - Create firewall rules
#
# Parameter dapat disesuaikan lewat env var jika region lab berbeda:
#   REGION_1 (default: us-east4)
#   REGION_2 (default: europe-west4)
#   REGION_3 (default: us-central1)

set -euo pipefail

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION_1 "us-east4" "Region 1 untuk subnet pertama (cocokkan dengan Task 1)"
ask REGION_2 "europe-west4" "Region 2 untuk subnet kedua (cocokkan dengan Task 1)"
ask REGION_3 "us-central1" "Region 3 untuk subnet ketiga (cocokkan dengan Task 1)"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Buat custom VPC network 'taw-custom-network' dan 3 subnetwork"

# Buat VPC network kustom jika belum ada
if gcloud compute networks describe taw-custom-network --project="$PROJECT" >/dev/null 2>&1; then
  echo "Network 'taw-custom-network' sudah ada, dilewat."
else
  gcloud compute networks create taw-custom-network \
    --subnet-mode=custom \
    --project="$PROJECT" -q
fi

# Subnet 1
SUBNET_1="subnet-${REGION_1}"
if gcloud compute networks subnets describe "$SUBNET_1" --region="$REGION_1" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Subnet $SUBNET_1 sudah ada, dilewat."
else
  gcloud compute networks subnets create "$SUBNET_1" \
    --network=taw-custom-network \
    --region="$REGION_1" \
    --range=10.0.0.0/16 \
    --project="$PROJECT" -q
fi

# Subnet 2
SUBNET_2="subnet-${REGION_2}"
if gcloud compute networks subnets describe "$SUBNET_2" --region="$REGION_2" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Subnet $SUBNET_2 sudah ada, dilewat."
else
  gcloud compute networks subnets create "$SUBNET_2" \
    --network=taw-custom-network \
    --region="$REGION_2" \
    --range=10.1.0.0/16 \
    --project="$PROJECT" -q
fi

# Subnet 3
SUBNET_3="subnet-${REGION_3}"
if gcloud compute networks subnets describe "$SUBNET_3" --region="$REGION_3" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Subnet $SUBNET_3 sudah ada, dilewat."
else
  gcloud compute networks subnets create "$SUBNET_3" \
    --network=taw-custom-network \
    --region="$REGION_3" \
    --range=10.2.0.0/16 \
    --project="$PROJECT" -q
fi

echo "Daftar subnet di taw-custom-network:"
gcloud compute networks subnets list --network=taw-custom-network --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat firewall rules untuk taw-custom-network"

# 1. HTTP
if gcloud compute firewall-rules describe nw101-allow-http --project="$PROJECT" >/dev/null 2>&1; then
  echo "Firewall rule 'nw101-allow-http' sudah ada, dilewat."
else
  gcloud compute firewall-rules create nw101-allow-http \
    --network=taw-custom-network \
    --allow=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http \
    --project="$PROJECT" -q
fi

# 2. ICMP
if gcloud compute firewall-rules describe nw101-allow-icmp --project="$PROJECT" >/dev/null 2>&1; then
  echo "Firewall rule 'nw101-allow-icmp' sudah ada, dilewat."
else
  gcloud compute firewall-rules create nw101-allow-icmp \
    --network=taw-custom-network \
    --allow=icmp \
    --target-tags=rules \
    --project="$PROJECT" -q
fi

# 3. Internal
if gcloud compute firewall-rules describe nw101-allow-internal --project="$PROJECT" >/dev/null 2>&1; then
  echo "Firewall rule 'nw101-allow-internal' sudah ada, dilewat."
else
  gcloud compute firewall-rules create nw101-allow-internal \
    --network=taw-custom-network \
    --allow=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=10.0.0.0/16,10.1.0.0/16,10.2.0.0/16 \
    --project="$PROJECT" -q
fi

# 4. SSH
if gcloud compute firewall-rules describe nw101-allow-ssh --project="$PROJECT" >/dev/null 2>&1; then
  echo "Firewall rule 'nw101-allow-ssh' sudah ada, dilewat."
else
  gcloud compute firewall-rules create nw101-allow-ssh \
    --network=taw-custom-network \
    --allow=tcp:22 \
    --target-tags=ssh \
    --project="$PROJECT" -q
fi

# 5. RDP
if gcloud compute firewall-rules describe nw101-allow-rdp --project="$PROJECT" >/dev/null 2>&1; then
  echo "Firewall rule 'nw101-allow-rdp' sudah ada, dilewat."
else
  gcloud compute firewall-rules create nw101-allow-rdp \
    --network=taw-custom-network \
    --allow=tcp:3389 \
    --project="$PROJECT" -q
fi

echo "Daftar firewall rules di taw-custom-network:"
gcloud compute firewall-rules list --filter="network:taw-custom-network" --project="$PROJECT"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk kedua task:

  [Task 1] Create a custom network and subnetworks
  [Task 2] Create firewall rules
==============================================================
EOF
