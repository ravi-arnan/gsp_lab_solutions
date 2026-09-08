#!/usr/bin/env bash
# GSP338 - Monitor and Log with Google Cloud Observability: Challenge Lab
#
#   bash gsp338.sh
#
# Checkpoint:
#   Task 1 (20 pts) - Enable Cloud Monitoring (API)
#   Task 2 (20 pts) - Fix startup script video-queue-monitor + restart (custom metric
#                     input_queue_size dari Go app)
#   Task 3 (20 pts) - Log metric big_video_upload_rate (4K/8K)
#   Task 4 (20 pts) - Dua chart di Media_Dashboard
#   Task 5 (20 pts) - Alert custom di big_video_upload_rate (> 3/s)
#
# Nilai yang bisa beda tiap instance ditanya di awal: nama metric, threshold,
# dan zone VM video-queue-monitor (default us-east4-c, ikuti panel lab).

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

ask METRIC "big_video_upload_rate" "Nama log metric (sesuai panel lab)"
ask THRESHOLD "3" "Ambang alert (upload rate per detik)"

VM_ZONE=$(gcloud compute instances list --filter="name=video-queue-monitor" \
  --format="value(zone)" --limit=1 2>/dev/null | awk -F/ '{print $NF}')
ask ZONE "${VM_ZONE:-us-east4-c}" "Zone VM video-queue-monitor (cocokkan dengan panel lab)"
ask REGION "${ZONE%-*}" "Region (cocokkan dengan panel lab)"

step() { printf '\n\033[1;34m>> %s\033[0m\n' "$*"; }

# ── Task 1: Cloud Monitoring ──
step "Task 1/5. Enable Cloud Monitoring dan API pendukung"
gcloud services enable monitoring.googleapis.com logging.googleapis.com \
  compute.googleapis.com cloudfunctions.googleapis.com --project="$PROJECT_ID" --quiet
echo "API monitoring selesai di-enable."

# VM di-provision lab saat start; tunggu sampai muncul (maks ±2 menit).
step "Tunggu VM video-queue-monitor siap"
INSTANCE_ID=""
for i in $(seq 1 12); do
  INSTANCE_ID=$(gcloud compute instances describe video-queue-monitor --zone="$ZONE" \
    --format='value(id)' 2>/dev/null || true)
  [[ -n "$INSTANCE_ID" ]] && { echo "video-queue-monitor siap (instance id: $INSTANCE_ID)"; break; }
  echo "  belum ada (percobaan $i/12), tunggu 10 detik..."
  sleep 10
done
[[ -n "$INSTANCE_ID" ]] || echo "WARNING: VM belum terdeteksi di $ZONE. Cek nama/zone di panel lab, lalu ulangi."

# ── Task 2: startup script video-queue-monitor ──
step "Task 2/5. Perbaiki startup script video-queue-monitor"
# Script bawaan lab men-download Go, install ops agent, lalu menjalankan Go app
# (gs://spls/gsp338/video_queue/main.go) yang menulis custom metric
# opencensus/my.videoservice.org/measure/input_queue_size. Yang belum terisi:
# env var project, instance id, dan zone.
cat > /tmp/gsp338_startup.sh << EOF_START
#!/bin/bash
ZONE="$ZONE"
REGION="${ZONE%-*}"
PROJECT_ID="$PROJECT_ID"
INSTANCE_ID="$INSTANCE_ID"

echo "\$(date) startup: zone=\$ZONE project=\$PROJECT_ID instance=\$INSTANCE_ID" >> /var/log/gsp338-startup.log

sudo apt-get update -y
sudo apt-get install -y wget git

sudo chmod 777 /usr/local/
sudo wget -q https://go.dev/dl/go1.22.8.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.8.linux-amd64.tar.gz
export PATH=\$PATH:/usr/local/go/bin

# Ops agent (tip 2: instance wajib punya monitoring agent)
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
sudo service google-cloud-ops-agent start || true

mkdir -p /work/go/cache
export GOPATH=/work/go
export GOCACHE=/work/go/cache
export GO111MODULE=on

