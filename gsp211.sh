#!/usr/bin/env bash
# GSP211 - Create and Configure Multiple VPC Networks
#
#   bash gsp211.sh
#
# Checkpoint:
#   Task 1 - Create the managementnet network
#   Task 1 - Create the privatenet network
#   Task 1 - Create the firewall rules for managementnet
#   Task 1 - Create the firewall rules for privatenet
#   Task 2 - Create the managementnet-vm-1 instance
#   Task 2 - Create the privatenet-vm-1 instance
#   Task 4 - Create a VM instance with multiple network interfaces
#
# Task 3 dan eksperimen konektivitas di Task 4 adalah latihan interaktif (tanpa checkpoint).
#
# LAMA: ~ 2-3 menit.

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set di env var
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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Deteksi region dan zone default dari VM bawaan lab (mynet-vm-1 dan mynet-vm-2)
ZONE_1_DEFAULT="$(gcloud compute instances list --filter="name=mynet-vm-1" --format="value(zone)" --project="$PROJECT_ID" 2>/dev/null | head -n1 || true)"
if [[ -z "$ZONE_1_DEFAULT" ]]; then
  ZONE_1_DEFAULT="us-central1-f"
fi

REGION_1_DEFAULT="$(echo "$ZONE_1_DEFAULT" | sed 's/-[a-z]$//')"
if [[ -z "$REGION_1_DEFAULT" ]]; then
  REGION_1_DEFAULT="us-central1"
fi

ZONE_2_DEFAULT="$(gcloud compute instances list --filter="name=mynet-vm-2" --format="value(zone)" --project="$PROJECT_ID" 2>/dev/null | head -n1 || true)"
REGION_2_DEFAULT="$(echo "$ZONE_2_DEFAULT" | sed 's/-[a-z]$//')"
if [[ -z "$REGION_2_DEFAULT" ]]; then
  REGION_2_DEFAULT="asia-east1"
fi

ask REGION_1 "$REGION_1_DEFAULT" "Region 1 (managementsubnet-1 & privatesubnet-1)"
ask ZONE_1 "$ZONE_1_DEFAULT" "Zone 1 (VM instances)"
ask REGION_2 "$REGION_2_DEFAULT" "Region 2 (privatesubnet-2)"

echo "Project ID: $PROJECT_ID"
echo "Region 1  : $REGION_1"
echo "Zone 1    : $ZONE_1"
echo "Region 2  : $REGION_2"

# ----------------------------------------------------------------- Task 1
step "Task 1.1: Buat VPC network managementnet dan subnet managementsubnet-1"
if gcloud compute networks describe managementnet --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VPC managementnet sudah ada, lewati."
else
  gcloud compute networks create managementnet \
    --subnet-mode=custom \
    --project="$PROJECT_ID" \
    --quiet
  echo "VPC managementnet berhasil dibuat."
fi

if gcloud compute networks subnets describe managementsubnet-1 --region="$REGION_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subnet managementsubnet-1 sudah ada, lewati."
else
  gcloud compute networks subnets create managementsubnet-1 \
    --network=managementnet \
    --region="$REGION_1" \
    --range=10.130.0.0/20 \
    --project="$PROJECT_ID" \
    --quiet
  echo "Subnet managementsubnet-1 berhasil dibuat."
fi

step "Task 1.2: Buat VPC network privatenet dan subnet (privatesubnet-1 & privatesubnet-2)"
if gcloud compute networks describe privatenet --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VPC privatenet sudah ada, lewati."
else
  gcloud compute networks create privatenet \
    --subnet-mode=custom \
    --project="$PROJECT_ID" \
    --quiet
  echo "VPC privatenet berhasil dibuat."
fi

if gcloud compute networks subnets describe privatesubnet-1 --region="$REGION_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subnet privatesubnet-1 sudah ada, lewati."
else
  gcloud compute networks subnets create privatesubnet-1 \
    --network=privatenet \
    --region="$REGION_1" \
    --range=172.16.0.0/24 \
    --project="$PROJECT_ID" \
    --quiet
  echo "Subnet privatesubnet-1 berhasil dibuat."
fi

