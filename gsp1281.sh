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
DC_LOC="us"
PARENT_DC="projects/${PROJECT_ID}/locations/${DC_LOC}"

dbg() {
  echo "  >>> $1" >&2
  local summary; summary=$(echo "$2" | jq -r 'if .error then "ERROR: "+.error.message else "OK" end' 2>/dev/null || echo "RAW: $(echo "$2" | head -c 200)")
  echo "  <<< $summary" >&2
}

post()  { local r; r=$(curl -s -X POST "$1" -H "$AUTH" -H "$CT" -d "$2"); dbg "POST $1" "$r"; echo "$r"; }
get()   { local r; r=$(curl -s "${API}/$1" -H "$AUTH"); dbg "GET ${API}/$1" "$r"; echo "$r"; }
patch() { local r; r=$(curl -s -X PATCH "$1" -H "$AUTH" -H "$CT" -d "$2"); dbg "PATCH $1" "$r"; echo "$r"; }

echo "Project : $PROJECT_ID"
echo "Input   : gs://$INPUT_BUCKET/"
echo "Output  : gs://$OUTPUT_BUCKET/"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ── Enable APIs & BigQuery datasets ──
step "Enable APIs"
gcloud services enable dlp.googleapis.com bigquery.googleapis.com --project="$PROJECT_ID" -q 2>/dev/null || true

# Cleanup previous job runs (idempotent, suppress errors)
for job_id in i-us_ssn_inspection i-us_ssn_deidentify; do
  curl -s -X DELETE "${API}/${PARENT}/dlpJobs/${job_id}" -H "$AUTH" > /dev/null 2>&1 || true
done
# List & delete existing discovery configs from any location
for loc in global us-central1 us; do
  EXISTING_DC=$(curl -s "${API}/projects/${PROJECT_ID}/locations/${loc}/discoveryConfigs" -H "$AUTH" | jq -r '.discoveryConfigs[0].name // empty' 2>/dev/null)
  if [ -n "$EXISTING_DC" ]; then
    curl -s -X DELETE "${API}/${EXISTING_DC}" -H "$AUTH" > /dev/null 2>&1 || true
  fi
done

step "BigQuery datasets"
for ds in cloudstorage_discovery cloudstorage_inspection cloudstorage_transformations; do
  bq mk --dataset --if_not_exists --project_id="$PROJECT_ID" --location=US "$PROJECT_ID:$ds" 2>/dev/null || true
done

# ══════════════════════════════════════════════════════════════
# TASK 1 – Discovery scan configuration (10 pts)
# ══════════════════════════════════════════════════════════════
step "Task 1: Buat inspection template + discovery config"

INSPECT_RESULT=$(post "$API/$PARENT_DC/inspectTemplates" "$(cat <<EOJSON
{
  "inspectTemplate": {
    "displayName": "Default Inspection Template",
    "inspectConfig": {
      "infoTypes": [
        {"name":"US_SOCIAL_SECURITY_NUMBER"},{"name":"EMAIL_ADDRESS"},
        {"name":"PHONE_NUMBER"},{"name":"CREDIT_CARD_NUMBER"},
        {"name":"PERSON_NAME"},{"name":"STREET_ADDRESS"},
        {"name":"DATE_OF_BIRTH"},{"name":"US_BANK_ROUTING_MICR"},
        {"name":"US_BANK_ACCOUNT_NUMBER"},{"name":"US_INDIVIDUAL_TAXPAYER_IDENTIFICATION_NUMBER"},
        {"name":"US_PASSPORT"},{"name":"US_DRIVERS_LICENSE"},
        {"name":"IP_ADDRESS"},{"name":"MAC_ADDRESS"},{"name":"URL"},
        {"name":"PASSWORD"},{"name":"USERNAME"},
        {"name":"VEHICLE_IDENTIFICATION_NUMBER"}
      ],
      "minLikelihood": "POSSIBLE"
    }
  }
}
EOJSON
)")
INSPECT_TPL_NAME=$(echo "$INSPECT_RESULT" | jq -r '.name // empty')
INSPECT_TPL_ID=$(echo "$INSPECT_TPL_NAME" | awk -F'/' '{print $NF}')
echo "Inspection template: $INSPECT_TPL_ID"

DISC_RESULT=$(post "$API/$PARENT_DC/discoveryConfigs" "$(cat <<EOJSON
{
  "discoveryConfig": {
    "displayName": "Cloud Storage Discovery",
    "status": "RUNNING",
    "targets": [{
      "cloudStorageTarget": {
        "filter": { "others": {} },
        "generationCadence": {
          "refreshFrequency": "UPDATE_FREQUENCY_DAILY"
        }
      }
    }],
    "inspectTemplates": [
      "${PARENT_DC}/inspectTemplates/${INSPECT_TPL_ID}"
    ],
    "actions": [
      {
        "exportData": {
          "profileTable": {
            "projectId": "${PROJECT_ID}",
            "datasetId": "cloudstorage_discovery",
            "tableId": "data_profiles"
          }
        }
      },
      { "publishToScc": {} }
    ]
  }
}
EOJSON
)")

