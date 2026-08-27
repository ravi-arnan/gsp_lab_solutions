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

# Enable required APIs
step "Enable required APIs"
gcloud services enable bigquery.googleapis.com dataplex.googleapis.com datacatalog.googleapis.com --project="$PROJECT_ID" --quiet

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
MULTI_REGION="US"
DATASET="ecommerce"
CONNECTION="customer_data_connection"
TABLE="customer_online_sessions"
GCS_URI="gs://qwiklabs-gcp-02-46aab1545321-bucket/customer-online-sessions.csv"
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
if bq --project_id="$PROJECT_ID" show --format=prettyjson "$DATASET.$TABLE" >/dev/null 2>&1; then
  echo "Table $DATASET.$TABLE sudah ada, lewati create"
else
  bq --project_id="$PROJECT_ID" mk --external_table_definition="$GCS_URI" \
    --connection_id="$PROJECT_ID.$MULTI_REGION.$CONNECTION" \
    --autodetect \
    "$DATASET.$TABLE"
  echo "Lakehouse table $DATASET.$TABLE dibuat"
fi

step "Task 3: Create aspect and apply to Lakehouse table"

# Check if Dataplex aspect type exists, create if not
ASPECT_TYPE="projects/$PROJECT_ID/locations/$REGION/aspectTypes/$ASPECT_NAME"
ASPECT_TYPE_ID=$(echo "$ASPECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

if gcloud dataplex aspects types describe "$ASPECT_TYPE_ID" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Aspect type $ASPECT_TYPE_ID sudah ada, lewati create"
else
  gcloud dataplex aspects types create "$ASPECT_TYPE_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="$ASPECT_NAME" \
    --metadata-template='{
      "fields": [
        {"name": "has_sensitive_data", "type": "BOOLEAN", "displayName": "Has Sensitive Data"},
        {"name": "sensitive_data_type", "type": "ENUM", "displayName": "Sensitive Data Type", "enumValues": ["Location Info", "Contact Info", "None"]}
      ]
    }'
  echo "Aspect type $ASPECT_TYPE_ID dibuat"
fi

# Apply aspect to the table
# Need to get the entry name for the BigQuery table in Data Catalog
ENTRY_NAME=$(gcloud data-catalog entries lookup \
  --project="$PROJECT_ID" \
  --linked-resource="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET/tables/$TABLE" \
  --format="value(name)" 2>/dev/null || echo "")

if [[ -n "$ENTRY_NAME" ]]; then
  echo "Entry ditemukan: $ENTRY_NAME"
  
  # Create aspect on the entry
  gcloud dataplex aspects create \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --aspect-type="$ASPECT_TYPE_ID" \
    --resource="$ENTRY_NAME" \
    --aspect-data='{
      "has_sensitive_data": true,
      "sensitive_data_type": "Location Info"
    }' \
    --quiet 2>/dev/null || {
    echo "Aspect mungkin sudah ada, mencoba update..."
    gcloud dataplex aspects update \
      --project="$PROJECT_ID" \
      --location="$REGION" \
      --aspect-type="$ASPECT_TYPE_ID" \
      --resource="$ENTRY_NAME" \
      --aspect-data='{
        "has_sensitive_data": true,
        "sensitive_data_type": "Location Info"
      }' \
      --quiet
  }
  echo "Aspect diterapkan ke table $DATASET.$TABLE"
else
  echo "WARNING: Entry Data Catalog untuk table tidak ditemukan. Jalankan manual:"
  echo "  gcloud data-catalog entries lookup --linked-resource=\"//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET/tables/$TABLE\""
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
echo "Aspect type: $ASPECT_TYPE_ID"
gcloud dataplex aspects types describe "$ASPECT_TYPE_ID" --location="$REGION" --project="$PROJECT_ID" 2>/dev/null | head -15

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a BigQuery dataset"
echo "  Task 2 - Create a Lakehouse table using a Cloud Resource connection"
echo "  Task 3 - Create an aspect and apply it to the Lakehouse table"