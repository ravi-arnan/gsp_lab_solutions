#!/usr/bin/env bash
# GSP090 - Monitor Multiple Google Cloud Projects with Cloud Monitoring
#
#   bash gsp090.sh
#
# Checkpoint:
#   Task 1 (5 pts) - Create Project 2's virtual machine
#   Task 2 (5 pts) - Create a Cloud Monitoring Group
#   Task 3 (5 pts) - Uptime Check for your group
#   Task 4 (5 pts) - Alerting Policy for the group
#
# LAMA: ~2-3 menit.

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

# Helper untuk REST call ke Cloud Monitoring
gcurl() {
  local token
  token="$(gcloud auth print-access-token)"
  curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/json" "$@"
}

echo "Mendeteksi daftar project Google Cloud..."
ALL_PROJECTS=($(gcloud projects list --format="value(projectId)" 2>/dev/null | grep -E '^qwiklabs-gcp-' | sort))

DEFAULT_P1=""
DEFAULT_P2=""

# Project 1 memiliki VM bawaan lab. Project 2 adalah project baru tempat instance2 dibuat.
for p in "${ALL_PROJECTS[@]}"; do
  VMS="$(gcloud compute instances list --project="$p" --format="value(name)" 2>/dev/null || true)"
  VMS_EXISTING="$(echo "$VMS" | grep -v "^instance2$" || true)"
  if [[ -n "$VMS_EXISTING" ]]; then
    DEFAULT_P1="$p"
  else
    DEFAULT_P2="$p"
  fi
done

# Pastikan P1 dan P2 terisi dari dua project qwiklabs-gcp- yang berbeda
if [[ -z "$DEFAULT_P1" && -n "$DEFAULT_P2" ]]; then
  for p in "${ALL_PROJECTS[@]}"; do
    if [[ "$p" != "$DEFAULT_P2" ]]; then DEFAULT_P1="$p"; break; fi
  done
elif [[ -z "$DEFAULT_P2" && -n "$DEFAULT_P1" ]]; then
  for p in "${ALL_PROJECTS[@]}"; do
    if [[ "$p" != "$DEFAULT_P1" ]]; then DEFAULT_P2="$p"; break; fi
  done
