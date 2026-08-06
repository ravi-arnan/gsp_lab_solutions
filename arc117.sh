#!/usr/bin/env bash
# ARC117 - Organize and Govern Data with Knowledge Catalog: Challenge Lab
#
#   bash arc117.sh
#
# Checkpoint:
#   Task 1 - Create a lake with a raw zone            (otomatis)
#   Task 2 - Create and attach a Cloud Storage bucket (otomatis)
#   Task 3 - Create and add an aspect                 (aspect type otomatis,
#            penempelan ke zone kemungkinan harus lewat UI, lihat docs/arc117.md)
#
# Region default europe-west1 sesuai instruksi lab. Override:
#   REGION=us-east1 bash arc117.sh
# Bucket harus bernama sama dengan Project ID, itu default script.

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

# ----------------------------------------------------------------- parameter
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "europe-west1" "Region (cocokkan dengan panel lab)"
ask BUCKET "$PROJECT" "Nama bucket (lab minta = Project ID)"

LAKE_ID="customer-engagements"
LAKE_NAME="Customer Engagements"
ZONE_ID="raw-event-data"
ZONE_NAME="Raw Event Data"
ASSET_ID="raw-event-files"
ASSET_NAME="Raw Event Files"
ASPECT_ID="protected-raw-data-aspect"
ASPECT_NAME="Protected Raw Data Aspect"
FIELD_ID="protected-raw-data-flag"
FIELD_NAME="Protected Raw Data Flag"

echo "Project: $PROJECT"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ----------------------------------------------------------------- API
step "Enable Dataplex API (bisa ~1 menit)"
gcloud services enable dataplex.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
# gcloud dataplex ... create tidak punya --force, jadi cek dulu biar script
# bisa dijalankan ulang setelah gagal di tengah.
step "Task 1a: lake '$LAKE_NAME' (bisa ~3 menit)"
if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Lake sudah ada, dilewat."
else
  gcloud dataplex lakes create "$LAKE_ID" \
    --project="$PROJECT" --location="$REGION" --display-name="$LAKE_NAME"
fi

step "Task 1b: zone '$ZONE_NAME' (RAW, regional) (bisa ~2 menit)"
if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
else
  gcloud dataplex zones create "$ZONE_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    --display-name="$ZONE_NAME" \
    --type=RAW \
    --resource-location-type=SINGLE_REGION
fi

# ----------------------------------------------------------------- Task 2
step "Task 2a: bucket gs://$BUCKET di $REGION"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "gs://$BUCKET" \
    --project="$PROJECT" --location="$REGION" --uniform-bucket-level-access
fi

step "Task 2b: attach asset '$ASSET_NAME' ke zone (bisa ~2 menit)"
# Tanpa flag discovery = inherit dari zone, sesuai default lab.
if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
else
  gcloud dataplex assets create "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --display-name="$ASSET_NAME" \
    --resource-type=STORAGE_BUCKET \
    --resource-name="projects/$PROJECT/buckets/$BUCKET"
fi

# ----------------------------------------------------------------- Task 3
step "Task 3a: aspect type '$ASPECT_NAME' (field enum Y/N)"
cat > "$WORK/template.json" <<EOF
{
  "name": "$ASPECT_ID",
  "type": "record",
  "recordFields": [
    {
      "name": "$FIELD_ID",
      "type": "enum",
      "index": 1,
      "annotations": { "displayName": "$FIELD_NAME" },
      "enumValues": [
        { "index": 1, "name": "Y" },
        { "index": 2, "name": "N" }
      ]
    }
  ]
}
EOF
python3 -m json.tool "$WORK/template.json" >/dev/null

if gcloud dataplex aspect-types describe "$ASPECT_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Aspect type sudah ada, dilewat."
else
  gcloud dataplex aspect-types create "$ASPECT_ID" \
    --project="$PROJECT" --location="$REGION" \
    --display-name="$ASPECT_NAME" \
    --metadata-template-file-name="$WORK/template.json"
fi

step "Task 3b: tempel aspect ke zone '$ZONE_NAME'"
# Pelajaran dari GSP514: zone Dataplex TIDAK selalu muncul sebagai entry di
# entry group @dataplex, dan menunggu tidak menolong. Dicoba sekali, kalau
# tidak ketemu langsung fallback ke UI, jangan gantung script.
ZONE_GUESS="dataplex.googleapis.com/projects/$PROJECT/locations/$REGION/lakes/$LAKE_ID/zones/$ZONE_ID"
ZONE_ENTRY=""
if gcloud dataplex entries lookup "$ZONE_GUESS" \
     --project="$PROJECT" --location="$REGION" --entry-group=@dataplex --view=basic >/dev/null 2>&1; then
  ZONE_ENTRY="$ZONE_GUESS"
else
  echo "Nama tebakan gagal, cari lewat listing @dataplex..."
  ZONE_ENTRY="$(gcloud dataplex entries list \
                  --project="$PROJECT" --location="$REGION" --entry-group=@dataplex \
                  --format='value(name)' 2>/dev/null \
                | grep -F "/zones/$ZONE_ID" | grep -v '/assets/' | head -1 \
                | sed 's|.*/entries/||' || true)"
fi

ASPECT_DONE=no
if [[ -n "$ZONE_ENTRY" ]]; then
  echo "Entry zone ketemu: $ZONE_ENTRY"
  cat > "$WORK/aspects.json" <<EOF
{
  "$PROJECT.$REGION.$ASPECT_ID": { "data": { "$FIELD_ID": "Y" } }
}
EOF
  python3 -m json.tool "$WORK/aspects.json" >/dev/null
  cat "$WORK/aspects.json"

  if gcloud dataplex entries update "$ZONE_ENTRY" \
       --project="$PROJECT" --location="$REGION" --entry-group=@dataplex \
       --update-aspects="$WORK/aspects.json"; then
    ASPECT_DONE=yes
  else
    echo "PERINGATAN: penempelan aspect gagal lewat API."
  fi
else
  echo "Entry zone tidak ada di @dataplex (sama seperti di GSP514)."
fi

# ----------------------------------------------------------------- verifikasi
step "Verifikasi"
gcloud dataplex zones list  --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
  --format='table(name.basename(), type, state)'
gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
  --format='table(name.basename(), resourceSpec.name, state)'
gcloud dataplex aspect-types list --project="$PROJECT" --location="$REGION" \
  --format='table(name.basename(), displayName)'

cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk verifikasi:
  Task 1 - Create a lake with a raw zone
  Task 2 - Create and attach a Cloud Storage bucket to the zone
EOF

if [[ "$ASPECT_DONE" == "yes" ]]; then
  echo "  Task 3 - Create and add an aspect"
else
  cat <<EOF
  Task 3 - aspect type SUDAH dibuat, tapi aspect BELUM menempel ke zone.

Sisa Task 3 lewat UI (Knowledge Catalog > Discover > Search):
  1. Search terbuka dalam mode natural language. Klik link "here." di
     kalimat "To return to keyword search, click here."
  2. Cari "$ZONE_NAME", klik entry zone-nya.
     (Filter Systems tidak punya "Dataplex" lagi, namanya kini
      "Knowledge Catalog" — tapi cari langsung lebih cepat.)
  3. Scroll ke Aspects, di sebelah Optional aspects klik Add.
  4. Ketik "protected raw data", pilih $ASPECT_NAME.
  5. $FIELD_NAME pilih Y, klik Save.
EOF
fi

echo "--------------------------------------------------------------"
