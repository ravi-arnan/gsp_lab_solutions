#!/usr/bin/env bash
# GSP1281 - Enabling Sensitive Data Protection Discovery for Cloud Storage
#
#   bash gsp1281.sh
#
# Checkpoint:
#   Task 1 (10 pts)  - Create and schedule a discovery scan configuration
#   Task 2 (40 pts)  - Modify inspection template + create de-identify template
#   Task 3 (0 pts)   - Manual (Looker dashboard)
#   Task 4 (25 pts)  - Create and run an inspection job
#   Task 5 (25 pts)  - Create and run a de-identify job

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }
INPUT_BUCKET="${PROJECT_ID}-input"
OUTPUT_BUCKET="${PROJECT_ID}-output"

API="https://dlp.googleapis.com/v2"
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
CT="Content-Type: application/json"
PARENT="projects/${PROJECT_ID}/locations/global"

post()  { curl -s -X POST "$1" -H "$AUTH" -H "$CT" -d "$2"; }
get()   { curl -s "$1" -H "$AUTH"; }
patch() { curl -s -X PATCH "$1" -H "$AUTH" -H "$CT" -d "$2"; }

echo "Project : $PROJECT_ID"
echo "Input   : gs://$INPUT_BUCKET/"
echo "Output  : gs://$OUTPUT_BUCKET/"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ── Enable APIs & BigQuery datasets ──
step "Enable APIs"
gcloud services enable dlp.googleapis.com bigquery.googleapis.com --project="$PROJECT_ID" -q 2>/dev/null || true

step "BigQuery datasets"
for ds in cloudstorage_discovery cloudstorage_inspection cloudstorage_transformations; do
  bq mk --dataset --if_not_exists --project_id="$PROJECT_ID" --location=US "$PROJECT_ID:$ds" 2>/dev/null || true
done

# ══════════════════════════════════════════════════════════════
# TASK 1 – Discovery scan configuration (10 pts)
# ══════════════════════════════════════════════════════════════
step "Task 1: Buat inspection template + discovery config"

# Buat inspection template default — dependency discovery config
INSPECT_RESULT=$(post "$API/$PARENT/inspectTemplates" "$(cat <<EOJSON
{
  "display_name": "Default Inspection Template",
  "inspect_config": {
    "info_types": [
      {"name":"US_SOCIAL_SECURITY_NUMBER"},{"name":"EMAIL_ADDRESS"},
      {"name":"PHONE_NUMBER"},{"name":"DATE_OF_BIRTH"},
      {"name":"CREDIT_CARD_NUMBER"},{"name":"US_PASSPORT"},
      {"name":"US_DRIVERS_LICENSE_NUMBER"},{"name":"PERSON_NAME"},
      {"name":"IP_ADDRESS"},{"name":"URL"},{"name":"US_DEA_NUMBER"},
      {"name":"CREDIT_SCORE"},{"name":"US_HEALTH_INSURANCE_CCPA"},
      {"name":"MEDICAL_TERM"},{"name":"US_BANK_ROUTING_MICR"}
    ],
    "min_likelihood": "POSSIBLE",
    "limits": {"max_findings_per_request": 0}
  }
}
EOJSON
)")
INSPECT_TPL_NAME=$(echo "$INSPECT_RESULT" | jq -r '.name // empty')
INSPECT_TPL_ID=$(echo "$INSPECT_TPL_NAME" | awk -F'/' '{print $NF}')
echo "Inspection template: $INSPECT_TPL_ID"

# Buat discovery config — ini yang di-score Task 1
DISC_RESULT=$(post "$API/$PARENT/discoveryConfigs" "$(cat <<EOJSON
{
  "display_name": "Cloud Storage Discovery",
  "status": "RUNNING",
  "targets": [{
    "cloud_storage_discovery": {
      "filter": { "others": {} }
    }
  }],
  "inspect_templates": [
    "${PARENT}/inspect_templates/${INSPECT_TPL_ID}"
  ],
  "actions": [
    {
      "export_data": {
        "profile_table": {
          "project_id": "${PROJECT_ID}",
          "dataset_id": "cloudstorage_discovery",
          "table_id": "data_profiles"
        }
      }
    },
    { "publish_to_scc": {} }
  ]
}
EOJSON
)")

DISC_NAME=$(echo "$DISC_RESULT" | jq -r '.name // empty')
if [ -n "$DISC_NAME" ]; then
  echo "Discovery config: $DISC_NAME"
else
  echo "WARNING:"
  echo "$DISC_RESULT" | jq . 2>/dev/null || echo "$DISC_RESULT"
fi

# ══════════════════════════════════════════════════════════════
# TASK 2 – Templates (40 pts)
# ══════════════════════════════════════════════════════════════
step "Task 2a: Modifikasi inspection template → US SSN only"

patch "$API/${INSPECT_TPL_NAME}?updateMask=display_name,description,inspect_config" "$(cat <<EOJSON
{
  "display_name": "Inspection Template for US SSN",
  "description": "This template was created as part of a Sensitive Data Protection profiler configuration and was modified for deeper inspection for US Social Security numbers.",
  "inspect_config": {
    "info_types": [{"name": "US_SOCIAL_SECURITY_NUMBER"}],
    "min_likelihood": "UNLIKELY",
    "include_quote": true,
    "limits": {"max_findings_per_request": 0}
  }
}
EOJSON
)" | jq -r '.display_name' 2>/dev/null && echo "Template diupdate."

