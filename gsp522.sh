#!/usr/bin/env bash
# GSP522 - Discover and Protect Sensitive Data Across Your Ecosystem: Challenge Lab
#
#   USER2=student-XX-xxxx@qwiklabs.net bash gsp522.sh
#
# Checkpoint:
#   Task 1 - Enable sensitive data protection for Cloud Storage   (otomatis)
#   Task 2 - Enable sensitive data protection for BigQuery        (otomatis)
#   Task 3 - Protect sensitive data in Gen AI model responses     (MANUAL, notebook)
#
# Task 3 harus dikerjakan di notebook Workbench 'vertex-ai-jupyterlab'. Kode
# selnya dicetak di akhir script, tinggal tempel.
#
# LAMA: ~5-8 menit (de-identify job-nya yang paling lama).

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
#   ask <NAMA_VAR> <default> <pertanyaan>
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

ask REGION "us-east1" "Region (cocokkan dengan panel lab)"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

USER2="${USER2:-}"
if [[ -z "$USER2" && "${1:-}" != "diag" ]]; then
  echo "USER2 belum di-set. Ambil email Username 2 dari panel lab, lalu:"
  echo "  USER2=student-03-xxxx@qwiklabs.net bash $0"
  exit 1
fi

INPUT_BUCKET="${PROJECT_ID}-car-owners"
OUTPUT_BUCKET="${PROJECT_ID}-car-owners-transformed"

API="https://dlp.googleapis.com/v2"
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
CT="Content-Type: application/json"
# DLP API menolak ADC tanpa quota project; header ini yang menggantikannya.
QP="x-goog-user-project: $PROJECT_ID"
PARENT="projects/${PROJECT_ID}/locations/global"   # template: global
PARENT_US="projects/${PROJECT_ID}/locations/us"    # discovery + job: multi-region us

