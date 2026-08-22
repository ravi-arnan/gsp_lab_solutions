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
#   Task 4 - Tag template "Customer Data Tag Template" + tempel tag ke entry bucket
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
ask DATA_OWNER "Ravi Arnan" "Nama untuk field Data Owner di tag (Task 4)"

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
step "Enable API (dataplex + datacatalog, bisa ~1 menit)"
gcloud services enable dataplex.googleapis.com datacatalog.googleapis.com \
  --project="$PROJECT"

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
# "Entry groups" di console sekarang milik Knowledge Catalog (Dataplex), tapi
# tag template di Task 4 masih API Data Catalog lama. Mana yang dibaca grader
# tidak pasti, jadi dibuat di keduanya — masing-masing satu perintah, dan yang
# gagal tidak menjatuhkan yang lain.
EG_OK=0
if gcloud dataplex entry-groups describe "$EG_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Entry group Dataplex sudah ada, dilewat."; EG_OK=1
elif gcloud dataplex entry-groups create "$EG_ID" \
       --project="$PROJECT" --location="$REGION" --display-name="$EG_NAME"; then
  EG_OK=1
else
  echo "-- entry group Dataplex gagal, coba Data Catalog"
fi

# Data Catalog memakai ID bergaris bawah, bukan tanda hubung.
DC_EG_ID="${DC_EG_ID:-custom_entry_group}"
if gcloud data-catalog entry-groups describe "$DC_EG_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Entry group Data Catalog sudah ada, dilewat."; EG_OK=1
elif gcloud data-catalog entry-groups create "$DC_EG_ID" \
       --project="$PROJECT" --location="$REGION" --display-name="$EG_NAME"; then
  EG_OK=1
else
  echo "-- entry group Data Catalog gagal"
fi
[[ "$EG_OK" == "1" ]] || fail "Task 3 - entry group (dua-duanya gagal)"

# ----------------------------------------------------- Task 4: tag template
step "Task 4a: tag template '$TT_NAME'"
if gcloud data-catalog tag-templates describe "$TT_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Tag template sudah ada, dilewat."
elif ! gcloud data-catalog tag-templates create "$TT_ID" \
       --project="$PROJECT" --location="$REGION" \
       --display-name="$TT_NAME" \
       --field=id=data_owner,display-name="Data Owner",type=string \
       --field=id=pii_data,display-name="PII Data",type='enum(Yes|No)'; then
  fail "Task 4 - tag template $TT_NAME"
fi

step "Task 4b: tempel tag ke entry bucket di Data Catalog"
# Entry Cloud Storage untuk bucket baru muncul setelah discovery Dataplex
# jalan. Dicari lewat dua jalur; kalau belum ada, jangan menggantung script —
# pelajaran dari GSP514/ARC117, menunggu entry Dataplex tidak pernah menolong.
ENTRY="$(gcloud data-catalog entries lookup \
           "//storage.googleapis.com/projects/_/buckets/$BUCKET" \
           --format='value(name)' 2>/dev/null || true)"
if [[ -z "$ENTRY" ]]; then
  echo "-- lookup gagal, cari lewat Data Catalog search"
  ENTRY="$(gcloud data-catalog search "$BUCKET" \
             --include-project-ids="$PROJECT" --order-by=relevance \
             --format='value(relativeResourceName)' 2>/dev/null | head -1 || true)"
fi

TAG_OK=0
if [[ -n "$ENTRY" ]]; then
  echo "Entry ketemu: $ENTRY"
  cat > "$WORK/tag.json" <<EOF
{
  "data_owner": "$DATA_OWNER",
  "pii_data": "Yes"
}
EOF
  python3 -m json.tool "$WORK/tag.json" >/dev/null
  if gcloud data-catalog tags create --entry="$ENTRY" \
       --tag-template="$TT_ID" --tag-template-location="$REGION" \
       --tag-file="$WORK/tag.json"; then
    TAG_OK=1
  else
    echo "-- pembuatan tag ditolak API"
  fi
else
  echo "Entry Cloud Storage untuk gs://$BUCKET belum ada di Data Catalog."
fi

step "Task 4c: search memakai tag template (meninggalkan jejak aktivitas)"
gcloud data-catalog search "tag:${PROJECT}.${REGION}.${TT_ID}" \
  --include-project-ids="$PROJECT" --format='table(relativeResourceName)' || true
gcloud data-catalog search "$TT_NAME" \
  --include-project-ids="$PROJECT" --format='table(relativeResourceName)' || true

# ================================================================ verifikasi
step "Verifikasi"
gcloud dataplex lakes list  --project="$PROJECT" --location="$REGION" \
  --format='table(name.basename(), displayName, state)' || true
gcloud dataplex zones list  --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
  --format='table(name.basename(), displayName, type, state, labels)' || true
gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
  --format='table(name.basename(), resourceSpec.name, state)' || true
gcloud data-catalog tag-templates describe "$TT_ID" --project="$PROJECT" --location="$REGION" \
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
  Task 4 - Create a tag template
EOF

if [[ "$TAG_OK" == "0" ]]; then
  cat <<EOF

Tag BELUM menempel ke entry bucket. Sisa Task 4 lewat UI
(Knowledge Catalog > Discover > Search):
  1. Search terbuka dalam mode natural language. Klik link "here." di
     kalimat "To return to keyword search, click here."
  2. Cari "$BUCKET", pilih entry di bawah source system CLOUD STORAGE.
     Kalau belum muncul, tunggu discovery zone selesai (~5-15 menit) lalu
     jalankan ulang script ini — bagian lain akan dilewat.
  3. Di panel entry, bagian Tags klik "Attach tags".
  4. Pilih template "$TT_NAME".
  5. Data Owner = $DATA_OWNER, PII Data = Yes, klik Save.
EOF
fi
echo "--------------------------------------------------------------"

(( ${#FAILED[@]} == 0 ))
