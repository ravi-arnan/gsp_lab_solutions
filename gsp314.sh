#!/usr/bin/env bash
# GSP314 - Set Up a Google Cloud Network: Challenge Lab
#
#   bash gsp314.sh
#
# Checkpoint:
#   Task 1 (30 pts)  - Create networks (VPC + 2 subnets)
#   Task 2 (30 pts)  - Add firewall rules (SSH, RDP, ICMP)
#   Task 3 (40 pts)  - Add VMs to your network + verify connectivity

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

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

step() {
  echo
  echo "=== $1 ==="
}

ask REGION_A "us-central1" "Region untuk subnet-a (cocokkan dengan panel lab)"
ask REGION_B "us-west1" "Region untuk subnet-b (cocokkan dengan panel lab)"
ask ZONE_A "us-central1-a" "Zone untuk us-test-01"
ask ZONE_B "us-west1-c" "Zone untuk us-test-02"

VPC_NAME="vpc-network-oqns"
SUBNET_A="subnet-a-kd5x"
SUBNET_B="subnet-b-3bzq"
SUBNET_A_RANGE="10.10.10.0/24"
SUBNET_B_RANGE="10.10.20.0/24"
VM_A="us-test-01"
VM_B="us-test-02"
MACHINE_TYPE="e2-standard-2"

step "Task 1: Create VPC network and subnets"

if gcloud compute networks describe "$VPC_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VPC $VPC_NAME sudah ada, lewati create"
else
  gcloud compute networks create "$VPC_NAME" \
    --project="$PROJECT_ID" \
    --subnet-mode=custom \
    --bgp-routing-mode=regional \
    --mtu=1460
  echo "VPC $VPC_NAME dibuat"
fi

if gcloud compute networks subnets describe "$SUBNET_A" --region="$REGION_A" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subnet $SUBNET_A sudah ada, lewati create"
else
  gcloud compute networks subnets create "$SUBNET_A" \
    --project="$PROJECT_ID" \
    --network="$VPC_NAME" \
    --region="$REGION_A" \
    --range="$SUBNET_A_RANGE" \
    --stack-type=IPV4_ONLY
  echo "Subnet $SUBNET_A dibuat"
fi

if gcloud compute networks subnets describe "$SUBNET_B" --region="$REGION_B" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subnet $SUBNET_B sudah ada, lewati create"
else
  gcloud compute networks subnets create "$SUBNET_B" \
    --project="$PROJECT_ID" \
    --network="$VPC_NAME" \
    --region="$REGION_B" \
    --range="$SUBNET_B_RANGE" \
    --stack-type=IPV4_ONLY
  echo "Subnet $SUBNET_B dibuat"
fi

step "Task 2: Create firewall rules"

FW_SSH="dvce-firewall-ssh"
FW_RDP="qorf-firewall-rdp"
FW_ICMP="pctx-firewall-icmp"

if gcloud compute firewall-rules describe "$FW_SSH" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall $FW_SSH sudah ada, lewati create"
else
  gcloud compute firewall-rules create "$FW_SSH" \
    --project="$PROJECT_ID" \
    --network="$VPC_NAME" \
    --priority=1000 \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0
  echo "Firewall $FW_SSH dibuat"
fi

if gcloud compute firewall-rules describe "$FW_RDP" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall $FW_RDP sudah ada, lewati create"
else
  gcloud compute firewall-rules create "$FW_RDP" \
    --project="$PROJECT_ID" \
    --network="$VPC_NAME" \
    --priority=65535 \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges=0.0.0.0/0
  echo "Firewall $FW_RDP dibuat"
fi

if gcloud compute firewall-rules describe "$FW_ICMP" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall $FW_ICMP sudah ada, lewati create"
else
  gcloud compute firewall-rules create "$FW_ICMP" \
    --project="$PROJECT_ID" \
    --network="$VPC_NAME" \
    --priority=1000 \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=icmp \
    --source-ranges="$SUBNET_A_RANGE,$SUBNET_B_RANGE"
  echo "Firewall $FW_ICMP dibuat"
fi

step "Task 3: Create VM instances"

if gcloud compute instances describe "$VM_A" --zone="$ZONE_A" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM $VM_A sudah ada, lewati create"
else
  gcloud compute instances create "$VM_A" \
    --project="$PROJECT_ID" \
    --zone="$ZONE_A" \
    --machine-type="$MACHINE_TYPE" \
    --network-interface="network=$VPC_NAME,subnet=$SUBNET_A" \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name="$VM_A"
  echo "VM $VM_A dibuat"
fi

if gcloud compute instances describe "$VM_B" --zone="$ZONE_B" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM $VM_B sudah ada, lewati create"
else
  gcloud compute instances create "$VM_B" \
    --project="$PROJECT_ID" \
    --zone="$ZONE_B" \
    --machine-type="$MACHINE_TYPE" \
    --network-interface="network=$VPC_NAME,subnet=$SUBNET_B" \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name="$VM_B"
  echo "VM $VM_B dibuat"
fi

step "Verifikasi konektivitas (manual)"
echo "VMs dibuat. Untuk test konektivitas:"
echo "1. Buka Cloud Console > Compute Engine > VM instances"
echo "2. Klik SSH pada $VM_A"
echo "3. Di terminal SSH, jalankan:"
echo "   ping -c 3 <internal-ip-$VM_B>"
echo "   ping -c 3 $VM_B.$ZONE_B"
echo ""
echo "Internal IP $VM_B:"
gcloud compute instances describe "$VM_B" --zone="$ZONE_B" --project="$PROJECT_ID" --format='value(networkInterfaces[0].networkIP)'

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create networks"
echo "  Task 2 - Add firewall rules"
echo "  Task 3 - Add VMs to your network"