DEID_TPL_ID="us_ccn_deidentify"
DEID_JOB_ID="us_ccn_deidentify"
TAG_KEY="SPII"

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Input   : gs://$INPUT_BUCKET/"
echo "Output  : gs://$OUTPUT_BUCKET/"
echo "User 2  : $USER2"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- mode diag
# `bash gsp522.sh diag` — dump state semua checkpoint tanpa mengubah apa pun.
# Dipakai waktu checkpoint merah tapi tidak jelas bagian mana yang kurang.
if [[ "${1:-}" == "diag" ]]; then
  step "diag 1: Inspect + de-identify template"
  for LOC in global us; do
    curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/inspectTemplates" -H "$AUTH" -H "$QP" \
      | jq -r --arg l "$LOC" '.inspectTemplates[]? |
          "[\($l)] INSPECT \(.name)
    displayName: \(.displayName)
    infoTypes  : \([.inspectConfig.infoTypes[]?.name] | join(", "))
    likelihood : \(.inspectConfig.minLikelihood // "-")"' 2>/dev/null
    curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/deidentifyTemplates" -H "$AUTH" -H "$QP" \
      | jq -r --arg l "$LOC" '.deidentifyTemplates[]? |
          "[\($l)] DEID    \(.name)
    displayName: \(.displayName)
    transform  : \(.deidentifyConfig | keys[0])
    fields     : \([.deidentifyConfig.recordTransformations.fieldTransformations[]?.fields[]?.name] | join(", "))"' 2>/dev/null
  done

  step "diag 2: Discovery config (semua lokasi)"
  for LOC in us global "$REGION"; do
    curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/discoveryConfigs" -H "$AUTH" -H "$QP" \
      | jq -r --arg l "$LOC" '.discoveryConfigs[]? |
          "[\($l)] \(.displayName)  status=\(.status)  lastRun=\(.lastRunTime // "belum")
    target  : \(.targets[0] | keys[0])
    cadence : \(.targets[0].cloudStorageTarget.generationCadence.refreshFrequency // "-")
    actions : \([.actions[] | keys[0]] | join(", "))
    inspect : \(.inspectTemplates // [] | join(", "))"' 2>/dev/null
  done

  step "diag 3: DLP job + state"
  for LOC in us global "$REGION"; do
    curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/dlpJobs" -H "$AUTH" -H "$QP" \
      | jq -r --arg l "$LOC" '.jobs[]? |
          "[\($l)] \(.name | split("/") | last)  state=\(.state)  type=\(.type)  err=\([.errors[]?.details.message] | join("; "))"' 2>/dev/null
  done

  step "diag 4: Isi bucket input dan output"
  echo "-- gs://$INPUT_BUCKET/"
  gcloud storage ls -r "gs://$INPUT_BUCKET/**" 2>&1 | head -10
  echo "-- gs://$OUTPUT_BUCKET/  (kosong = de-identify job belum menulis apa-apa)"
  gcloud storage ls -r "gs://$OUTPUT_BUCKET/**" 2>&1 | head -10

  step "diag 5: Tag key, value, dan binding dataset orders"
  gcloud resource-manager tags values list --parent="$PROJECT_ID/$TAG_KEY" \
    --format='table(namespacedName, description)' 2>&1 || echo "Tag key tidak ada."
  DS_LOC=$(bq --format=json show "${PROJECT_ID}:orders" 2>/dev/null | jq -r '.location // "?"' | tr '[:upper:]' '[:lower:]')
  echo "lokasi dataset orders: $DS_LOC"
  gcloud resource-manager tags bindings list \
    --parent="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/orders" \
    --location="$DS_LOC" --format='value(tagValueNamespacedName)' 2>&1

  step "diag 6: Role USER2 + kondisi"
  gcloud projects get-iam-policy "$PROJECT_ID" --format=json \
    | jq --arg u "user:${USER2:-<tidak-di-set>}" '[.bindings[] | select(.members[]? == $u)]'

  step "diag 7: Dataset dan tabel hasil"
  bq ls --format=pretty --project_id="$PROJECT_ID" 2>&1 | head -20
  bq ls --format=pretty "${PROJECT_ID}:cs_transformations" 2>&1 | head -10

  echo; echo "Selesai. Tidak ada yang diubah."
  exit 0
fi

# Error dicetak utuh; pesan ringkas sering menyembunyikan field mana yang ditolak.
dbg() {
  echo "  >>> $1" >&2
  if echo "$2" | jq -e '.error' >/dev/null 2>&1; then
    echo "  <<< ERROR:" >&2
    echo "$2" | jq '.error | {code, status, message, details}' >&2
  else
    echo "  <<< OK $(echo "$2" | jq -r '.name // "-"' 2>/dev/null)" >&2
  fi
}
post() { local r; r=$(curl -s -X POST "$1" -H "$AUTH" -H "$QP" -H "$CT" -d "$2"); dbg "POST $1" "$r"; echo "$r"; }
get()  { local r; r=$(curl -s "${API}/$1" -H "$AUTH" -H "$QP"); dbg "GET $1" "$r"; echo "$r"; }

# Batas polling wajib: kalau API balas error transien, .state jadi null dan
# loop tanpa batas menggantung Cloud Shell.
JOB_MAX_POLL="${JOB_MAX_POLL:-40}"   # 40 x 15s = 10 menit
wait_job() {
  local name=$1 st i
  for (( i = 1; i <= JOB_MAX_POLL; i++ )); do
    st=$(get "$name" | jq -r '.state // "UNKNOWN"')
    echo "  -> $st ($i/$JOB_MAX_POLL)"
    case "$st" in
      DONE)            return 0 ;;
      FAILED|CANCELED) echo "ABORTED: $st"; return 1 ;;
    esac
    sleep 15
  done
  echo "TIMEOUT: job belum DONE. Cek manual di Console."
  return 1
}

# ----------------------------------------------------------------- persiapan
step "Enable API + dataset BigQuery tujuan ekspor"
gcloud services enable dlp.googleapis.com bigquery.googleapis.com \
  cloudresourcemanager.googleapis.com --project="$PROJECT_ID" -q 2>/dev/null || true

for DS in cs_discovery cs_transformations; do
  bq --location=US mk -d "${PROJECT_ID}:${DS}" 2>/dev/null && echo "Dataset $DS dibuat." \
    || echo "Dataset $DS sudah ada."
done

# ================================================================= Task 1
step "Task 1a: Inspection template untuk discovery"

INSPECT_RESULT=$(post "$API/$PARENT/inspectTemplates" "$(cat <<EOJSON
{
  "inspectTemplate": {
    "displayName": "Default Inspection Template",
    "inspectConfig": {
      "infoTypes": [
        {"name": "CREDIT_CARD_NUMBER"},
        {"name": "US_SOCIAL_SECURITY_NUMBER"},
        {"name": "EMAIL_ADDRESS"},
        {"name": "PHONE_NUMBER"},
        {"name": "PERSON_NAME"}
      ],
      "minLikelihood": "POSSIBLE",
      "limits": {"maxFindingsPerRequest": 0}
    }
  }
}
EOJSON
)")
INSPECT_TPL_NAME=$(echo "$INSPECT_RESULT" | jq -r '.name // empty')
echo "Inspection template: ${INSPECT_TPL_NAME:-GAGAL}"

step "Task 1b: Discovery config harian untuk Cloud Storage"

# Hapus discovery config lama supaya jalan ulang tidak menumpuk config.
for LOC in us global "$REGION"; do
  EXISTING=$(curl -s "${API}/projects/${PROJECT_ID}/locations/${LOC}/discoveryConfigs" -H "$AUTH" -H "$QP" \
    | jq -r '.discoveryConfigs[]?.name // empty' 2>/dev/null)
  for DC in $EXISTING; do
    curl -s -X DELETE "${API}/${DC}" -H "$AUTH" -H "$QP" >/dev/null 2>&1 || true
  done
done

DISC_RESULT=$(post "$API/$PARENT_US/discoveryConfigs" "$(cat <<EOJSON
{
  "discoveryConfig": {
    "displayName": "Cloud Storage Daily Discovery",
    "status": "RUNNING",
    "targets": [{
      "cloudStorageTarget": {
        "filter": {"others": {}},
        "generationCadence": {
          "refreshFrequency": "UPDATE_FREQUENCY_DAILY",
          "inspectTemplateModifiedCadence": {
            "frequency": "UPDATE_FREQUENCY_DAILY"
          }
        }
      }
    }],
    "inspectTemplates": ["${INSPECT_TPL_NAME}"],
    "actions": [{
      "exportData": {
        "profileTable": {
          "projectId": "${PROJECT_ID}",
          "datasetId": "cs_discovery",
          "tableId": "cs_data_profiles"
        }
      }
    }]
  }
}
EOJSON
)")
echo "Discovery config: $(echo "$DISC_RESULT" | jq -r '.name // "GAGAL"')"

step "Task 1c: De-identify template '$DEID_TPL_ID' (field message, replace with infoType name)"

curl -s -X DELETE "$API/$PARENT/deidentifyTemplates/$DEID_TPL_ID" -H "$AUTH" -H "$QP" >/dev/null 2>&1 || true

DEID_TPL=$(post "$API/$PARENT/deidentifyTemplates" "$(cat <<EOJSON
{
  "deidentifyTemplate": {
    "displayName": "De-identify Credit Card Numbers",
    "deidentifyConfig": {
      "recordTransformations": {
        "fieldTransformations": [{
          "fields": [{"name": "message"}],
          "infoTypeTransformations": {
            "transformations": [{
              "infoTypes": [],
              "primitiveTransformation": {
                "replaceWithInfoTypeConfig": {}
              }
            }]
          }
        }]
      }
    }
  },
  "templateId": "${DEID_TPL_ID}"
}
EOJSON
)")
DEID_TPL_NAME=$(echo "$DEID_TPL" | jq -r '.name // empty')
[[ -n "$DEID_TPL_NAME" ]] || DEID_TPL_NAME="${PARENT}/deidentifyTemplates/${DEID_TPL_ID}"
echo "De-identify template: $DEID_TPL_NAME"

step "Task 1d: De-identify job '$DEID_JOB_ID' pada gs://$INPUT_BUCKET/"

# Job ID hanya boleh dipakai sekali; hapus sisa run sebelumnya.
for LOC in us global "$REGION"; do
  curl -s -X DELETE "${API}/projects/${PROJECT_ID}/locations/${LOC}/dlpJobs/i-${DEID_JOB_ID}" \
    -H "$AUTH" -H "$QP" >/dev/null 2>&1 || true
done

DEID_JOB=$(post "$API/$PARENT_US/dlpJobs" "$(cat <<EOJSON
{
  "inspectJob": {
    "inspectConfig": {
      "infoTypes": [{"name": "CREDIT_CARD_NUMBER"}],
      "minLikelihood": "POSSIBLE",
      "limits": {"maxFindingsPerRequest": 0}
    },
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {"url": "gs://${INPUT_BUCKET}/**"},
        "fileTypes": ["TEXT_FILE", "CSV"],
        "filesLimitPercent": 100,
        "sampleMethod": "SAMPLE_METHOD_UNSPECIFIED"
      }
    },
    "actions": [{
      "deidentify": {
        "cloudStorageOutput": "gs://${OUTPUT_BUCKET}",
        "fileTypesToTransform": ["TEXT_FILE", "CSV"],
        "transformationConfig": {
          "structuredDeidentifyTemplate": "${DEID_TPL_NAME}"
        },
        "transformationDetailsStorageConfig": {
          "table": {
            "projectId": "${PROJECT_ID}",
            "datasetId": "cs_transformations",
            "tableId": "deidentify_ccn"
          }
        }
      }
    }]
  },
  "jobId": "${DEID_JOB_ID}"
}
EOJSON
)")
DEID_JOB_NAME=$(echo "$DEID_JOB" | jq -r '.name // empty')
if [[ -n "$DEID_JOB_NAME" ]]; then
  echo "Job: $DEID_JOB_NAME"
  wait_job "$DEID_JOB_NAME" || true