if gcloud compute networks subnets describe privatesubnet-2 --region="$REGION_2" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subnet privatesubnet-2 sudah ada, lewati."
else
  gcloud compute networks subnets create privatesubnet-2 \
    --network=privatenet \
    --region="$REGION_2" \
    --range=172.20.0.0/20 \
    --project="$PROJECT_ID" \
    --quiet
  echo "Subnet privatesubnet-2 berhasil dibuat."
fi

step "Task 1.3: Buat firewall rule untuk managementnet"
if gcloud compute firewall-rules describe managementnet-allow-icmp-ssh-rdp --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall rule managementnet-allow-icmp-ssh-rdp sudah ada, lewati."
else
  gcloud compute firewall-rules create managementnet-allow-icmp-ssh-rdp \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=managementnet \
    --action=ALLOW \
    --rules=icmp,tcp:22,tcp:3389 \
    --source-ranges=0.0.0.0/0 \
    --quiet
  echo "Firewall rule managementnet-allow-icmp-ssh-rdp berhasil dibuat."
fi

step "Task 1.4: Buat firewall rule untuk privatenet"
if gcloud compute firewall-rules describe privatenet-allow-icmp-ssh-rdp --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall rule privatenet-allow-icmp-ssh-rdp sudah ada, lewati."
else
  gcloud compute firewall-rules create privatenet-allow-icmp-ssh-rdp \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=privatenet \
    --action=ALLOW \
    --rules=icmp,tcp:22,tcp:3389 \
    --source-ranges=0.0.0.0/0 \
    --quiet
  echo "Firewall rule privatenet-allow-icmp-ssh-rdp berhasil dibuat."
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat VM instances (managementnet-vm-1 dan privatenet-vm-1)"
if gcloud compute instances describe managementnet-vm-1 --zone="$ZONE_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM managementnet-vm-1 sudah ada, lewati."
else
  gcloud compute instances create managementnet-vm-1 \
    --project="$PROJECT_ID" \
    --zone="$ZONE_1" \
    --machine-type=e2-micro \
    --subnet=managementsubnet-1 \
    --quiet
  echo "VM managementnet-vm-1 berhasil dibuat."
fi

if gcloud compute instances describe privatenet-vm-1 --zone="$ZONE_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM privatenet-vm-1 sudah ada, lewati."
else
  gcloud compute instances create privatenet-vm-1 \
    --project="$PROJECT_ID" \
    --zone="$ZONE_1" \
    --machine-type=e2-micro \
    --subnet=privatesubnet-1 \
    --quiet
  echo "VM privatenet-vm-1 berhasil dibuat."
fi

# ----------------------------------------------------------------- Task 4
step "Task 4: Buat VM instance multi-NIC (vm-appliance)"
if gcloud compute instances describe vm-appliance --zone="$ZONE_1" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VM vm-appliance sudah ada, lewati."
else
  gcloud compute instances create vm-appliance \
    --project="$PROJECT_ID" \
    --zone="$ZONE_1" \
    --machine-type=e2-standard-4 \
    --network-interface=network=privatenet,subnet=privatesubnet-1 \
    --network-interface=network=managementnet,subnet=managementsubnet-1 \
    --network-interface=network=mynetwork,subnet=mynetwork \
    --quiet
  echo "VM vm-appliance berhasil dibuat."
fi

# ----------------------------------------------------------------- Verifikasi & Ringkasan
step "Ringkasan Resource"
echo "--- VPC Networks ---"
gcloud compute networks list --project="$PROJECT_ID"
echo
echo "--- Subnets (sorted by network) ---"
gcloud compute networks subnets list --project="$PROJECT_ID" --sort-by=NETWORK
echo
echo "--- VM Instances ---"
gcloud compute instances list --project="$PROJECT_ID" --sort-by=ZONE

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh checkpoint:

  Task 1:
  - Create the managementnet network
  - Create the privatenet network
  - Create the firewall rules for managementnet
  - Create the firewall rules for privatenet

  Task 2:
  - Create the managementnet-vm-1 instance
  - Create the privatenet-vm-1 instance

  Task 4:
  - Create a VM instance with multiple network interfaces

Semua checkpoint selesai dieksekusi secara otomatis.
Untuk eksplorasi interaktif konektivitas (Task 3 & 4),
dapat dicoba via SSH untuk membuktikan isolasi jaringan VPC
dan default route pada multi-NIC VM.
==============================================================
EOF