mkdir -p /work/go/video
gsutil cp gs://spls/gsp338/video_queue/main.go /work/go/video/main.go

cd /work/go/video
go get go.opencensus.io
go get contrib.go.opencensus.io/exporter/stackdriver

# Env yang dibutuhkan Go app untuk menulis custom metric
export MY_PROJECT_ID="$PROJECT_ID"
export MY_GCE_INSTANCE_ID="$INSTANCE_ID"
export MY_GCE_INSTANCE_ZONE="$ZONE"

cd /work
go mod init go/video/main || true
go mod tidy || true
nohup go run /work/go/video/main.go > /var/log/gsp338-goapp.log 2>&1 &
echo "\$(date) app dimulai" >> /var/log/gsp338-startup.log
EOF_START

gcloud compute instances add-metadata video-queue-monitor --zone="$ZONE" \
  --metadata-from-file startup-script=/tmp/gsp338_startup.sh --quiet
echo "Startup script di-update. Restart instance..."
gcloud compute instances stop video-queue-monitor --zone="$ZONE" --quiet
gcloud compute instances start video-queue-monitor --zone="$ZONE" --quiet
echo "Instance di-restart. Custom metric input_queue_size muncul 5-10 menit lagi."

# ── Task 3: log metric ──
step "Task 3/5. Log metric $METRIC (4K/8K)"
if gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Metric $METRIC sudah ada, update filter."
  gcloud logging metrics update "$METRIC" \
    --description="Metric untuk upload video resolusi tinggi (4K/8K)" \
    --log-filter='textPayload=~"file_format\: ([4,8]K).*"' --quiet
else
  gcloud logging metrics create "$METRIC" \
    --description="Metric untuk upload video resolusi tinggi (4K/8K)" \
    --log-filter='textPayload=~"file_format\: ([4,8]K).*"' --quiet
fi
echo "Log metric $METRIC dibuat."

# ── Task 4: chart di Media_Dashboard ──
step "Task 4/5. Chart custom metric di Media_Dashboard"
DASHBOARD_ID=""
for i in $(seq 1 10); do
  DASHBOARD_ID=$(gcloud monitoring dashboards list \
    --filter='displayName="Media_Dashboard"' \
    --format='value(name)' 2>/dev/null | head -1)
  [[ -n "$DASHBOARD_ID" ]] && break
  echo "  Media_Dashboard belum ketemu (percobaan $i/10), tunggu 20 detik..."
  sleep 20
done

if [[ -n "$DASHBOARD_ID" ]]; then
  gcloud monitoring dashboards describe "$DASHBOARD_ID" --format=json \
    > /tmp/gsp338_dashboard.json 2>/dev/null || true
  python3 - "$METRIC" << 'PYEOF'
import json, sys

metric = sys.argv[1]
path = '/tmp/gsp338_dashboard.json'

try:
    with open(path) as f:
        raw = f.read()
    if not raw.strip().startswith('{'):
        raise ValueError('describe tidak mengembalikan objek JSON')
    dash = json.loads(raw)
except Exception as e:
    print(f"SKIP: dashboard tidak bisa dibaca ({e}); update lewat Console.")
    sys.exit(0)

queue_widget = {
    "title": "Video Input Queue Size",
    "xyChart": {
        "dataSets": [{
            "timeSeriesQuery": {
                "timeSeriesFilter": {
                    "filter": 'metric.type="custom.googleapis.com/opencensus/my.videoservice.org/measure/input_queue_size" resource.type="gce_instance"',
                    "aggregation": {"alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN"}
                }
            },
            "plotType": "LINE"
        }],
        "timeshiftDuration": "0s",
        "yAxis": {"scale": "LINEAR"}
    }
}
rate_widget = {
    "title": "High Resolution Video Upload Rate",
    "xyChart": {
        "dataSets": [{
            "timeSeriesQuery": {
                "timeSeriesFilter": {
                    "filter": 'metric.type="logging.googleapis.com/user/' + metric + '"',
                    "aggregation": {"alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE"}
                }
            },
            "plotType": "LINE"
        }],
        "timeshiftDuration": "0s",
        "yAxis": {"scale": "LINEAR"}
    }
}

