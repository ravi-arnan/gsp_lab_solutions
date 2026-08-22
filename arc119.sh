#!/usr/bin/env bash
# ARC119 - Create a Secure Data Lake on Cloud Storage: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc119.sh
#   bash arc119.sh
#
# Checkpoint:
#   Task 1 - Cloud Storage bucket <PROJECT>-bucket + attach jadi asset ke zone
#   Task 2 - Lake "Customer-Lake" + zone "Public-Zone" (RAW, regional, discovery,
#            label domain_type=source_data)
#   Task 3 - Entry group "Custom entry group"
#   Task 4 - "Tag template" Customer Data Tag Template -> DIBUAT SEBAGAI ASPECT
#            TYPE Knowledge Catalog, karena API Data Catalog sudah dimatikan
#
# DUA USER. Instruksi lab menyuruh Task 1 dikerjakan sebagai User 1 dan Task 2
# sebagai User 2. Script tidak bisa berganti akun sendiri, jadi kegagalan izin
# TIDAK menghentikan script: task yang gagal dicatat dan dilaporkan di akhir.
# Kalau ada yang PERMISSION_DENIED, `gcloud auth login` sebagai user yang
# diminta lalu jalankan ulang — semua langkah dilewat kalau resource sudah ada.
#
# URUTAN DIBALIK dari nomor task. Asset di Task 1 butuh zone dari Task 2, jadi
# lake dan zone dibuat lebih dulu.
#
# LAMA: ~6-10 menit, hampir semuanya menunggu lake dan zone naik.

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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

FAILED=()
fail() { FAILED+=("$1"); echo "!! GAGAL: $1"; }

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "us-west1" "Region (cocokkan dengan panel lab)"

BUCKET="${BUCKET:-${PROJECT}-bucket}"

# ID dikosongkan di instruksi lab ("Leave the default value"), artinya console
# menurunkannya dari display name: "Customer-Lake" -> customer-lake.
LAKE_ID="${LAKE_ID:-customer-lake}"
LAKE_NAME="Customer-Lake"
ZONE_ID="${ZONE_ID:-public-zone}"
ZONE_NAME="Public-Zone"
ASSET_ID="${ASSET_ID:-$BUCKET}"
EG_ID="${EG_ID:-custom-entry-group}"
EG_NAME="Custom entry group"
TT_ID="${TT_ID:-customer-data-tag-template}"
TT_NAME="Customer Data Tag Template"

echo "Project: $PROJECT"
echo "Bucket : gs://$BUCKET"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ================================================================= persiapan
step "Enable API Dataplex (bisa ~1 menit)"
gcloud services enable dataplex.googleapis.com --project="$PROJECT"

# ------------------------------------------------------- Task 2: lake + zone
step "Task 2a: lake '$LAKE_NAME' (bisa ~3 menit)"
if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Lake sudah ada, dilewat."
elif ! gcloud dataplex lakes create "$LAKE_ID" \
       --project="$PROJECT" --location="$REGION" --display-name="$LAKE_NAME"; then
  fail "Task 2 - lake $LAKE_NAME"
fi

step "Task 2b: zone '$ZONE_NAME' (RAW, regional, discovery, label)"
if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
elif ! gcloud dataplex zones create "$ZONE_ID" \
       --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
       --display-name="$ZONE_NAME" \
       --type=RAW \
       --resource-location-type=SINGLE_REGION \
       --discovery-enabled \
       --labels=domain_type=source_data; then
  fail "Task 2 - zone $ZONE_NAME"
fi

# --------------------------------------------------- Task 1: bucket + asset
step "Task 1a: bucket gs://$BUCKET (regional, $REGION)"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
elif ! gcloud storage buckets create "gs://$BUCKET" \
       --project="$PROJECT" --location="$REGION" --uniform-bucket-level-access; then
  fail "Task 1 - bucket gs://$BUCKET"
fi

step "Task 1b: attach bucket sebagai asset ke zone '$ZONE_NAME'"
if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" \
     --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
elif ! gcloud dataplex assets create "$ASSET_ID" \
       --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
       --display-name="$ASSET_ID" \
       --resource-type=STORAGE_BUCKET \
       --resource-name="projects/$PROJECT/buckets/$BUCKET"; then
  fail "Task 1 - attach asset ke zone"
fi

# ------------------------------------------------------ Task 3: entry group
step "Task 3: entry group '$EG_NAME'"
# "Custom entry group" di instruksi lab itu display name; ID-nya tidak boleh
# berspasi, jadi diturunkan jadi custom-entry-group.
if gcloud dataplex entry-groups describe "$EG_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Entry group sudah ada, dilewat."
elif ! gcloud dataplex entry-groups create "$EG_ID" \
       --project="$PROJECT" --location="$REGION" --display-name="$EG_NAME"; then
  fail "Task 3 - entry group $EG_NAME"
fi

# ----------------------------------------------------- Task 4: aspect type
step "Task 4: aspect type '$TT_NAME' (yang lab sebut tag template)"
# API Data Catalog SUDAH MATI di project lab ini:
#   INVALID_ARGUMENT: Project ... is not allowed to perform read operations
#   due to Data Catalog deprecation.
# "Tag template" di soal sekarang berarti aspect type Knowledge Catalog.
cat > "$WORK/template.json" <<EOF
{
  "name": "$TT_ID",
  "type": "record",
  "recordFields": [
    { "name": "data_owner", "type": "string", "index": 1,
      "annotations": { "displayName": "Data Owner" } },
    { "name": "pii_data", "type": "enum", "index": 2,
      "annotations": { "displayName": "PII Data" },
      "enumValues": [ { "index": 1, "name": "Yes" }, { "index": 2, "name": "No" } ] }
  ]
}
EOF
python3 -m json.tool "$WORK/template.json" >/dev/null

if gcloud dataplex aspect-types describe "$TT_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Aspect type sudah ada, dilewat."
elif ! gcloud dataplex aspect-types create "$TT_ID" \
       --project="$PROJECT" --location="$REGION" \
       --display-name="$TT_NAME" \
       --metadata-template-file-name="$WORK/template.json"; then
  fail "Task 4 - aspect type $TT_NAME"
fi

# ================================================================ verifikasi
step "Verifikasi"
gcloud dataplex lakes list  --project="$PROJECT" --location="$REGION" \
  --format='table(name.basename(), displayName, state)' || true
gcloud dataplex zones list  --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
  --format='table(name.basename(), displayName, type, state, labels)' || true
gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
  --format='table(name.basename(), resourceSpec.name, state)' || true
gcloud dataplex entry-groups list --project="$PROJECT" --location="$REGION" \
  --format='table(name.basename(), displayName)' || true
gcloud dataplex aspect-types list --project="$PROJECT" --location="$REGION" \
  --format='table(name.basename(), displayName)' || true

echo
echo "--------------------------------------------------------------"
if (( ${#FAILED[@]} )); then
  echo "ADA TASK YANG GAGAL:"
  printf '  - %s\n' "${FAILED[@]}"
  echo
  echo "Kalau errornya PERMISSION_DENIED: lab ini memakai dua user."
  echo "  gcloud auth login          # masuk sebagai user yang diminta task itu"
  echo "  bash $0                    # aman diulang, yang sudah ada dilewat"
  echo
fi

cat <<EOF
Klik Check my progress untuk:
  Task 1 - Create a Cloud Storage bucket
  Task 2 - Create a lake and add a zone
  Task 3 - Create an entry group
  Task 4 - Create a tag template (aspect type)
EOF

echo "--------------------------------------------------------------"

(( ${#FAILED[@]} == 0 ))
