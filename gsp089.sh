#!/usr/bin/env bash
# GSP089 - Cloud Monitoring: Qwik Start
#
#   ZONE=europe-west3-a bash gsp089.sh
#
# Checkpoint:
#   Task 1 - Create a Compute Engine instance (lamp-1-vm)
#   Task 2 - Add Apache2 HTTP Server to your instance
#   Task 3 - Get a success response over External IP of VM instance
#   Task 4 - Create an uptime check and alerting policy
#   Task 5-7 - Dashboard, log, cek incident: tanpa checkpoint, manual
#
# Uptime check dan alerting policy dibuat lewat REST API Monitoring
# (gcloud auth print-access-token + curl), bukan console.
#
# LAMA: ~5 menit, paling lama install ops agent di VM.

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
#   ask <NAMA_VAR> <default> <pertanyaan>
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

ask ZONE "europe-west3-a" "Zone (cocokkan dengan panel lab)"
REGION="${REGION:-${ZONE%-*}}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="lamp-1-vm"
UPTIME_NAME="Lamp Uptime Check"
ALERT_NAME="Inbound Traffic Alert"
API="https://monitoring.googleapis.com/v3/projects/$PROJECT"

echo "Project: $PROJECT"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable compute.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com --project="$PROJECT"

gcloud config set compute/zone "$ZONE" >/dev/null 2>&1 || true
gcloud config set compute/region "$REGION" >/dev/null 2>&1 || true

# ----------------------------------------------------------------- Task 1
step "Task 1: Create instance '$VM'"
if gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Instance sudah ada, lewati."
else
  gcloud compute instances create "$VM" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --project="$PROJECT"
fi

# Firewall "Allow HTTP traffic" (checkbox di console = tag http-server).
if ! gcloud compute firewall-rules describe default-allow-http --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules create default-allow-http \
    --allow=tcp:80 --target-tags=http-server \
    --description="Allow HTTP traffic" --project="$PROJECT"
else
  echo "Firewall default-allow-http sudah ada."
fi

EXTERNAL_IP="$(gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
[[ -n "$EXTERNAL_IP" ]] || { echo "External IP tidak ketemu."; exit 1; }
echo "External IP: $EXTERNAL_IP"

# ----------------------------------------------------------------- Task 2
step "Task 2: Install Apache2 + PHP + ops agent di $VM"
REMOTE=/tmp/gsp089_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -qq
# Debian 12 tidak punya php7.0; paket 'php' menarik versi default (8.2).
sudo apt-get install -y -qq apache2 php
sudo service apache2 restart

# Ops agent: sumber metrik agent.googleapis.com yang dipakai alerting policy.
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
sudo systemctl status google-cloud-ops-agent"*" --no-pager | head -20 || true

echo "Apache lokal:"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost/
REMOTE_EOF

n=1
until gcloud compute scp "$REMOTE" "$VM":~/gsp089_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 8 )) && { echo "SSH tidak siap setelah 7 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/gsp089_remote.sh"

# ----------------------------------------------------------------- Task 3
step "Task 3: Akses Apache lewat External IP"
for i in $(seq 1 10); do
  CODE="$(curl -s -o /dev/null -m 20 -w '%{http_code}' "http://$EXTERNAL_IP/" || true)"
  echo "  percobaan $i: HTTP $CODE"
  [[ "$CODE" == "200" ]] && break
  sleep 10
done
[[ "$CODE" == "200" ]] || echo "PERINGATAN: belum dapat 200. Cek firewall/apache."

# ----------------------------------------------------------------- Task 4
step "Task 4: Uptime check + alerting policy (REST API)"
TOKEN="$(gcloud auth print-access-token)"
api_post() {  # $1 = path, $2 = file body
  curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" --data-binary @"$2" "$API/$1"
}
api_get() {   # $1 = path
  curl -s -H "Authorization: Bearer $TOKEN" "$API/$1"
}

# --- uptime check
if api_get uptimeCheckConfigs | grep -q "$UPTIME_NAME"; then
  echo "Uptime check '$UPTIME_NAME' sudah ada, lewati."
else
  cat > /tmp/gsp089_uptime.json << EOF
{
  "displayName": "$UPTIME_NAME",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": { "host": "$EXTERNAL_IP" }
  },
  "httpCheck": { "path": "/", "port": 80, "requestMethod": "GET" },
  "period": "60s",
  "timeout": "10s"
}
EOF
  api_post uptimeCheckConfigs /tmp/gsp089_uptime.json | head -c 400; echo
fi

# --- alerting policy
if api_get alertPolicies | grep -q "$ALERT_NAME"; then
  echo "Alerting policy '$ALERT_NAME' sudah ada, lewati."
else
  cat > /tmp/gsp089_alert.json << EOF
{
  "displayName": "$ALERT_NAME",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "VM Instance - Network traffic",
      "conditionThreshold": {
        "filter": "metric.type=\"agent.googleapis.com/interface/traffic\" AND resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 500,
        "duration": "60s",
        "trigger": { "count": 1 },
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_NONE"
          }
        ]
      }
    }
  ],
  "documentation": {
    "content": "Inbound traffic melebihi ambang 500.",
    "mimeType": "text/markdown"
  },
  "enabled": true
}
EOF
  api_post alertPolicies /tmp/gsp089_alert.json | head -c 400; echo
fi

step "Verifikasi"
api_get uptimeCheckConfigs | grep -o '"displayName": "[^"]*"' || true
api_get alertPolicies | grep -o '"displayName": "[^"]*"' || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 1-4.

  External IP : http://$EXTERNAL_IP/
  Uptime check: $UPTIME_NAME
  Alert policy: $ALERT_NAME

Task 5-7 tanpa checkpoint (opsional, lewat console):
  - Dashboard "Cloud Monitoring LAMP Qwik Start Dashboard"
    dengan chart CPU load (1m) dan Received packets
  - Logs Explorer, filter VM Instance > $VM
  - Monitoring > Uptime checks untuk lihat status per region
==============================================================
EOF