else
  echo "Job GAGAL dibuat:"; echo "$DEID_JOB" | jq . 2>/dev/null || echo "$DEID_JOB"
fi

# ================================================================= Task 2
step "Task 2a: Tag key '$TAG_KEY' + value Yes/No"

gcloud resource-manager tags keys create "$TAG_KEY" \
  --parent="projects/$PROJECT_ID" \
  --description="Flag for sensitive personally identifiable information (SPII)" \
  2>/dev/null && echo "Tag key dibuat." || echo "Tag key sudah ada."

gcloud resource-manager tags values create Yes \
  --parent="$PROJECT_ID/$TAG_KEY" \
  --description="Contains sensitive personally identifiable information (SPII)" \
  2>/dev/null && echo "Value Yes dibuat." || echo "Value Yes sudah ada."

gcloud resource-manager tags values create No \
  --parent="$PROJECT_ID/$TAG_KEY" \
  --description="Does not contain sensitive personally identifiable information (SPII)" \
  2>/dev/null && echo "Value No dibuat." || echo "Value No sudah ada."

step "Task 2b: Tag dataset BigQuery 'orders' dengan SPII=No"

# Lokasi binding harus sama dengan lokasi dataset-nya.
DS_LOCATION=$(bq --format=json show "${PROJECT_ID}:orders" 2>/dev/null | jq -r '.location // empty' | tr '[:upper:]' '[:lower:]')
DS_LOCATION="${DS_LOCATION:-$REGION}"
echo "Lokasi dataset orders: $DS_LOCATION"