elif [[ -z "$DEFAULT_P1" && -z "$DEFAULT_P2" && ${#ALL_PROJECTS[@]} -ge 2 ]]; then
  DEFAULT_P2="${ALL_PROJECTS[0]}"
  DEFAULT_P1="${ALL_PROJECTS[1]}"
fi

ask PROJECT_2 "${DEFAULT_P2}" "Project ID 2 (scoping project tempat instance2 dibuat)"
ask PROJECT_1 "${DEFAULT_P1}" "Project ID 1 (monitored project tempat instance1 berada)"

[[ -n "$PROJECT_2" ]] || { echo "PROJECT_2 belum di-set."; exit 1; }
[[ -n "$PROJECT_1" ]] || { echo "PROJECT_1 belum di-set."; exit 1; }

ask REGION "europe-west1" "Region untuk instance2"
ask ZONE "europe-west1-b" "Zone untuk instance2"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Setup & Task 1
step "Task 1: Set Project 2 ($PROJECT_2) dan buat VM instance2"
gcloud config set project "$PROJECT_2"

# Enable API yang diperlukan di Project 2
gcloud services enable \
  compute.googleapis.com \
  monitoring.googleapis.com \
  --project="$PROJECT_2" -q || true

# Pastikan monitoring API juga aktif di Project 1
gcloud services enable \
  monitoring.googleapis.com \
  --project="$PROJECT_1" -q || true

if gcloud compute instances describe instance2 --zone="$ZONE" --project="$PROJECT_2" >/dev/null 2>&1; then
  echo "Instance instance2 sudah ada di $PROJECT_2 ($ZONE)."
else
  echo "Membuat instance2 di $PROJECT_2 ($ZONE)..."
  gcloud compute instances create instance2 \
    --project="$PROJECT_2" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    -q
fi

# ----------------------------------------------------------------- Metrics Scope
step "Setup Metrics Scope: Tambahkan Project 1 ($PROJECT_1) ke Metrics Scope Project 2 ($PROJECT_2)"
echo "Menghubungkan Metrics Scope..."
gcurl -X POST \
  "https://monitoring.googleapis.com/v1/locations/global/metricsScopes/${PROJECT_2}/projects" \
  -d "{\"name\": \"locations/global/metricsScopes/${PROJECT_2}/projects/${PROJECT_1}\"}" >/dev/null || true

# ----------------------------------------------------------------- Task 2
step "Task 2: Konfigurasi Cloud Monitoring Group (DemoGroup)"
GROUP_ID=""

EXISTING_GROUPS=$(gcurl "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/groups")

if command -v jq >/dev/null 2>&1; then
  GROUP_ID=$(echo "$EXISTING_GROUPS" | jq -r '.group[]? | select(.displayName=="DemoGroup") | .name' 2>/dev/null | awk -F'/' '{print $NF}' | head -n 1)
fi

if [[ -n "$GROUP_ID" ]]; then
  echo "Memperbarui filter DemoGroup (ID: $GROUP_ID) ke resource.metadata.name..."
  gcurl -X PUT \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/groups/${GROUP_ID}" \
    -d "{
      \"name\": \"projects/${PROJECT_2}/groups/${GROUP_ID}\",
      \"displayName\": \"DemoGroup\",
      \"filter\": \"resource.metadata.name = has_substring(\\\"instance\\\")\"
    }" >/dev/null || true
else
  echo "Membuat group DemoGroup..."
  CREATE_GROUP_RESP=$(gcurl -X POST \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/groups" \
    -d '{
      "displayName": "DemoGroup",
      "filter": "resource.metadata.name = has_substring(\"instance\")"
    }')

  if command -v jq >/dev/null 2>&1; then
    GROUP_ID=$(echo "$CREATE_GROUP_RESP" | jq -r '.name // empty' | awk -F'/' '{print $NF}')
  fi
fi

echo "Group DemoGroup ID: ${GROUP_ID:-tidak ditemukan}"

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat Uptime Check untuk DemoGroup (port 22 TCP)"
CHECK_ID=""

EXISTING_CHECKS=$(gcurl "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/uptimeCheckConfigs")

if command -v jq >/dev/null 2>&1; then
  CHECK_ID=$(echo "$EXISTING_CHECKS" | jq -r '.uptimeCheckConfigs[]? | select(.displayName=="DemoGroup uptime check") | .name' 2>/dev/null | awk -F'/' '{print $NF}' | head -n 1)
fi

if [[ -z "$CHECK_ID" && -n "$GROUP_ID" ]]; then
  echo "Membuat Uptime Check 'DemoGroup uptime check'..."
  CREATE_CHECK_RESP=$(gcurl -X POST \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/uptimeCheckConfigs" \
    -d "{
      \"displayName\": \"DemoGroup uptime check\",
      \"resourceGroup\": {
        \"groupId\": \"${GROUP_ID}\",
        \"resourceType\": \"INSTANCE\"
      },
      \"tcpCheck\": {
        \"port\": 22
      },
      \"period\": \"60s\",
      \"timeout\": \"10s\"
    }")

  if command -v jq >/dev/null 2>&1; then
    CHECK_ID=$(echo "$CREATE_CHECK_RESP" | jq -r '.name // empty' | awk -F'/' '{print $NF}')
  fi
fi

echo "Uptime Check ID: ${CHECK_ID:-tidak ditemukan}"

# ----------------------------------------------------------------- Task 4
step "Task 4: Buat Alerting Policy (Uptime Check Policy)"
WORKDIR="$(mktemp -d)"
POLICY_FILE="$WORKDIR/awesome.json"

CHECK_FILTER="resource.type = \"gce_instance\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
if [[ -n "$CHECK_ID" ]]; then
  CHECK_FILTER="${CHECK_FILTER} AND metric.labels.check_id = \"${CHECK_ID}\""
fi

cat > "$POLICY_FILE" <<EOF
{
  "displayName": "Uptime Check Policy",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "VM Instance - Check passed",
      "conditionAbsent": {
        "filter": "${CHECK_FILTER}",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "crossSeriesReducer": "REDUCE_NONE",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE"
          }
        ],
        "duration": "300s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {},
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "severity": "SEVERITY_UNSPECIFIED"
}
EOF

# Hapus policy lama jika sudah ada agar bersih
EXISTING_POLICIES=$(gcloud monitoring policies list --project="$PROJECT_2" --filter='displayName="Uptime Check Policy"' --format="value(name)" 2>/dev/null || true)
for pol in $EXISTING_POLICIES; do
  echo "Menghapus policy lama: $pol..."
  gcloud monitoring policies delete "$pol" --project="$PROJECT_2" -q 2>/dev/null || true
done

echo "Mendaftarkan Alerting Policy baru..."
if ! gcloud alpha monitoring policies create --policy-from-file="$POLICY_FILE" --project="$PROJECT_2" -q 2>/dev/null; then
  if ! gcloud monitoring policies create --policy-from-file="$POLICY_FILE" --project="$PROJECT_2" -q 2>/dev/null; then
    gcurl -X POST \
      "https://monitoring.googleapis.com/v3/projects/${PROJECT_2}/alertPolicies" \
      -d @"$POLICY_FILE"
  fi
fi

rm -rf "$WORKDIR"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create Project 2's virtual machine (Task 1)
  2. Create a Cloud Monitoring Group (Task 2)
  3. Uptime Check for your group (Task 3)
  4. Alerting Policy for the group (Task 4)

Kuis Pemahaman (Task 7):
  Pertanyaan: "Cloud Monitoring lets you define and monitor groups of resources with Cloud Monitoring Group."
  Jawaban: True
==============================================================
EOF
