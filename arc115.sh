#!/usr/bin/env bash
# ARC115 - Monitoring in Google Cloud: Challenge Lab
#
#   bash arc115.sh
#
# Checkpoint:
#   Task 1 - Install Ops Agent (logging + monitoring) di apache-vm
#   Task 2 - Uptime check (resource type URL, External IP VM)
#   Task 3 - Alert policy Apache traffic > 3 KiB/s
#   Task 4 - Dashboard: chart CPU load (1m) + Apache Requests
#   Task 5 - Log-based metric (logName apache-access, textPayload "200")
#
# VM 'apache-vm' sudah disiapkan lab, zone-nya dicari otomatis.
# Notification channel email tidak dibuat — terbukti tidak diperlukan di
# gsp089/gsp1108, dan lab menyuruh menghapusnya lagi di akhir.
#
# LAMA: ~5 menit, paling lama install ops agent + generate traffic.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-apache-vm}"
UPTIME_NAME="Apache Uptime Check"
ALERT_NAME="Apache traffic above threshold"
DASHBOARD_NAME="Apache Dashboard"
LOG_METRIC="apache-access-200"
API="https://monitoring.googleapis.com/v3/projects/$PROJECT"
API_V1="https://monitoring.googleapis.com/v1/projects/$PROJECT"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable monitoring.googleapis.com logging.googleapis.com \
  compute.googleapis.com --project="$PROJECT"

step "Cari $VM"
ZONE="$(gcloud compute instances list --filter="name=$VM" \
  --format='value(zone)' --project="$PROJECT" | head -1)"
[[ -n "$ZONE" ]] || { echo "Instance $VM tidak ditemukan."; exit 1; }
EXTERNAL_IP="$(gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "Zone: $ZONE  External IP: $EXTERNAL_IP"

# ----------------------------------------------------------------- Task 1
step "Task 1: Install + konfigurasi Ops Agent, lalu kirim trafik"
REMOTE=/tmp/arc115_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
set -uo pipefail

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
echo "== Generate traffic (120 detik) =="
timeout 120 bash -c -- 'while true; do curl -s localhost | grep -oP "<title>.*</title>"; sleep .1s; done' || true
echo "  selesai."
REMOTE_EOF

n=1
until gcloud compute scp "$REMOTE" "$VM":~/arc115_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 8 )) && { echo "SSH tidak siap setelah 7 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/arc115_remote.sh"

# ----------------------------------------------------------------- REST helper
TOKEN="$(gcloud auth print-access-token)"
api_post() { curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" --data-binary @"$2" "$1"; }
api_get()  { curl -s -H "Authorization: Bearer $TOKEN" "$1"; }

# ----------------------------------------------------------------- Task 2
step "Task 2: Uptime check '$UPTIME_NAME'"
if api_get "$API/uptimeCheckConfigs" | grep -q "$UPTIME_NAME"; then
  echo "Uptime check sudah ada, lewati."
else
  cat > /tmp/arc115_uptime.json << EOF
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
  api_post "$API/uptimeCheckConfigs" /tmp/arc115_uptime.json | head -c 300; echo
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Alert policy '$ALERT_NAME' (> 3 KiB/s)"
if api_get "$API/alertPolicies" | grep -q "$ALERT_NAME"; then
  echo "Alert policy sudah ada, lewati."
else
  cat > /tmp/arc115_alert.json << 'EOF'
{
  "displayName": "Apache traffic above threshold",
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
        "thresholdValue": 3000,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "enabled": true
}
EOF
  api_post "$API/alertPolicies" /tmp/arc115_alert.json | head -c 300; echo
fi

# ----------------------------------------------------------------- Task 4
step "Task 4: Dashboard '$DASHBOARD_NAME' (CPU load 1m + Apache Requests)"
if api_get "$API_V1/dashboards" | grep -q "$DASHBOARD_NAME"; then
  echo "Dashboard sudah ada, lewati."
else
  cat > /tmp/arc115_dashboard.json << 'EOF'
{
  "displayName": "Apache Dashboard",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6, "height": 4,
        "widget": {
          "title": "CPU load (1m)",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"agent.googleapis.com/cpu/load_1m\" AND resource.type=\"gce_instance\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      },
      {
        "xPos": 6, "width": 6, "height": 4,
        "widget": {
          "title": "Apache Requests",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"workload.googleapis.com/apache.requests\" AND resource.type=\"gce_instance\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
  api_post "$API_V1/dashboards" /tmp/arc115_dashboard.json | head -c 300; echo
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Log-based metric '$LOG_METRIC'"
if gcloud logging metrics describe "$LOG_METRIC" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Log-based metric sudah ada, lewati."
else
  gcloud logging metrics create "$LOG_METRIC" \
    --description="Apache access log dengan status 200" \
    --log-filter="resource.type=\"gce_instance\" AND logName=\"projects/$PROJECT/logs/apache-access\" AND textPayload:\"200\"" \
    --project="$PROJECT"
fi

step "Verifikasi"
api_get "$API/uptimeCheckConfigs" | grep -o '"displayName": "[^"]*"' || true
api_get "$API/alertPolicies"      | grep -o '"displayName": "[^"]*"' || true
api_get "$API_V1/dashboards"      | grep -o '"displayName": "[^"]*"' || true
gcloud logging metrics list --project="$PROJECT" --format="table(name, filter)" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 1-5.

  Apache    : http://$EXTERNAL_IP/
  Uptime    : $UPTIME_NAME
  Alert     : $ALERT_NAME
  Dashboard : $DASHBOARD_NAME
  Metric    : $LOG_METRIC

Kalau perlu kirim trafik lagi:
  gcloud compute ssh $VM --zone=$ZONE --command \\
    "timeout 120 bash -c -- 'while true; do curl -s localhost >/dev/null; sleep .1s; done'"
==============================================================
EOF