gcloud resource-manager tags bindings create \
  --tag-value="$PROJECT_ID/$TAG_KEY/No" \
  --parent="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/orders" \
  --location="$DS_LOCATION" \
  2>/dev/null && echo "Binding dibuat." || echo "Binding sudah ada / gagal, cek manual."

step "Task 2c: IAM bersyarat untuk $USER2"

# Viewer diganti Browser
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/viewer" --condition=None --quiet >/dev/null 2>&1 \
  && echo "roles/viewer dicabut." || echo "roles/viewer tidak ada."

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/browser" --condition=None --quiet >/dev/null
echo "roles/browser diberikan."

# Binding dataViewer tanpa kondisi harus dicabut dulu, kalau tidak akses penuhnya
# tetap jalan dan kondisinya tidak ada efek.
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/bigquery.dataViewer" --condition=None --quiet >/dev/null 2>&1 \
  && echo "dataViewer tanpa kondisi dicabut." || echo "dataViewer tanpa kondisi tidak ada."

# Kondisi wajib lewat file: gcloud memisah --condition dengan koma, sedangkan
# resource.matchTag('...', 'No') mengandung koma dan langsung ditolak.
cat > /tmp/gsp522-condition.yaml <<EOF
title: No SPII Access Only
description: Access only to datasets tagged SPII=No
expression: resource.matchTag('$PROJECT_ID/$TAG_KEY', 'No')
EOF

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$USER2" --role="roles/bigquery.dataViewer" \
  --condition-from-file=/tmp/gsp522-condition.yaml \
  --quiet >/dev/null