DISC_NAME=$(echo "$DISC_RESULT" | jq -r '.name // empty')
if [ -n "$DISC_NAME" ]; then
  echo ">> DISCOVERY CONFIG CREATED: $DISC_NAME"
else
  echo ">> DISCOVERY CONFIG FAILED (see [DEBUG] above)"
fi

# ══════════════════════════════════════════════════════════════
# TASK 2 – Templates (40 pts)
# ══════════════════════════════════════════════════════════════
step "Task 2a: Modifikasi inspection template → US SSN only"

patch "$API/${INSPECT_TPL_NAME}?updateMask=displayName,description,inspectConfig" "$(cat <<EOJSON
{
  "inspectTemplate": {
    "displayName": "Inspection Template for US SSN",
    "description": "This template was created as part of a Sensitive Data Protection profiler configuration and was modified for deeper inspection for US Social Security numbers.",
    "inspectConfig": {
      "infoTypes": [{"name": "US_SOCIAL_SECURITY_NUMBER"}],
      "minLikelihood": "UNLIKELY",
      "includeQuote": true,
      "limits": {"maxFindingsPerRequest": 0}
    }
  }
}
EOJSON
)" | jq -r '.displayName' 2>/dev/null && echo "Template diupdate."

step "Task 2b: Buat de-identify template (ID: us_ssn_deidentify)"

DEID_RESULT=$(post "$API/$PARENT/deidentifyTemplates" "$(cat <<EOJSON
{
  "deidentifyTemplate": {
    "displayName": "De-identification Template for US SSN",
    "deidentifyConfig": {
      "recordTransformations": {
        "fieldTransformations": [
          {
            "fields": [{"name": "ssn"}, {"name": "email"}],
            "primitiveTransformation": {
              "replaceConfig": {
                "newValue": {"stringValue": "[redacted]"}
              }
            }
          },
          {
            "fields": [{"name": "message"}],
            "infoTypeTransformations": {
              "transformations": [{
                "infoTypes": [],
                "primitiveTransformation": {
                  "replaceWithInfoTypeConfig": {}
                }
              }]
            }
          }
        ]
      }
    }
  },
  "templateId": "us_ssn_deidentify"
}
EOJSON
)")

DEID_TPL_NAME=$(echo "$DEID_RESULT" | jq -r '.name // empty')
# if already exists, use known path
if [ -z "$DEID_TPL_NAME" ]; then
  DEID_TPL_NAME="${PARENT}/deidentifyTemplates/us_ssn_deidentify"
fi
echo "De-identify template: $DEID_TPL_NAME"

# ══════════════════════════════════════════════════════════════
# TASK 4 – Inspection job (25 pts)
# ══════════════════════════════════════════════════════════════
step "Task 4: Inspection job (US SSN, TEXT+CSV)"

INSPECT_JOB=$(post "$API/$PARENT/dlpJobs" "$(cat <<EOJ
{
  "inspectJob": {
    "inspectTemplateName": "${PARENT_DC}/inspectTemplates/${INSPECT_TPL_ID}",
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {"url": "gs://${INPUT_BUCKET}/"},
        "fileTypes": ["TEXT_FILE", "CSV"]
      }
    },
    "actions": [
      {
        "saveFindings": {
          "outputConfig": {
            "table": {
              "projectId": "${PROJECT_ID}",
              "datasetId": "cloudstorage_inspection",
              "tableId": "us_ssn"
            }
          }
        }
      },
      { "publishSummaryToCscc": {} }
    ]
  },
  "jobId": "us_ssn_inspection"
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
  "inspectJob": {
    "inspectConfig": {
      "infoTypes": [
        {"name":"US_SOCIAL_SECURITY_NUMBER"},{"name":"EMAIL_ADDRESS"},
        {"name":"PHONE_NUMBER"},{"name":"DATE_OF_BIRTH"},
        {"name":"PERSON_NAME"}
      ],
      "minLikelihood": "POSSIBLE",
      "limits": {"maxFindingsPerRequest": 0}
    },
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {
          "regexFileSet": {
            "bucketName": "${INPUT_BUCKET}",
            "excludeRegex": ["ignore"]
          }
        },
        "fileTypes": ["TEXT_FILE", "CSV"]
      }
    },
    "actions": [{
      "deidentify": {
        "cloudStorageOutput": "gs://${OUTPUT_BUCKET}",
        "fileTypesToTransform": ["TEXT_FILE", "CSV"],
        "transformationConfig": {
          "structuredDeidentifyTemplate": "${PARENT}/deidentifyTemplates/us_ssn_deidentify"
        },
        "transformationDetailsStorageConfig": {
          "table": {
            "projectId": "${PROJECT_ID}",
            "datasetId": "cloudstorage_transformations",
            "tableId": "deidentify_ssn_csv"
          }
        }
      }
    }]
  },
  "jobId": "us_ssn_deidentify"
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
