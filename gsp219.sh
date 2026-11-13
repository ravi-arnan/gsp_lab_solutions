#!/usr/bin/env bash
# GSP219 - Network Tiers - Optimizing Network Spend
#
#   bash gsp219.sh
#
# Checkpoint:
#   Task 1 (100 pts) - Create the VM instances (vm-premium & vm-standard)
#
# Task 2 adalah uji latency & traceroute manual via web eksternal (tidak dinilai).
#
# LAMA: < 1 menit.

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

DEF_ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
ask ZONE "${DEF_ZONE:-us-east1-c}" "Zone VM (cocokkan dengan panel lab)"
REGION="${ZONE%-*}"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

instance_exists() {
  gcloud compute instances describe "$1" --zone="$ZONE" >/dev/null 2>&1
}

# ================================================================= Task 1
step "Task 1: buat VM vm-premium (Tier Premium) dan vm-standard (Tier Standard)"

gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

PIDS=()

if instance_exists vm-premium; then
  echo "Instance vm-premium sudah ada, lewati pembuatan."
else
  echo "Membuat vm-premium (network-tier=PREMIUM)..."
  gcloud compute instances create vm-premium \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --network-tier=PREMIUM -q &
  PIDS+=($!)
fi

if instance_exists vm-standard; then
  echo "Instance vm-standard sudah ada, lewati pembuatan."
else
  echo "Membuat vm-standard (network-tier=STANDARD)..."
  gcloud compute instances create vm-standard \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --network-tier=STANDARD -q &
  PIDS+=($!)
fi

# Tunggu pembuatan VM selesai secara paralel
if [[ ${#PIDS[@]} -gt 0 ]]; then
  echo "Menunggu deployment VM selesai..."
  for pid in "${PIDS[@]}"; do
    wait "$pid"
  done
fi

# Memastikan firewall allow-icmp tersedia untuk keperluan eksplorasi Task 2
if ! gcloud compute firewall-rules describe default-allow-icmp >/dev/null 2>&1; then
  gcloud compute firewall-rules create default-allow-icmp \
    --direction=INGRESS \
    --priority=65534 \
    --network=default \
    --action=ALLOW \
    --rules=icmp \
    --source-ranges=0.0.0.0/0 >/dev/null 2>&1 || true
fi

PREMIUM_IP="$(gcloud compute instances describe vm-premium --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo '-')"
STANDARD_IP="$(gcloud compute instances describe vm-standard --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo '-')"

cat <<EOF

==============================================================
Detail VM yang telah dibuat:
  vm-premium  (Tier: PREMIUM)  -> IP: $PREMIUM_IP
  vm-standard (Tier: STANDARD) -> IP: $STANDARD_IP
==============================================================

SELESAI! Klik Check my progress untuk verifikasi:
  - Create the VM instances (Task 1)

Jawaban kuis pemahaman materi (Task 2):
  1. Which Network Service Tier should provide lower latency?
     -> Premium Tier
  2. Which Network Service Tier should have fewer hops on the public internet?
     -> Premium Tier
EOF
