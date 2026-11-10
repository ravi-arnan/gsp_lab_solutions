#!/usr/bin/env bash
# GSP694 - gcloud for Network Configuration
#
#   bash gsp694.sh
#
# Checkpoint:
#   Task 4 - Add firewall rules to allow tcp:22 and ICMP
#   Task 6 - Create deny firewall rules

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

# Deteksi zona otomatis dari VM yang sudah ada
DETECTED_ZONE="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=(lnet-vm OR pnet-vm)" --format="value(zone)" 2>/dev/null | head -n1 || true)"
[[ -z "$DETECTED_ZONE" ]] && DETECTED_ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
[[ -z "$DETECTED_ZONE" ]] && DETECTED_ZONE="europe-west4-a"

ask ZONE "$DETECTED_ZONE" "Zone (cocokkan dengan panel lab)"
REGION="${ZONE%-*}"

echo "Project ID : $PROJECT_ID"
echo "Zone       : $ZONE"
echo "Region     : $REGION"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1-3: Inspeksi Jaringan & Subnet
step "Task 1-3: Inspeksi VPC Networks & Subnets"

echo "Daftar VPC Networks:"
gcloud compute networks list --project="$PROJECT_ID"

echo
echo "Daftar Subnets:"
gcloud compute networks subnets list --project="$PROJECT_ID" --filter="network:(labnet OR privatenet)" || true

# ----------------------------------------------------------------- Task 4-5: Firewall Rule labnet-allow-internal (Checkpoint 1)
step "Task 4: Buat Firewall Rule labnet-allow-internal (Checkpoint 1)"

if gcloud compute firewall-rules describe labnet-allow-internal --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall rule labnet-allow-internal sudah ada di network labnet."
else
  echo "Membuat firewall rule labnet-allow-internal (ALLOW icmp,tcp:22)..."
  gcloud compute firewall-rules create labnet-allow-internal \
    --network=labnet \
    --action=ALLOW \
    --rules=icmp,tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --project="$PROJECT_ID" \
    --quiet
fi

echo
echo "Detail firewall rule labnet-allow-internal:"
gcloud compute firewall-rules describe labnet-allow-internal --project="$PROJECT_ID" --format="table(name,network,action,allowed,sourceRanges)"

# ----------------------------------------------------------------- Task 6: Firewall Rule privatenet-deny (Checkpoint 2)
step "Task 6: Buat Firewall Rule privatenet-deny (Checkpoint 2)"

if gcloud compute firewall-rules describe privatenet-deny --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall rule privatenet-deny sudah ada di network privatenet."
else
  echo "Membuat firewall rule privatenet-deny (DENY icmp,tcp:22)..."
  gcloud compute firewall-rules create privatenet-deny \
    --network=privatenet \
    --action=DENY \
    --rules=icmp,tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --project="$PROJECT_ID" \
    --quiet
fi

echo
echo "Detail firewall rule privatenet-deny:"
gcloud compute firewall-rules describe privatenet-deny --project="$PROJECT_ID" --format="table(name,network,action,denied,sourceRanges)"

# ----------------------------------------------------------------- Task 7-8: Verifikasi VM & Uji Konektivitas Ping
step "Task 7-8: Verifikasi VM Instances & Pengujian Konektivitas"

echo "Daftar VM Instances:"
gcloud compute instances list --project="$PROJECT_ID"

LNET_IP="$(gcloud compute instances describe lnet-vm --zone="$ZONE" --project="$PROJECT_ID" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || gcloud compute instances list --project="$PROJECT_ID" --filter="name=lnet-vm" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null | head -n1 || true)"
PNET_IP="$(gcloud compute instances describe pnet-vm --zone="$ZONE" --project="$PROJECT_ID" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || gcloud compute instances list --project="$PROJECT_ID" --filter="name=pnet-vm" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null | head -n1 || true)"

if [[ -n "$LNET_IP" ]]; then
  echo
  echo "Menguji ping ke lnet-vm ($LNET_IP) - seharusnya berhasil..."
  ping -c 3 "$LNET_IP" || echo "Catatan: Ping dari Cloud Shell mungkin dibatasi, rule firewall sudah aktif."
fi

if [[ -n "$PNET_IP" ]]; then
  echo
  echo "Menguji ping ke pnet-vm ($PNET_IP) - seharusnya di-drop..."
  timeout 3 ping -c 2 "$PNET_IP" || echo "Ping ke pnet-vm di-drop (sesuai ekspektasi DENY rule)."
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Add firewall rules to allow tcp:22 and ICMP (Task 4)
  2. Create deny firewall rules (Task 6)
==============================================================
EOF