existing = set()
layout = dash.get('layout', {})
if 'mosaicLayout' in dash and isinstance(dash['mosaicLayout'], dict):
    layout = dash
for tile in dash.get('mosaicLayout', {}).get('tiles', []):
    existing.add(tile.get('widget', {}).get('title', ''))
for w in dash.get('gridLayout', {}).get('widgets', []):
    existing.add(w.get('title', ''))

new = []
if 'Video Input Queue Size' not in existing:
    new.append(queue_widget)
if 'High Resolution Video Upload Rate' not in existing:
    new.append(rate_widget)

if not new:
    print("Kedua chart sudah ada, lewati.")
    sys.exit(0)

if 'mosaicLayout' in dash and isinstance(dash['mosaicLayout'], dict):
    tiles = dash['mosaicLayout'].get('tiles', [])
    max_y = max((t.get('yPos', 0) + t.get('height', 0)) for t in tiles) if tiles else 0
    for i, w in enumerate(new):
        tiles.append({"yPos": max_y + i * 16, "xPos": 0, "width": 24, "height": 16, "widget": w})
    dash['mosaicLayout']['tiles'] = tiles
elif 'gridLayout' in dash:
    dash['gridLayout']['widgets'] = dash['gridLayout'].get('widgets', []) + new
else:
    dash['gridLayout'] = {"widgets": new}

dash.pop('name', None)  # etag dipertahankan untuk optimistic concurrency

with open('/tmp/gsp338_dashboard_updated.json', 'w') as f:
    json.dump(dash, f, indent=2)
print("JSON dashboard di-update dengan 2 chart baru.")
PYEOF

  gcloud monitoring dashboards update "$DASHBOARD_ID" \
    --config-from-file=/tmp/gsp338_dashboard_updated.json --quiet 2>/dev/null \
    || echo "UPDATE GAGAL: dashboard tetap harus di-edit lewat Console (dashboards → Media_Dashboard → Add widget)."
  echo "Chart ditambahkan ke Media_Dashboard."
else
  echo "WARNING: Media_Dashboard tidak ditemukan. Task 4 manual lewat console."
fi

# ── Task 5: alert policy ──
step "Task 5/5. Alert custom di $METRIC (threshold $THRESHOLD/s)"
cat > /tmp/gsp338_alert.json << EOF_ALERT
{
  "displayName": "High Resolution Video Upload Rate Alert",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "$METRIC rate exceeds $THRESHOLD",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/$METRIC\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": $THRESHOLD,
        "duration": "0s",
        "trigger": {"count": 1},
        "aggregations": [
          {"alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE"}
        ]
      }
    }
  ]
}
EOF_ALERT

if ! gcloud alpha monitoring policies create --policy-from-file=/tmp/gsp338_alert.json --quiet; then
  echo "  gcloud alpha gagal, fallback ke REST API..."
  TOKEN=$(gcloud auth print-access-token)
  curl -s -X POST \
    "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/alertPolicies" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d @/tmp/gsp338_alert.json | jq '.name // .error.message' -r
fi
echo "Alert policy dibuat."

# Verifikasi quick: metric input_queue_size sudah muncul?
step "Cek cepat custom metric input_queue_size"
if gcloud monitoring metrics-descriptors list \
  --filter='metric.type="custom.googleapis.com/opencensus/my.videoservice.org/measure/input_queue_size"' \
  --format='value(type)' 2>/dev/null | head -1 | grep -q input_queue_size; then
  echo "input_queue_size sudah muncul."
else
  echo "Belum terlihat (normal, 5-10 menit). Cek via Metrics Explorer: input_queue_size"
fi

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Cloud Monitoring enabled"
echo "  Task 2 - video input queue custom metric (tunggu 5-10 menit sebelum klik)"
echo "  Task 3 - log metric $METRIC (4K/8K)"
echo "  Task 4 - dua custom metric di Media_Dashboard (data chart 5-10 menit)"
echo "  Task 5 - custom alert $METRIC > $THRESHOLD/s"