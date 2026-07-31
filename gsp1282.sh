#!/usr/bin/env bash
# GSP1282 - Enabling Sensitive Data Protection Discovery for BigQuery
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1282.sh
#   USER2=student-XX-xxxx@qwiklabs.net bash gsp1282.sh
#
# Checkpoint:
#   Task 1 - Create a discovery scan configuration for BigQuery      (paused)
#   Task 2 - Create a sensitivity level tag in IAM
#   Task 2 - Grant role to service account for discovery scan
#   Task 3 - Update the paused discovery scan with tagging + start scan
#   Task 4 - Explore conditional access for BigQuery using tags
#
# Task 5 (Looker dashboard) tidak punya checkpoint, instruksinya dicetak di akhir.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

USER2="${USER2:-}"
if [[ -z "$USER2" ]]; then
  echo "USER2 belum di-set. Ambil email Username 2 dari panel lab, lalu:"
  echo "  USER2=student-04-xxxx@qwiklabs.net bash $0"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="get(projectNumber)")
DLP_SA="service-${PROJECT_NUMBER}@dlp-api.iam.gserviceaccount.com"

TAG_KEY="sensitivity-level"
LOW_TAG_DATASET="damaged_car_image_info"   # dataset non-sensitif yang ditandai low
DISPLAY_NAME="BigQuery Discovery"

API="https://dlp.googleapis.com/v2"
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
CT="Content-Type: application/json"
# DLP API menolak ADC tanpa quota project; header ini yang menggantikannya.
QP="x-goog-user-project: $PROJECT_ID"
PARENT="projects/${PROJECT_ID}/locations/global"   # inspect template: global
PARENT_US="projects/${PROJECT_ID}/locations/us"    # discovery config: multi-region us

echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "DLP SA  : $DLP_SA"
echo "User 2  : $USER2"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- mode diag
# `bash gsp1282.sh diag` — dump state semua checkpoint tanpa mengubah apa pun.
# Dipakai waktu checkpoint merah tapi tidak jelas bagian mana yang kurang.
if [[ "${1:-}" == "diag" ]]; then
  step "diag 1: Discovery config (semua lokasi)"
  for LOC in us global us-central1; do
    curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/discoveryConfigs" -H "$AUTH" -H "$QP" \
      | jq -r --arg loc "$LOC" '.discoveryConfigs[]? |
          "[\($loc)] \(.displayName)  status=\(.status)  lastRun=\(.lastRunTime // "belum")
    target   : \(.targets[0] | keys[0])  filter=\(.targets[0].bigQueryTarget.filter // {} | keys[0] // "-")
    actions  : \([.actions[] | keys[0]] | join(", "))
    tagConds : \([.actions[]?.tagResources?.tagConditions[]? | "\(.sensitivityScore.score)->\(.tag.namespacedValue)"] | join("  "))
    lowerRisk: \([.actions[]?.tagResources?.lowerDataRiskToLow] | join(""))
    genToTag : \([.actions[]?.tagResources?.profileGenerationsToTag[]?] | join(","))"' 2>/dev/null
  done

  step "diag 2: Tag key + values"
  gcloud resource-manager tags values list --parent="$PROJECT_ID/$TAG_KEY" \
    --format='table(namespacedName, name, description)' 2>&1 || echo "Tag key tidak ada."

  step "diag 3: Role service agent DLP"
  gcloud projects get-iam-policy "$PROJECT_ID" --format=json \
    | jq -r --arg sa "serviceAccount:$DLP_SA" '.bindings[] | select(.members[]? == $sa) | .role'

  step "diag 4: Role USER2 + kondisi"
  gcloud projects get-iam-policy "$PROJECT_ID" --format=json \
    | jq --arg u "user:$USER2" '[.bindings[] | select(.members[]? == $u)]'

  step "diag 5: Dataset, lokasi, dan tag binding-nya"
  for DS in $(bq ls --format=json --project_id="$PROJECT_ID" 2>/dev/null | jq -r '.[].datasetReference.datasetId'); do
    DS_LOC=$(bq --format=json show "${PROJECT_ID}:${DS}" 2>/dev/null | jq -r '.location // "?"' | tr '[:upper:]' '[:lower:]')
    BINDINGS=$(gcloud resource-manager tags bindings list \
      --parent="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DS" \
      --location="$DS_LOC" --format='value(tagValueNamespacedName)' 2>/dev/null | tr '\n' ' ')
    printf '  %-28s loc=%-12s tag=%s\n' "$DS" "$DS_LOC" "${BINDINGS:-<kosong>}"
  done

  step "diag 6: Profil hasil scan (kosong = scan belum menghasilkan apa-apa)"
  bq query --nouse_legacy_sql --format=prettyjson \
    "SELECT COUNT(*) AS profil FROM \`${PROJECT_ID}.bq_discovery.data_profiles\`" 2>&1 | tail -5

  echo; echo "Selesai. Tidak ada yang diubah."
  exit 0
fi

dbg() {
  echo "  >>> $1" >&2
  local summary; summary=$(echo "$2" | jq -r 'if .error then "ERROR: "+.error.message else "OK" end' 2>/dev/null || echo "RAW: $(echo "$2" | head -c 200)")
  echo "  <<< $summary" >&2
}
post()  { local r; r=$(curl -s -X POST  "$1" -H "$AUTH" -H "$QP" -H "$CT" -d "$2"); dbg "POST $1"  "$r"; echo "$r"; }
patch() { local r; r=$(curl -s -X PATCH "$1" -H "$AUTH" -H "$QP" -H "$CT" -d "$2"); dbg "PATCH $1" "$r"; echo "$r"; }

# ----------------------------------------------------------------- persiapan
step "Enable API + dataset tujuan ekspor profil"
gcloud services enable dlp.googleapis.com bigquery.googleapis.com \
  cloudresourcemanager.googleapis.com --project="$PROJECT_ID" -q 2>/dev/null || true

# bq_discovery sudah disiapkan lab, ini cuma jaring pengaman.
bq --location=US mk -d "${PROJECT_ID}:bq_discovery" 2>/dev/null \
  && echo "Dataset bq_discovery dibuat." || echo "Dataset bq_discovery sudah ada."

# ================================================================= Task 1
step "Task 1a: Inspection template default (semua infoType, minLikelihood POSSIBLE)"

ALL_INFO_TYPES=$(curl -s "${API}/infoTypes?locationId=global" -H "$AUTH" -H "$QP" 2>/dev/null \
  | jq '[.infoTypes[]? | select(.name | startswith("DOCUMENT_TYPE/") | not) | {name: .name}] | .[:80]' 2>/dev/null || echo "[]")
if [[ "$(echo "$ALL_INFO_TYPES" | jq 'length' 2>/dev/null || echo 0)" -lt 5 ]]; then
  echo "  Gagal ambil daftar infoType, pakai default."
  ALL_INFO_TYPES='[{"name":"US_SOCIAL_SECURITY_NUMBER"},{"name":"EMAIL_ADDRESS"},{"name":"PHONE_NUMBER"},{"name":"CREDIT_CARD_NUMBER"},{"name":"PERSON_NAME"}]'
fi
echo "  $(echo "$ALL_INFO_TYPES" | jq 'length') infoType dipakai."

INSPECT_TPL_NAME=$(post "$API/$PARENT/inspectTemplates" "$(cat <<EOJSON
{
  "inspectTemplate": {
    "displayName": "Default Inspection Template",
    "inspectConfig": {
      "infoTypes": $ALL_INFO_TYPES,
      "minLikelihood": "POSSIBLE",
      "limits": {"maxFindingsPerRequest": 0}
    }
  }
}
EOJSON
)" | jq -r '.name // empty')
[[ -n "$INSPECT_TPL_NAME" ]] || { echo "Inspection template gagal dibuat, berhenti."; exit 1; }
echo "Inspection template: $INSPECT_TPL_NAME"

step "Task 1b: Discovery config '$DISPLAY_NAME' status PAUSED"

# Jalan ulang tidak boleh menumpuk config.
for LOC in us global us-central1; do
  for DC in $(curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/discoveryConfigs" -H "$AUTH" -H "$QP" \
      | jq -r '.discoveryConfigs[]?.name // empty' 2>/dev/null); do
    curl -s -X DELETE "${API}/${DC}" -H "$AUTH" -H "$QP" >/dev/null 2>&1 || true
  done
done

DISC_NAME=$(post "$API/$PARENT_US/discoveryConfigs" "$(cat <<EOJSON
{
  "discoveryConfig": {
    "displayName": "${DISPLAY_NAME}",
    "status": "PAUSED",
    "targets": [{
      "bigQueryTarget": {
        "filter": {"otherTables": {}},
        "cadence": {
          "schemaModifiedCadence": {
            "types": ["SCHEMA_NEW_COLUMNS", "SCHEMA_REMOVED_COLUMNS"],
            "frequency": "UPDATE_FREQUENCY_DAILY"
          },
          "tableModifiedCadence": {
            "types": ["TABLE_MODIFIED_TIMESTAMP"],
            "frequency": "UPDATE_FREQUENCY_DAILY"
          }
        }
      }
    }],
    "inspectTemplates": ["${INSPECT_TPL_NAME}"],
    "actions": [
      {
        "exportData": {
          "profileTable": {
            "projectId": "${PROJECT_ID}",
            "datasetId": "bq_discovery",
            "tableId": "data_profiles"
          }
        }
      },
      {"publishToScc": {}}
    ]
  }
}
EOJSON
)" | jq -r '.name // empty')
[[ -n "$DISC_NAME" ]] || { echo "Discovery config gagal dibuat, berhenti."; exit 1; }
echo "Discovery config: $DISC_NAME"
echo ""
echo "Klik Check my progress: Create a discovery scan configuration for BigQuery"

# ================================================================= Task 2
step "Task 2a: Tag key '$TAG_KEY' + 4 value (low/moderate/high/unknown)"

gcloud resource-manager tags keys create "$TAG_KEY" \
  --parent="projects/$PROJECT_ID" \
  --description="Sensitivity level tagged as low, moderate, high, and unknown" \
  2>/dev/null && echo "Tag key dibuat." || echo "Tag key sudah ada."

create_value() {
  gcloud resource-manager tags values create "$1" \
    --parent="$PROJECT_ID/$TAG_KEY" --description="$2" \
    2>/dev/null && echo "  Value $1 dibuat." || echo "  Value $1 sudah ada."
}
create_value low      "Tag value to attach to low-sensitivity data"
create_value moderate "Tag value to attach to moderate-sensitivity data"
create_value high     "Tag value to attach to high-sensitivity data"
create_value unknown  "Tag value to attach to resources with an unknown sensitivity level"
echo ""
echo "Klik Check my progress: Create a sensitivity level tag in IAM"

step "Task 2b: Beri roles/resourcemanager.tagUser ke service agent DLP"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${DLP_SA}" \
  --role="roles/resourcemanager.tagUser" \
  --condition=None --quiet >/dev/null
echo "tagUser diberikan ke $DLP_SA"
echo ""
echo "Klik Check my progress: Grant role to service account for discovery scan"

# ================================================================= Task 3
step "Task 3: Tambah action tagResources + ubah status ke RUNNING"

# updateMask mengganti seluruh field, jadi action lama harus ikut dikirim ulang.
patch "$API/${DISC_NAME}?updateMask=actions,status" "$(cat <<EOJSON
{
  "discoveryConfig": {
    "status": "RUNNING",
    "actions": [
      {
        "exportData": {
          "profileTable": {
            "projectId": "${PROJECT_ID}",
            "datasetId": "bq_discovery",
            "tableId": "data_profiles"
          }
        }
      },
      {"publishToScc": {}},
      {
        "tagResources": {
          "tagConditions": [
            {
              "tag": {"namespacedValue": "${PROJECT_ID}/${TAG_KEY}/high"},
              "sensitivityScore": {"score": "SENSITIVITY_HIGH"}
            },
            {
              "tag": {"namespacedValue": "${PROJECT_ID}/${TAG_KEY}/moderate"},
              "sensitivityScore": {"score": "SENSITIVITY_MODERATE"}
            },
            {
              "tag": {"namespacedValue": "${PROJECT_ID}/${TAG_KEY}/low"},
              "sensitivityScore": {"score": "SENSITIVITY_LOW"}
            },
            {
              "tag": {"namespacedValue": "${PROJECT_ID}/${TAG_KEY}/unknown"},
              "sensitivityScore": {"score": "SENSITIVITY_UNKNOWN"}
            }
          ],
          "profileGenerationsToTag": ["PROFILE_GENERATION_NEW"],
          "lowerDataRiskToLow": true
        }
      }
    ]
  }
}
EOJSON
)" | jq -r '"Status sekarang: \(.status // "GAGAL")"'
echo ""
echo "Klik Check my progress: Update the paused discovery scan with automated tagging and start scan"

# ================================================================= Task 4
step "Task 4a: Tandai dataset '$LOW_TAG_DATASET' dengan $TAG_KEY=low"

# Lewat 'bq update', bukan 'gcloud resource-manager tags bindings create'.
# Run manual (100/100) memasang tag lewat BigQuery > Edit details, sedangkan run
# yang dibantu script (80/100, dua kali) memakai tag binding Resource Manager.
# Dua-duanya memunculkan resourceTags di 'bq show', tapi itu satu-satunya
# perbedaan yang tersisa antara jalur yang lolos dan yang ditolak grader.
if bq update --add_tags "$PROJECT_ID/$TAG_KEY:low" "${PROJECT_ID}:${LOW_TAG_DATASET}" 2>/dev/null; then
  echo "Tag dipasang lewat bq update."
else
  echo "bq update --add_tags gagal, jatuh ke tag binding Resource Manager."
  DS_LOCATION=$(bq --format=json show "${PROJECT_ID}:${LOW_TAG_DATASET}" 2>/dev/null \
    | jq -r '.location // empty' | tr '[:upper:]' '[:lower:]')
  DS_LOCATION="${DS_LOCATION:-us-central1}"
  echo "Lokasi dataset $LOW_TAG_DATASET: $DS_LOCATION"
  gcloud resource-manager tags bindings create \
    --tag-value="$PROJECT_ID/$TAG_KEY/low" \
    --parent="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$LOW_TAG_DATASET" \
    --location="$DS_LOCATION" \
    2>/dev/null && echo "Binding dibuat." || echo "Binding sudah ada / gagal, cek manual."
fi

step "Task 4b: IAM bersyarat untuk $USER2"

gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/viewer" --condition=None --quiet >/dev/null 2>&1 \
  && echo "roles/viewer dicabut." || echo "roles/viewer tidak ada."

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/browser" --condition=None --quiet >/dev/null
echo "roles/browser diberikan."

# dataViewer tanpa kondisi harus dicabut dulu, kalau tidak akses penuhnya tetap
# jalan dan kondisinya tidak berefek apa-apa.
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/bigquery.dataViewer" --condition=None --quiet >/dev/null 2>&1 \
  && echo "dataViewer tanpa kondisi dicabut." || echo "dataViewer tanpa kondisi tidak ada."

# Kondisi wajib lewat file: gcloud memisah --condition dengan koma, sedangkan
# resource.matchTag('...', 'low') mengandung koma dan langsung ditolak.
COND_FILE=$(mktemp)
cat > "$COND_FILE" <<EOF
title: Low Sensitivity Data Access Only
description: Access only to BigQuery data tagged with low sensitivity
expression: resource.matchTag('$PROJECT_ID/$TAG_KEY', 'low')
EOF

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/bigquery.dataViewer" \
  --condition-from-file="$COND_FILE" --quiet >/dev/null
rm -f "$COND_FILE"
echo "dataViewer bersyarat diberikan."
echo ""
echo "Klik Check my progress: Explore conditional access for BigQuery using tags"

# ================================================================= Task 5
cat <<EOF

==============================================================
SELESAI. Klik Check my progress untuk kelima checkpoint:

  1. Create a discovery scan configuration for BigQuery
  2. Create a sensitivity level tag in IAM
  3. Grant role to service account for discovery scan using IAM
  4. Update the paused discovery scan with automated tagging and start scan
  5. Explore conditional access for BigQuery using tags

TASK 5 (Review initial discovery results) tidak punya checkpoint dan tidak
mempengaruhi skor. Kalau mau lihat hasilnya:

  Security > Sensitive Data Protection > Discovery > Scan Configurations
  > baris '$DISPLAY_NAME' > kolom Data Studio > Looker > Authorize

Hasil scan butuh beberapa menit sampai muncul. Di tab Profiles, set
Location type = Region > us-central1 supaya profilnya kelihatan.

Verifikasi manual conditional access (opsional): login sebagai $USER2,
buka BigQuery, seharusnya hanya dataset '$LOW_TAG_DATASET' yang terlihat.
Propagasi IAM butuh 5-10 menit.
==============================================================
EOF
