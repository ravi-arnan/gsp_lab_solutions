#!/usr/bin/env bash
# ARC123 - Enrich Metadata and Discovery of Lakehouse Data: Challenge Lab
#
#   bash arc123.sh
#
# Checkpoint:
#   Task 1 (33 pts)  - Create BigQuery dataset
#   Task 2 (33 pts)  - Create Lakehouse table using Cloud Resource connection
#   Task 3 (34 pts)  - Create aspect and apply to Lakehouse table

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

step() {
  echo
  echo "=== $1 ==="
}

# Enable required APIs (ikut Happy.sh: datacatalog + bigqueryconnection + dataplex)
step "Enable required APIs"
gcloud services enable datacatalog.googleapis.com bigqueryconnection.googleapis.com dataplex.googleapis.com bigquery.googleapis.com --project="$PROJECT_ID" --quiet

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
MULTI_REGION="US"
DATASET="ecommerce"
CONNECTION="customer_data_connection"
TABLE="customer_online_sessions"
# Happy.sh pakai bucket dinamis gs://$PROJECT_ID-bucket/ (lebih tahan instance baru)
GCS_URI="gs://${PROJECT_ID}-bucket/customer-online-sessions.csv"
ASPECT_NAME="Sensitive Data Aspect"

step "Task 1: Create BigQuery dataset"

if bq --project_id="$PROJECT_ID" show --format=prettyjson "$DATASET" >/dev/null 2>&1; then
  echo "Dataset $DATASET sudah ada, lewati create"
else
  bq --project_id="$PROJECT_ID" mk --location="$MULTI_REGION" "$DATASET"
  echo "Dataset $DATASET dibuat di $MULTI_REGION"
fi

step "Task 2: Create Cloud Resource connection and Lakehouse table"

# Create Cloud Resource connection
if bq --project_id="$PROJECT_ID" show --connection --format=prettyjson --location="$MULTI_REGION" "$CONNECTION" >/dev/null 2>&1; then
  echo "Connection $CONNECTION sudah ada, lewati create"
else
  bq --project_id="$PROJECT_ID" mk --connection --connection_type=CLOUD_RESOURCE \
    --location="$MULTI_REGION" \
    --project_id="$PROJECT_ID" \
    "$CONNECTION"
  echo "Connection $CONNECTION dibuat"
fi

# Get connection service account
CONN_SA=$(bq --project_id="$PROJECT_ID" show --connection --format=json --location="$MULTI_REGION" "$CONNECTION" | jq -r '.cloudResource.serviceAccountId')
echo "Connection service account: $CONN_SA"

# Grant Storage Object Viewer to connection SA
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CONN_SA" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true
echo "IAM binding untuk $CONN_SA diberikan"

# Create Lakehouse table (external table with Cloud Resource connection)
# Ikut Happy.sh: bq mkdef --autodetect --connection_id=... --source_format=CSV gs://... > /tmp/tabledef.json
if bq --project_id="$PROJECT_ID" show --format=prettyjson "$DATASET.$TABLE" >/dev/null 2>&1; then
  echo "Table $DATASET.$TABLE sudah ada, lewati create"
else
  bq mkdef \
    --autodetect \
    --connection_id="${PROJECT_ID}.${MULTI_REGION}.${CONNECTION}" \
    --source_format=CSV \
    "${GCS_URI}" > /tmp/tabledef.json
  bq --project_id="$PROJECT_ID" mk \
    --external_table_definition=/tmp/tabledef.json \
    "$DATASET.$TABLE"
  echo "Lakehouse table $DATASET.$TABLE dibuat (mkdef autodetect)"
  rm -f /tmp/tabledef.json
fi

step "Task 3: Create aspect and apply to Lakehouse table"
# Multi-region aspect di United States = location "us" (bukan us-central1).
# Ikut ePlus: DATAPLEX_LOCATION=us, ASPECT_TYPE_ID=sensitive-data-aspect
ASPECT_TYPE_ID="sensitive-data-aspect"
DATAPLEX_LOCATION="us"

if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" --location="$DATAPLEX_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Aspect type $ASPECT_TYPE_ID sudah ada, lewati create"
else
  cat > /tmp/metadata_template.json <<'EOF'
{
  "name": "SensitiveDataAspect",
  "type": "record",
  "recordFields": [
    {
      "name": "has_sensitive_data",
      "type": "bool",
      "index": 1,
      "annotations": {
        "displayName": "Has Sensitive Data",
        "displayOrder": 1
      }
    },
    {
      "name": "sensitive_data_type",
      "type": "enum",
      "index": 2,
      "enumValues": [
        {"name": "Location Info", "index": 1},
        {"name": "Contact Info", "index": 2},
        {"name": "None", "index": 3}
      ],
      "annotations": {
        "displayName": "Sensitive Data Type",
        "displayOrder": 2
      }
    }
  ]
}
EOF
  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --location="$DATAPLEX_LOCATION" \
    --project="$PROJECT_ID" \
    --display-name="$ASPECT_NAME" \
    --metadata-template-file-name=/tmp/metadata_template.json --quiet
  echo "Aspect type $ASPECT_TYPE_ID dibuat di $DATAPLEX_LOCATION"
fi

# Apply aspect ke entry BigQuery via Knowledge Catalog (ikut ePlus)
# Entry untuk BigQuery table ada di entryGroups/@bigquery
cat > /tmp/aspect_values.json <<EOF
{
  "${PROJECT_ID}.${DATAPLEX_LOCATION}.${ASPECT_TYPE_ID}": {
    "data": {
      "has_sensitive_data": true,
      "sensitive_data_type": "Location Info"
    }
  }
}
EOF

ENTRY_NAME="projects/${PROJECT_ID}/locations/${DATAPLEX_LOCATION}/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET}/tables/${TABLE}"
ASPECT_APPLIED=false
for ATTEMPT in 1 2 3 4 5 6; do
  if gcloud dataplex entries modify "$ENTRY_NAME" \
    --update-aspects=/tmp/aspect_values.json \
    --project="$PROJECT_ID" --quiet 2>/dev/null; then
    ASPECT_APPLIED=true
    echo "Aspect diterapkan ke table $DATASET.$TABLE (attempt $ATTEMPT)"
    break
  fi
  echo "Entry Knowledge Catalog belum siap, retry ($ATTEMPT/6)..."
  sleep 10
done
if [[ "$ASPECT_APPLIED" != "true" ]]; then
  echo "WARNING: Gagal apply aspect setelah 6 percobaan. Entry mungkin belum ter-index."
  echo "Coba manual: gcloud dataplex entries modify $ENTRY_NAME --update-aspects=/tmp/aspect_values.json"
fi

step "Verifikasi"
echo "Dataset: $DATASET"
bq --project_id="$PROJECT_ID" show "$DATASET" 2>/dev/null | head -10

echo
echo "Connection: $CONNECTION"
bq --project_id="$PROJECT_ID" show --connection --location="$MULTI_REGION" "$CONNECTION" 2>/dev/null | head -10

echo
echo "Table: $DATASET.$TABLE"
bq --project_id="$PROJECT_ID" show "$DATASET.$TABLE" 2>/dev/null | head -15

echo
echo "Aspect type: $ASPECT_TYPE_ID ($DATAPLEX_LOCATION)"
gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" --location="$DATAPLEX_LOCATION" --project="$PROJECT_ID" 2>/dev/null | head -15

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a BigQuery dataset"
echo "  Task 2 - Create a Lakehouse table using a Cloud Resource connection"
echo "  Task 3 - Create an aspect and apply it to the Lakehouse table"