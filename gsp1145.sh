#!/usr/bin/env bash
# GSP1145 - Create and Add Aspects to Knowledge Catalog Assets
#
# REGION diisi dinamis per instance ("Region ____" di Task 1, "Location ____" di Task 2).
# Cocokkan dengan halaman lab, override begini kalau bukan us-central1:
#   REGION=europe-west1 bash gsp1145.sh
#
# Task 4 (search pakai filter Aspect Types) murni UI dan tidak punya checkpoint,
# jadi tidak diotomasi. Lihat docs/gsp1145.md.

set -euo pipefail

# ----------------------------------------------------------------- parameter
REGION="${REGION:-us-central1}"
LAKE_ID="orders-lake"
LAKE_NAME="Orders Lake"
ZONE_ID="customer-curated-zone"
ZONE_NAME="Customer Curated Zone"
ASSET_ID="customer-details-dataset"
ASSET_NAME="Customer Details Dataset"
BQ_DATASET="customers"
BQ_TABLE="customer_details"
ASPECT_ID="protected-data-aspect"
ASPECT_NAME="Protected Data Aspect"
FIELD_ID="protected-data-flag"
FIELD_NAME="Protected Data Flag"
# JANGAN namai variabel ini COLUMNS: itu variabel spesial bash (lebar terminal).
# Bash me-reset-nya via checkwinsize, dan assignment skalar ke array menulis ke
# index 0, jadi elemen pertama diam-diam berubah jadi angka.
ASPECT_COLUMNS=(zip state last_name country email latitude first_name city longitude)

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Project: $PROJECT"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ----------------------------------------------------------------- API
step "Enable Cloud Dataplex API (bisa ~1 menit)"
gcloud services enable dataplex.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
# gcloud dataplex ... create tidak punya --force, jadi cek dulu biar script
# bisa dijalankan ulang setelah gagal di tengah.
step "Task 1a: lake '$LAKE_NAME' (bisa beberapa menit)"
if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Lake sudah ada, dilewat."
else
  gcloud dataplex lakes create "$LAKE_ID" \
    --project="$PROJECT" --location="$REGION" --display-name="$LAKE_NAME"
fi

step "Task 1b: zone '$ZONE_NAME' (CURATED, regional)"
if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
else
  gcloud dataplex zones create "$ZONE_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    --display-name="$ZONE_NAME" \
    --type=CURATED \
    --resource-location-type=SINGLE_REGION
fi

# Dataset 'customers' disiapkan lab, bukan script. Cek dulu biar errornya jelas.
if ! bq --project_id="$PROJECT" show --format=none "$BQ_DATASET" 2>/dev/null; then
  echo "ERROR: dataset '$BQ_DATASET' belum ada. Itu resource pre-created dari lab."
  echo "Tunggu provisioning selesai, refresh halaman lab, jalankan ulang."
  exit 1
fi

step "Task 1c: attach asset '$ASSET_NAME' (BigQuery dataset $BQ_DATASET)"
# Tanpa flag discovery = inherit dari zone, sesuai instruksi lab.
if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
else
  gcloud dataplex assets create "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --display-name="$ASSET_NAME" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name="projects/$PROJECT/datasets/$BQ_DATASET"
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: aspect type '$ASPECT_NAME' (enum wajib, Yes/No)"
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
      "constraints": { "required": true },
      "enumValues": [
        { "index": 1, "name": "Yes" },
        { "index": 2, "name": "No" }
      ]
    }
  ]
}
EOF

if gcloud dataplex aspect-types describe "$ASPECT_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Aspect type sudah ada, dilewat."
else
  gcloud dataplex aspect-types create "$ASPECT_ID" \
    --project="$PROJECT" --location="$REGION" \
    --display-name="$ASPECT_NAME" \
    --metadata-template-file-name="$WORK/template.json"
fi

# ----------------------------------------------------------------- Task 3
# Entry BigQuery dibuat otomatis Dataplex di entry group @bigquery, dan letaknya
# mengikuti LOCATION DATASET-nya, bukan region lake. Deteksi, jangan asumsikan.
step "Task 3a: cari entry BigQuery untuk $BQ_DATASET.$BQ_TABLE"

