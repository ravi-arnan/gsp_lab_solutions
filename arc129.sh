#!/usr/bin/env bash
# ARC129 - Secure Lakehouse Data: Challenge Lab
#
#   bash arc129.sh
#
# Checkpoint:
#   Task 1 (33 pts)  - Create Lakehouse table using Cloud Resource connection
#   Task 2 (33 pts)  - Create, apply, and verify aspect on sensitive columns
#   Task 3 (34 pts)  - Remove IAM permissions to Cloud Storage for user 2

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

MULTI_REGION="US"
DATASET="online_shop"
CONNECTION="user_data_connection"
TABLE="user_online_sessions"
GCS_URI="gs://qwiklabs-gcp-01-1b647f7bcbc7-bucket/user-online-sessions.csv"
ASPECT_NAME="Sensitive Data Aspect"
SENSITIVE_COLUMNS=("zip" "latitude" "ip_address" "longitude")
USER_TO_REMOVE="student-03-f1879f24a800@qwiklabs.net"

step "Task 1: Create BigQuery dataset, connection, and Lakehouse table"

# Create BigQuery dataset
if bq --project_id="$PROJECT_ID" show --format=prettyjson "$DATASET" >/dev/null 2>&1; then
  echo "Dataset $DATASET sudah ada, lewati create"
else
  bq --project_id="$PROJECT_ID" mk --location="$MULTI_REGION" "$DATASET"
  echo "Dataset $DATASET dibuat di $MULTI_REGION"
fi

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
  cat > /tmp/table_def.json <<EOF
{
  "sourceFormat": "CSV",
  "sourceUris": ["$GCS_URI"],
  "autodetect": true,
  "connectionId": "$PROJECT_ID.$MULTI_REGION.$CONNECTION"
}
EOF
  bq --project_id="$PROJECT_ID" mk --external_table_definition=/tmp/table_def.json "$DATASET.$TABLE"
  echo "Lakehouse table $DATASET.$TABLE dibuat"
fi

step "Task 2: Create aspect and apply to sensitive columns"

# Check if Dataplex aspect type exists, create if not
ASPECT_TYPE_ID=$(echo "$ASPECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" --location="$MULTI_REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Aspect type $ASPECT_TYPE_ID sudah ada, lewati create"
else
  cat > /tmp/metadata_template.json <<EOF
{
  "definition": {
    "fields": [
      {"name": "has_sensitive_data", "type": "BOOL", "displayName": "Has Sensitive Data"}
    ]
  }
}
EOF
  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --location="$MULTI_REGION" \
    --project="$PROJECT_ID" \
    --display-name="$ASPECT_NAME" \
    --metadata-template-file-name=/tmp/metadata_template.json
  echo "Aspect type $ASPECT_TYPE_ID dibuat"
fi

# Apply aspect to each sensitive column via Dataplex entries
# Need to get the entry name for the BigQuery table in Data Catalog
ENTRY_NAME=$(gcloud data-catalog entries lookup \
  --project="$PROJECT_ID" \
  --linked-resource="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET/tables/$TABLE" \
  --format="value(name)" 2>/dev/null || echo "")

if [[ -n "$ENTRY_NAME" ]]; then
  echo "Table entry ditemukan: $ENTRY_NAME"
  
  # For each sensitive column, we need to apply aspect at column level
  # Dataplex entries can have child entries for columns
  for col in "${SENSITIVE_COLUMNS[@]}"; do
    # Look up column entry
    COL_ENTRY=$(gcloud data-catalog entries lookup \
      --project="$PROJECT_ID" \
      --linked-resource="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET/tables/$TABLE/columns/$col" \
      --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$COL_ENTRY" ]]; then
      echo "Column entry ditemukan untuk $col: $COL_ENTRY"
      
      cat > /tmp/aspect_data.json <<EOF
{
  "aspects": {
    "$ASPECT_TYPE_ID": {
      "has_sensitive_data": true
    }
  }
}
EOF
      gcloud dataplex entries update "$COL_ENTRY" \
        --project="$PROJECT_ID" \
        --location="$MULTI_REGION" \
        --aspects-file=/tmp/aspect_data.json \
        --quiet
      echo "Aspect diterapkan ke kolom $col"
    else
      echo "WARNING: Column entry untuk $col tidak ditemukan"
    fi
  done
else
  echo "WARNING: Table entry tidak ditemukan"
fi

step "Task 3: Remove IAM permissions to Cloud Storage for user 2"

# Get current IAM bindings for the user on storage roles
echo "Mencari IAM bindings untuk $USER_TO_REMOVE..."

# List all storage-related roles for this user
STORAGE_ROLES=(
  "roles/storage.admin"
  "roles/storage.objectAdmin"
  "roles/storage.objectCreator"
  "roles/storage.objectViewer"
  "roles/storage.legacyBucketReader"
  "roles/storage.legacyBucketWriter"
  "roles/storage.legacyObjectReader"
  "roles/storage.legacyObjectOwner"
)

for role in "${STORAGE_ROLES[@]}"; do
  echo "Checking $role..."
  gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="user:$USER_TO_REMOVE" \
    --role="$role" \
    --condition=None \
    --quiet 2>/dev/null && echo "Removed $role dari $USER_TO_REMOVE" || echo "$role tidak ada atau sudah dihapus"
done

echo "Project Viewer role (roles/viewer) tidak dihapus sesuai instruksi"

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
gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" --location="$MULTI_REGION" --project="$PROJECT_ID" 2>/dev/null | head -15

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create a Lakehouse table using a Cloud Resource connection"
echo "  Task 2 - Create, apply, and verify an aspect on columns containing sensitive data"
echo "  Task 3 - Remove IAM permissions to Cloud Storage for other users"