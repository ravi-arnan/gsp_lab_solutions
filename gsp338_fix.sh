#!/usr/bin/env bash
# GSP338 - Perbaikan Task 3 & Task 4 (lab sedang berjalan, task lain sudah lolos)
#
#   bash gsp338_fix.sh
#
# Konteks: script pihak ketiga (KenilithCloudx.sh) memakai filter log metric
# versi lama dan tidak menyentuh dashboard sama sekali.
#   Task 3 (0/20) - Log metric filter salah  -> update filter ke regex lab
#                   (textPayload=~"file_format\: ([4,8]K).*")
#   Task 4 (0/20) - Chart belum ditambahkan  -> + 2 widget di Media_Dashboard
#
# Idempoten: metric sudah benar maka di-skip, widget sudah ada maka di-skip.

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

step() { printf '\n\033[1;34m>> %s\033[0m\n' "$*"; }

# ── Task 3: log metric dengan filter yang benar ──
step "Task 3/5. Update filter log metric (regex 4K/8K)"
METRIC_FOUND=$(gcloud logging metrics list --format="value(name)" 2>/dev/null \
  | grep -E '^(big|huge)_video_upload_rate$' | head -1 || true)
ask METRIC "${METRIC_FOUND:-big_video_upload_rate}" "Nama log metric di panel lab"

FILTER='textPayload=~"file_format\: ([4,8]K).*"'
if gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  CURRENT=$(gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" \
    --format="value(filter)" 2>/dev/null || true)
  if [[ "$CURRENT" == *'file_format\: ([4,8]K).*'* ]]; then
    echo "Filter sudah benar, lewati."
  else
    gcloud logging metrics update "$METRIC" \
      --description="Metric for high resolution video uploads" \
      --log-filter="$FILTER" --quiet
    echo "Filter di-update ke: $FILTER"
  fi
else
  gcloud logging metrics create "$METRIC" \
    --description="Metric for high resolution video uploads" \
    --log-filter="$FILTER" --quiet
  echo "Metric $METRIC dibuat dengan: $FILTER"
fi

# ── Task 4: tambah 2 chart di Media_Dashboard ──
step "Task 4/5. Tambah 2 chart di Media_Dashboard"
DASHBOARD_ID=""
for i in $(seq 1 10); do
  DASHBOARD_ID=$(gcloud monitoring dashboards list \
    --filter='displayName="Media_Dashboard"' \
    --format='value(name)' 2>/dev/null | head -1)
  [[ -n "$DASHBOARD_ID" ]] && break
  echo "  Media_Dashboard belum ketemu (percobaan $i/10), tunggu 20 detik..."
  sleep 20
done

if [[ -z "$DASHBOARD_ID" ]]; then
  echo "GAGAL: Media_Dashboard tidak ditemukan di project ini."
  exit 1
fi

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
    print(f"GAGAL: dashboard tidak bisa dibaca ({e})")
    sys.exit(1)

def widget(title, f, aligner, axis_label):
    return {
        "title": title,
        "xyChart": {
            "dataSets": [{
                "timeSeriesQuery": {
                    "timeSeriesFilter": {
                        "filter": f,
                        "aggregation": {"alignmentPeriod": "60s", "perSeriesAligner": aligner}
                    }
                }
            }],
            "timeshiftDuration": "0s",
            "yAxis": {"label": axis_label, "scale": "LINEAR"}
        }
    }

rate_widget = widget(
    "High-Res Video Upload Rate",
    f'metric.type="logging.googleapis.com/user/{metric}"',
    "ALIGN_RATE", "Upload Rate")
queue_widget = widget(
    "OpenCensus - Video Input Queue Length",
    'metric.type="custom.googleapis.com/opencensus/my.videoservice.org/measure/input_queue_size"',
    "ALIGN_MEAN", "Queue Length")

existing = set()
if 'mosaicLayout' in dash and isinstance(dash.get('mosaicLayout'), dict):
    for tile in dash['mosaicLayout'].get('tiles', []):
        existing.add(tile.get('widget', {}).get('title', ''))
if 'gridLayout' in dash:
    for w in dash.get('gridLayout', {}).get('widgets', []):
        existing.add(w.get('title', ''))

new = []
if rate_widget["title"] not in existing:
    new.append(rate_widget)
if queue_widget["title"] not in existing:
    new.append(queue_widget)

if not new:
    print("Kedua widget sudah ada, lewati.")
    sys.exit(0)

if 'mosaicLayout' in dash and isinstance(dash.get('mosaicLayout'), dict):
    tiles = dash['mosaicLayout'].get('tiles', [])
    max_y = max((t.get('yPos', 0) + t.get('height', 0)) for t in tiles) if tiles else 0
    for i, w in enumerate(new):
        tiles.append({"yPos": max_y + i * 16, "xPos": 0, "width": 24, "height": 16, "widget": w})
    dash['mosaicLayout']['tiles'] = tiles
elif 'gridLayout' in dash:
    dash['gridLayout']['widgets'] = dash['gridLayout'].get('widgets', []) + new
else:
    dash['gridLayout'] = {"widgets": new}

with open('/tmp/gsp338_dashboard_updated.json', 'w') as f:
    json.dump(dash, f, indent=2)
print(f"Dashboard JSON siap: tambah {len(new)} widget.")
PYEOF

gcloud monitoring dashboards update "$DASHBOARD_ID" \
  --config-from-file=/tmp/gsp338_dashboard_updated.json --quiet
echo "Media_Dashboard di-update (2 chart ditambahkan)."

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 3 - $METRIC dengan filter regex 4K/8K (data masuk 5-10 menit)"
echo "  Task 4 - 2 chart (upload rate + queue length) di Media_Dashboard"
echo
echo "Catatan: data chart dan metric baru muncul 5-10 menit setelah logs masuk."