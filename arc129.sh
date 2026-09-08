#!/usr/bin/env bash
# ARC129 - Secure Lakehouse Data: Challenge Lab
#
#   bash arc129.sh
#
# Checkpoint:
#   Task 1 (auto) - Dataset online_shop, koneksi BigLake, IAM Storage Object Viewer,
#                   external table user_online_sessions dari CSV di GCS
#   Task 2 (auto) - Schema + policy tag (fine-grained access) di kolom sensitif
#   Task 3 (auto) - Hapus IAM binding storage.objectViewer milik USER 2
#
# USER 2 diisi dari email yang muncul di halaman lab (tokenizer user kedua),
# lewat env var atau jawaban di prompt.

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

ask USER_2 "" "Email USER 2 dari panel lab (yang IAM-nya harus dicabut)"

step() { printf '\n\033[1;34m>> %s\033[0m\n' "$*"; }

step "Task 1/3. Dataset online_shop, koneksi BigLake, IAM, external table"
if ! bq show online_shop >/dev/null 2>&1; then
  bq --location=US mk -d online_shop
fi

if ! bq show --connection "$PROJECT_ID.US.user_data_connection" >/dev/null 2>&1; then
  bq mk --connection --location=US --project_id="$PROJECT_ID" \
    --connection_type=CLOUD_RESOURCE user_data_connection
fi

SERVICE_ACCOUNT=$(bq show --format=json --connection "$PROJECT_ID.US.user_data_connection" \
  | jq -r '.cloudResource.serviceAccountId')
[[ -n "$SERVICE_ACCOUNT" ]] || { echo "Service account koneksi tidak ketemu."; exit 1; }
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role=roles/storage.objectViewer

bq mkdef --autodetect \
  --connection_id="$PROJECT_ID.US.user_data_connection" \
  --source_format=CSV \
  "gs://$PROJECT_ID-bucket/user-online-sessions.csv" > /tmp/arc129_tabledef.json

if ! bq show online_shop.user_online_sessions >/dev/null 2>&1; then
  bq mk --external_table_definition=/tmp/arc129_tabledef.json \
    --project_id="$PROJECT_ID" online_shop.user_online_sessions
fi

step "Task 2/3. Schema + policy tag ke kolom sensitif"
TAXONOMY_NAME=$(gcloud data-catalog taxonomies list \
  --location=us --project="$PROJECT_ID" \
  --format="value(displayName)" --limit=1)
TAXONOMY_ID=$(gcloud data-catalog taxonomies list \
  --location=us --project="$PROJECT_ID" \
  --format="value(name)" \
  --filter="displayName=$TAXONOMY_NAME" | awk -F'/' '{print $6}')
POLICY_TAG=$(gcloud data-catalog taxonomies policy-tags list \
  --location=us --taxonomy="$TAXONOMY_ID" \
  --format="value(name)" --limit=1)

cat > /tmp/arc129_schema.json << EOM
[
  { "mode": "NULLABLE", "name": "ad_event_id", "type": "INTEGER" },
  { "mode": "NULLABLE", "name": "user_id", "type": "INTEGER" },
  { "mode": "NULLABLE", "name": "uri", "type": "STRING" },
  { "mode": "NULLABLE", "name": "traffic_source", "type": "STRING" },
  {
    "mode": "NULLABLE",
    "name": "zip",
    "policyTags": { "names": ["$POLICY_TAG"] },
    "type": "STRING"
  },
  { "mode": "NULLABLE", "name": "event_type", "type": "STRING" },
  { "mode": "NULLABLE", "name": "state", "type": "STRING" },
  { "mode": "NULLABLE", "name": "country", "type": "STRING" },
  { "mode": "NULLABLE", "name": "city", "type": "STRING" },
  {
    "mode": "NULLABLE",
    "name": "latitude",
    "policyTags": { "names": ["$POLICY_TAG"] },
    "type": "FLOAT"
  },
  { "mode": "NULLABLE", "name": "created_at", "type": "TIMESTAMP" },
  {
    "mode": "NULLABLE",
    "name": "ip_address",
    "policyTags": { "names": ["$POLICY_TAG"] },
    "type": "STRING"
  },
  { "mode": "NULLABLE", "name": "session_id", "type": "STRING" },
  {
    "mode": "NULLABLE",
    "name": "longitude",
    "policyTags": { "names": ["$POLICY_TAG"] },
    "type": "FLOAT"
  },
  { "mode": "NULLABLE", "name": "id", "type": "INTEGER" }
]
EOM

bq update --schema /tmp/arc129_schema.json "$PROJECT_ID:online_shop.user_online_sessions"

step "Verifikasi: query tanpa kolom sensitif"
bq query --use_legacy_sql=false --format=csv \
  "SELECT * EXCEPT(zip, latitude, ip_address, longitude) FROM \`$PROJECT_ID.online_shop.user_online_sessions\`"

step "Task 3/3. Cabut IAM binding USER 2"
if [[ -n "$USER_2" ]]; then
  gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="user:$USER_2" \
    --role=roles/storage.objectViewer \
    || echo "Binding untuk $USER_2 sudah tidak ada, lanjut."
else
  echo "USER_2 kosong, lewati. Cek manual: IAM user kedua di lab sudah tidak punya storage.objectViewer?"
fi

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a BigQuery dataset, connection, dan external table (BigLake)"
echo "  Task 2 - Terapkan fine-grained access (policy tag) ke kolom sensitif"
echo "  Task 3 - Hapus akses storage.objectViewer milik USER 2"