echo "dataViewer bersyarat diberikan."

# ================================================================= Task 3
cat <<EOF

==============================================================
Task 1 dan 2 selesai. Klik Check my progress untuk keduanya.

TASK 3 MANUAL — harus di notebook Workbench, tidak bisa dari Cloud Shell.

  Notebook memakai SDK google-genai (client = genai.Client(enterprise=True, ...),
  model = "gemini-3.5-flash"). Tidak ada 'GenerationConfig' di SDK ini —
  temperature masuk lewat argumen config.

  1. Vertex AI > Workbench > instance 'vertex-ai-jupyterlab' > Open JupyterLab
  2. Buka 'deidentify-model-response-challenge-lab.ipynb', jalankan sel setup
     sampai sel 'Import Gemini 3.5 Flash model'
  3. Di fungsi 'deidentify_with_replace_infotype', ganti blok setelah komentar
     '# Add conditional return ...' jadi (VIN ditambahkan, blocking source code
     bawaan dipertahankan):

        info_types = ["DOCUMENT_TYPE/R&D/SOURCE_CODE", "US_VEHICLE_IDENTIFICATION_NUMBER"]
        inspect_config = {"info_types": [{"name": t} for t in info_types]}

        response = dlp.inspect_content(request={
            "parent": parent, "inspect_config": inspect_config,
            "item": {"value": item},
        })

        if response.result.findings:
            for finding in response.result.findings:
                if finding.info_type.name == "DOCUMENT_TYPE/R&D/SOURCE_CODE":
                    return_payload = '[Blocked due to category: Source Code]'
                elif finding.info_type.name == "US_VEHICLE_IDENTIFICATION_NUMBER":
                    return_payload = '[Blocked due to category: US Vehicle Identification Number]'

  4. Sel berikutnya, generate respons dengan temperature 0:

        prompt = "Is 4Y1SL65848Z411439 an example of a US Vehicle Identification Number (VIN)?"
        response_vin = client.models.generate_content(
            model=model, contents=prompt, config={"temperature": 0})
        print(response_vin.text)

  5. Sel terakhir, panggil fungsinya. Sertakan prompt-nya: model sering
     memecah VIN jadi potongan ('4Y1', 'SL658', '411439') dan tidak pernah
     mengulang VIN utuh, sehingga DLP tidak menemukan apa pun kalau yang
     diperiksa cuma respons:

        deidentify_with_replace_infotype(
            PROJECT_ID, prompt + "\\n" + response_vin.text,
            ["US_VEHICLE_IDENTIFICATION_NUMBER"])

     Output harus '[Blocked due to category: US Vehicle Identification Number]'.
     Jalankan ulang sel definisi fungsi setelah diedit, kalau tidak yang
     dipakai masih versi lama.

  Project ID: $PROJECT_ID   Location: global
==============================================================
EOF
