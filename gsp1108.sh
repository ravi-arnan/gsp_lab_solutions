#!/usr/bin/env bash
# GSP1108 - Monitor an Apache Web Server using Ops Agent
#
#   ZONE=us-east4-a bash gsp1108.sh
#
# Checkpoint:
#   Task 1 - Create a Compute Engine VM instance (quickstart-vm)
#   Task 2 - Install an Apache Web Server
#   Task 3 - Install the Ops Agent
#   Task 5 - Create an alerting policy (Apache traffic above threshold)
#   Task 4 & 6 - Generate traffic / lihat dashboard: tanpa checkpoint
#
# Alerting policy dibuat lewat REST API Monitoring. Notification channel
# email TIDAK dibuat — di gsp089 checkpoint tetap hijau tanpa itu, dan lab
# sendiri memperingatkan email akan terus dikirim sampai project dihapus.
#
# LAMA: ~6 menit, paling lama install ops agent + jeda 60 detik.

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

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

DEFAULT_ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="us-east1-c"

ask ZONE "$DEFAULT_ZONE" "Zone (cocokkan dengan panel lab)"
REGION="${REGION:-${ZONE%-*}}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="quickstart-vm"
ALERT_NAME="Apache traffic above threshold"
API="https://monitoring.googleapis.com/v3/projects/$PROJECT"

echo "Project: $PROJECT"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable compute.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com --project="$PROJECT" || echo "Enable API gagal/kena rate limit, lanjut saja."

gcloud config set compute/zone "$ZONE" >/dev/null 2>&1 || true
gcloud config set compute/region "$REGION" >/dev/null 2>&1 || true

# ----------------------------------------------------------------- Task 1
step "Task 1: Create instance '$VM'"
if gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Instance sudah ada, lewati."
else
  gcloud compute instances create "$VM" \
    --zone="$ZONE" \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server,https-server \
    --project="$PROJECT" \
    --quiet
fi

# Checkbox "Allow HTTP/HTTPS traffic" di console = tag + firewall rule.
for rule in "default-allow-http tcp:80 http-server" "default-allow-https tcp:443 https-server"; do
  set -- $rule
  if ! gcloud compute firewall-rules describe "$1" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$1" \
      --allow="$2" --target-tags="$3" --project="$PROJECT" --quiet
  else
    echo "Firewall $1 sudah ada."
  fi
done

EXTERNAL_IP="$(gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "External IP: $EXTERNAL_IP"

# ----------------------------------------------------------------- Task 2-4
step "Task 2-4: Apache + Ops Agent + generate traffic"
if gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
    --command="systemctl is-active google-cloud-ops-agent" 2>/dev/null | grep -q "active"; then
  echo "Ops Agent sudah terpasang dan aktif di VM $VM, melewati Task 2-4."
else
  REMOTE=/tmp/gsp1108_remote.sh
  cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "== Task 2: Apache2 =="
sudo apt-get update -qq
# Debian 12 tidak punya php7.0; instruksi lab sudah memberi jalan keluar 'php'.
sudo apt-get install -y -qq apache2 php
sudo service apache2 restart
curl -s -o /dev/null -w "  apache lokal: HTTP %{http_code}\n" http://localhost/

echo
echo "== Task 3: Ops Agent =="
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

sudo cp /etc/google-cloud-ops-agent/config.yaml /etc/google-cloud-ops-agent/config.yaml.bak
sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null << 'EOF'
metrics:
  receivers:
    apache:
      type: apache
  service:
    pipelines:
      apache:
        receivers:
          - apache
logging:
  receivers:
    apache_access:
      type: apache_access
    apache_error:
      type: apache_error
  service:
    pipelines:
      apache:
        receivers:
          - apache_access
          - apache_error
EOF

sudo service google-cloud-ops-agent restart
sleep 60
sudo systemctl status google-cloud-ops-agent"*" --no-pager | head -15 || true

echo
echo "== Task 4: Generate traffic (120 detik) =="
timeout 120 bash -c -- 'while true; do curl -s -o /dev/null localhost; sleep $((RANDOM % 4)); done' || true
echo "  selesai."
exit 0
REMOTE_EOF

  n=1
  until gcloud compute scp "$REMOTE" "$VM":~/gsp1108_remote.sh \
          --zone="$ZONE" --project="$PROJECT" --quiet; do
    (( n++ >= 8 )) && { echo "SSH tidak siap setelah 7 percobaan."; exit 1; }
    echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
    sleep 15
  done

  gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
    --command="bash ~/gsp1108_remote.sh" || echo "Peringatan: SSH selesai, lanjut ke Task 5."
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Alerting policy '$ALERT_NAME'"
TOKEN="$(gcloud auth print-access-token)"

STUDENT_EMAIL="$(gcloud config get-value account 2>/dev/null || echo 'student@example.com')"
echo "Menyiapkan notification channel untuk $STUDENT_EMAIL..."
CHANNEL_NAME=""
CHANNEL_RESP="$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"email\",\"displayName\":\"Lab Alert Email\",\"labels\":{\"email_address\":\"$STUDENT_EMAIL\"}}" \
  "$API/notificationChannels" || true)"
CHANNEL_NAME="$(echo "$CHANNEL_RESP" | grep -o '"name": "[^"]*"' | head -1 | cut -d'"' -f4 || true)"

CHANNELS_JSON="[]"
if [[ -n "$CHANNEL_NAME" ]]; then
  echo "Notification channel dibuat: $CHANNEL_NAME"
  CHANNELS_JSON="[\"$CHANNEL_NAME\"]"
fi

if curl -s -H "Authorization: Bearer $TOKEN" "$API/alertPolicies" | grep -q "$ALERT_NAME"; then
  echo "Alerting policy '$ALERT_NAME' sudah ada, lewati."
else
  cat > /tmp/gsp1108_alert.json << EOF
{
  "displayName": "$ALERT_NAME",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "VM Instance - Apache traffic",
      "conditionThreshold": {
        "filter": "metric.type=\"workload.googleapis.com/apache.traffic\" AND resource.type=\"gce_instance\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 4000,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": $CHANNELS_JSON,
  "enabled": true
}
EOF
  CREATE_RESP="$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/gsp1108_alert.json "$API/alertPolicies")"
  echo "Respon pembuatan alert policy:"
  echo "$CREATE_RESP" | head -n 20
fi

step "Verifikasi"
curl -s -H "Authorization: Bearer $TOKEN" "$API/alertPolicies" \
  | grep -o '"displayName": "[^"]*"' || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 1, 2, 3, dan 5.

  Apache : http://$EXTERNAL_IP/
  Alert  : $ALERT_NAME

Task 4 & 6 tanpa checkpoint. Kalau mau lihat dashboard:
  Monitoring > Dashboards > Apache Overview
Untuk kirim trafik lagi:
  gcloud compute ssh $VM --zone=$ZONE --command \\
    "timeout 120 bash -c -- 'while true; do curl -s -o /dev/null localhost; sleep \\\$((RANDOM % 4)); done'"
==============================================================
EOF