step "Task 2b: Buat de-identify template (ID: us_ssn_deidentify)"

DEID_RESULT=$(post "$API/$PARENT/deidentifyTemplates" "$(cat <<EOJSON
{
  "template_id": "us_ssn_deidentify",
  "display_name": "De-identification Template for US SSN",
  "deidentify_config": {
    "record_transformations": {
      "field_transformations": [
        {
          "fields": [{"name": "ssn"}, {"name": "email"}],
          "primitive_transformation": {
            "replace_config": {
              "new_value": {"string_value": "[redacted]"}
            }
          }
        },
        {
          "fields": [{"name": "message"}],
          "info_type_transformations": {
            "transformations": [{
              "info_types": [],
              "primitive_transformation": {
                "replace_with_info_type_config": {}
              }
            }]
          }
        }
      ]
    }
  }
}
EOJSON
)")

DEID_TPL_NAME=$(echo "$DEID_RESULT" | jq -r '.name // empty')
echo "De-identify template: $DEID_TPL_NAME"

# ══════════════════════════════════════════════════════════════
# TASK 4 – Inspection job (25 pts)
# ══════════════════════════════════════════════════════════════
step "Task 4: Inspection job (US SSN, TEXT+CSV)"

INSPECT_JOB=$(post "$API/$PARENT/dlpJobs" "$(cat <<EOJ
{
  "inspect_job": {
    "inspect_config": {
      "info_types": [{"name": "US_SOCIAL_SECURITY_NUMBER"}],
      "min_likelihood": "UNLIKELY",
      "include_quote": true,
      "limits": {"max_findings_per_request": 0}
    },
    "storage_config": {
      "google_cloud_storage": {
        "file_set": {"url": "gs://${INPUT_BUCKET}/"},
        "files_limit": {"max_files": 0, "file_types": ["TEXT_FILE", "CSV"]}
      }
    },
    "actions": [{
      "save_findings": {
        "output_config": {
          "table": {
            "project_id": "${PROJECT_ID}",
            "dataset_id": "cloudstorage_inspection",
            "table_id": "us_ssn"
          }
        }
      }
    }]
  }
}
EOJ
)")

INSPECT_JOB_NAME=$(echo "$INSPECT_JOB" | jq -r '.name // empty')
echo "Job: $INSPECT_JOB_NAME"

if [ -n "$INSPECT_JOB_NAME" ]; then
  echo "Menunggu selesai..."
  while true; do
    ST=$(get "$INSPECT_JOB_NAME" | jq -r '.state')
    echo "  -> $ST"
    [[ "$ST" == "DONE" ]] && break
    [[ "$ST" == "FAILED" || "$ST" == "CANCELED" ]] && { echo "ABORTED: $ST"; break; }
    sleep 15
  done
else
  echo "ERROR:"; echo "$INSPECT_JOB" | jq . 2>/dev/null || echo "$INSPECT_JOB"
fi

# ══════════════════════════════════════════════════════════════
# TASK 5 – De-identify job (25 pts)
# ══════════════════════════════════════════════════════════════
step "Task 5: De-identify job (template: us_ssn_deidentify, exclude ignore/)"

DEID_JOB=$(post "$API/$PARENT/dlpJobs" "$(cat <<EOJ
{
  "inspect_job": {
    "inspect_config": {
      "info_types": [
        {"name":"US_SOCIAL_SECURITY_NUMBER"},{"name":"EMAIL_ADDRESS"},
        {"name":"PHONE_NUMBER"},{"name":"DATE_OF_BIRTH"},
        {"name":"PERSON_NAME"}
      ],
      "min_likelihood": "POSSIBLE",
      "limits": {"max_findings_per_request": 0}
    },
    "storage_config": {
      "google_cloud_storage": {
        "file_set": {"url": "gs://${INPUT_BUCKET}/"},
        "files_limit": {"max_files": 0, "file_types": ["TEXT_FILE", "CSV"]}
      }
    },
    "actions": [{
      "deidentify": {
        "cloud_storage_output": "gs://${OUTPUT_BUCKET}",
        "file_types_to_transform": ["TEXT_FILE", "CSV"],
        "transformation_details_storage_config": {
          "table": {
            "project_id": "${PROJECT_ID}",
            "dataset_id": "cloudstorage_transformations",
            "table_id": "deidentify_ssn_csv"
          }
        }
      }
    }]
  }
}
EOJ
)")

DEID_JOB_NAME=$(echo "$DEID_JOB" | jq -r '.name // empty')
echo "Job: $DEID_JOB_NAME"

if [ -n "$DEID_JOB_NAME" ]; then
  echo "Menunggu selesai..."
  while true; do
    ST=$(get "$DEID_JOB_NAME" | jq -r '.state')
    echo "  -> $ST"
    [[ "$ST" == "DONE" ]] && break
    [[ "$ST" == "FAILED" || "$ST" == "CANCELED" ]] && { echo "ABORTED: $ST"; break; }
    sleep 15
  done
else
  echo "ERROR:"; echo "$DEID_JOB" | jq . 2>/dev/null || echo "$DEID_JOB"
fi

# ══════════════════════════════════════════════════════════════
step "SELESAI — Klik Check my progress untuk Task 1, 2, 4, 5"