BQ_LOC="$(bq --project_id="$PROJECT" show --format=prettyjson "$BQ_DATASET" \
          | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"].lower())')"
echo "Location dataset $BQ_DATASET: $BQ_LOC"
if [[ "$BQ_LOC" != "$REGION" ]]; then
  echo
  echo "PERINGATAN: location dataset ($BQ_LOC) beda dengan REGION ($REGION)."
  echo "Aspect type dibuat di $REGION tapi entry-nya ada di $BQ_LOC."
  echo "Kalau langkah berikutnya gagal, kemungkinan besar REGION-nya salah."
fi

ENTRY_GUESS="bigquery.googleapis.com/projects/$PROJECT/datasets/$BQ_DATASET/tables/$BQ_TABLE"
ENTRY=""
if gcloud dataplex entries lookup "$ENTRY_GUESS" \
     --project="$PROJECT" --location="$BQ_LOC" --entry-group=@bigquery \
     --view=basic >/dev/null 2>&1; then
  ENTRY="$ENTRY_GUESS"
  echo "Entry ketemu: $ENTRY"
else
  echo "Nama tebakan gagal, cari lewat listing..."
  ENTRY="$(gcloud dataplex entries list \
             --project="$PROJECT" --location="$BQ_LOC" --entry-group=@bigquery \
             --format='value(name)' 2>/dev/null \
           | grep -F "/tables/$BQ_TABLE" | head -1 | sed 's|.*/entries/||' || true)"
  [[ -n "$ENTRY" ]] || {
    echo "ERROR: entry untuk $BQ_TABLE tidak ketemu di entry group @bigquery ($BQ_LOC)."
    echo "Dataplex butuh waktu meng-index tabel BigQuery. Tunggu beberapa menit,"
    echo "lalu jalankan ulang. Kalau tetap gagal, kerjakan Task 3 lewat UI"
    echo "(lihat docs/gsp1145.md, bagian fallback)."
    exit 1
  }
  echo "Entry ketemu: $ENTRY"
fi

step "Task 3b: tambah aspect ke entry + ${#ASPECT_COLUMNS[@]} kolom"
KEY="$PROJECT.$REGION.$ASPECT_ID"
{
  printf '{\n'
  printf '  "%s": { "data": { "%s": "Yes" } }' "$KEY" "$FIELD_ID"
  for c in "${ASPECT_COLUMNS[@]}"; do
    printf ',\n  "%s@Schema.%s": { "data": { "%s": "Yes" } }' "$KEY" "$c" "$FIELD_ID"
  done
  printf '\n}\n'
} > "$WORK/aspects.json"

python3 -m json.tool "$WORK/aspects.json" >/dev/null   # gagal cepat kalau JSON rusak

# Nama kolom harus huruf, bukan angka. Kalau ada yang jadi angka, sebuah variabel
# tertimpa shell dan aspect akan ditolak dengan "path is used but not provided".
if grep -qE '@Schema\.[0-9]+"' "$WORK/aspects.json"; then
  echo "ERROR: ada nama kolom yang berubah jadi angka. Cek variabel ASPECT_COLUMNS."
  cat "$WORK/aspects.json"
  exit 1
fi
cat "$WORK/aspects.json"

gcloud dataplex entries update "$ENTRY" \
  --project="$PROJECT" --location="$BQ_LOC" --entry-group=@bigquery \
  --update-aspects="$WORK/aspects.json"

# ----------------------------------------------------------------- verifikasi
step "Verifikasi: aspect yang menempel di entry"
gcloud dataplex entries lookup "$ENTRY" \
  --project="$PROJECT" --location="$BQ_LOC" --entry-group=@bigquery \
  --view=custom --aspect-types="$ASPECT_ID" \
  --format='value(entry.aspects.keys())'

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk:
  - Create a lake, zone, and asset in Knowledge Catalog
  - Create an aspect type
  - Add an aspect to assets

Task 4 (search pakai filter Aspect Types) murni UI dan tidak
punya checkpoint. Kerjakan sendiri kalau mau lihat hasilnya.
--------------------------------------------------------------
EOF
