#!/usr/bin/env bash
# ARC120 - The Basics of Google Cloud Compute: Challenge Lab
#
#   bash arc120.sh
#
# Checkpoint:
#   Task 1 - Cloud Storage bucket <PROJECT_ID>-bucket (US multi-region)
#   Task 2 - Instance 'my-instance' + persistent disk 'mydisk' 200GB, di-attach
#   Task 3 - NGINX jalan dan bisa diakses dari luar lewat External IP
#
# NGINX dipasang lewat startup-script waktu instance dibuat, jadi tidak perlu
# SSH sama sekali. Script menunggu sampai http://EXTERNAL_IP benar-benar
# menjawab sebelum menyatakan Task 3 selesai.
#
# LAMA: ~3-5 menit, sebagian besar menunggu boot + apt install nginx.

set -euo pipefail

REGION="${REGION:-europe-west4}"
ZONE="${ZONE:-europe-west4-a}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Nama bucket di soal selalu <PROJECT_ID>-bucket.
BUCKET="gs://${PROJECT}-bucket"
INSTANCE="my-instance"
DISK="mydisk"

echo "Project : $PROJECT"
echo "Region  : $REGION"
echo "Zone    : $ZONE"
echo "Bucket  : $BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable compute.googleapis.com storage.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: Bucket $BUCKET (US multi-region)"
# Soal minta US multi-region, bukan europe-west4 seperti resource lainnya.
gcloud storage buckets describe "$BUCKET" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud storage buckets create "$BUCKET" --location=US --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: Instance $INSTANCE"
# Console "Allow HTTP traffic" = tag http-server + firewall rule default-allow-http.
# Rule-nya tidak selalu ada di project lab, jadi dibuat kalau belum ada.
gcloud compute firewall-rules describe default-allow-http --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud compute firewall-rules create default-allow-http \
    --project="$PROJECT" \
    --network=default \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server

if ! gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute instances create "$INSTANCE" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --boot-disk-type=pd-balanced \
    --boot-disk-size=10GB \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable --now nginx'
else
  echo "Instance sudah ada, dilewati."
fi

step "Task 2: Disk $DISK 200GB + attach"
gcloud compute disks describe "$DISK" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud compute disks create "$DISK" --size=200GB --zone="$ZONE" --project="$PROJECT"

if gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --project="$PROJECT" \
     --format='value(disks[].source)' | grep -q "/$DISK$"; then
  echo "Disk sudah ter-attach, dilewati."
else
  gcloud compute instances attach-disk "$INSTANCE" \
    --disk="$DISK" --zone="$ZONE" --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Tunggu NGINX menjawab"
IP=$(gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --project="$PROJECT" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
echo "External IP: $IP"

# Startup-script baru selesai beberapa puluh detik setelah instance RUNNING.
ok=false
for i in $(seq 1 30); do
  if curl -sf -m 5 "http://$IP/" | grep -q "Welcome to nginx"; then
    ok=true
    break
  fi
  echo "Belum menjawab, tunggu 10 detik (percobaan $i/30)..."
  sleep 10
done

if [[ "$ok" != true ]]; then
  cat <<EOF

NGINX belum menjawab setelah 5 menit. Pasang manual:

  gcloud compute ssh $INSTANCE --zone=$ZONE --project=$PROJECT --quiet \\
    --command='sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl enable --now nginx'

Lalu cek: curl http://$IP/
EOF
  exit 1
fi

cat <<EOF

==============================================================
SELESAI! NGINX menjawab di http://$IP/

Klik Check my progress untuk:
  - Create a Cloud Storage bucket
  - Create and attach a persistent disk to an instance
  - Install a NGINX web server
==============================================================
EOF
