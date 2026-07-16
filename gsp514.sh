#!/usr/bin/env bash
# GSP514 - Build a Data Mesh with Knowledge Catalog: Challenge Lab
#
# Challenge lab, tapi tasknya TIDAK diacak seperti GSP340. Yang berubah per
# instance cuma region, project, dan email User 2.
#
#   USER2=<email> REGION=<region> bash gsp514.sh
#
# Satu fase, tidak ada delete dan tidak ada urutan checkpoint yang merusak.

set -euo pipefail

# ----------------------------------------------------------------- parameter
REGION="${REGION:-us-central1}"
USER2="${USER2:-}"

LAKE_ID="sales-lake";            LAKE_NAME="Sales Lake"
RAW_ZONE_ID="raw-customer-zone"; RAW_ZONE_NAME="Raw Customer Zone"
CUR_ZONE_ID="curated-customer-zone"; CUR_ZONE_NAME="Curated Customer Zone"
GCS_ASSET_ID="customer-engagements"; GCS_ASSET_NAME="Customer Engagements"
BQ_ASSET_ID="customer-orders";   BQ_ASSET_NAME="Customer Orders"

BQ_DATASET="customer_orders"
BQ_TABLE="ordered_items"
DQ_RESULTS_DATASET="orders_dq_dataset"
DQ_RESULTS_TABLE="results"
DQ_FILE="dq-customer-orders.yaml"
SCAN_ID="customer-orders-data-quality-job"

ASPECT_ID="protected-customer-data-aspect"
ASPECT_NAME="Protected Customer Data Aspect"
F1_ID="raw-data-flag";                        F1_NAME="Raw Data Flag"
F2_ID="protected-contact-information-flag";   F2_NAME="Protected Contact Information Flag"

ROLE_WRITER="roles/dataplex.dataWriter"   # least privilege untuk upload file

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
[[ -n "$USER2" ]] || { echo "USER2 belum diisi. Ambil email User 2 dari panel Lab setup, lalu:"
                       echo "  USER2=<email-user-2> REGION=$REGION bash gsp514.sh"; exit 1; }

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "User 2 : $USER2"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ----------------------------------------------------------------- API
step "Enable API (Dataplex, Data Catalog, Dataproc)"
gcloud services enable \
  dataplex.googleapis.com \
  datacatalog.googleapis.com \
  dataproc.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- deteksi resource pre-created
step "Deteksi bucket dan dataset yang disiapkan lab"
ONLINE_BUCKET="$(gcloud storage buckets list --project="$PROJECT" --format='value(name)' 2>/dev/null \
                 | sed 's|^gs://||; s|/$||' | grep -- '-customer-online-sessions$' | head -1 || true)"
DQ_BUCKET="$(gcloud storage buckets list --project="$PROJECT" --format='value(name)' 2>/dev/null \
             | sed 's|^gs://||; s|/$||' | grep -- '-dq-config$' | head -1 || true)"

if [[ -z "$ONLINE_BUCKET" || -z "$DQ_BUCKET" ]]; then
  echo "ERROR: bucket pre-created belum lengkap."
  echo "  *-customer-online-sessions : ${ONLINE_BUCKET:-TIDAK KETEMU}"
  echo "  *-dq-config                : ${DQ_BUCKET:-TIDAK KETEMU}"
  echo "Bucket yang ada sekarang:"
  gcloud storage buckets list --project="$PROJECT" --format='value(name)' || true
  echo "Tunggu provisioning lab selesai, lalu jalankan ulang."
  exit 1
fi
echo "Bucket sesi   : $ONLINE_BUCKET"
echo "Bucket dq     : $DQ_BUCKET"

bq --project_id="$PROJECT" show --format=none "$BQ_DATASET" 2>/dev/null || {
  echo "ERROR: dataset '$BQ_DATASET' belum ada (pre-created lab). Tunggu provisioning."; exit 1; }
echo "Dataset       : $BQ_DATASET (ada)"

# ----------------------------------------------------------------- Task 1
step "Task 1a: lake '$LAKE_NAME'"
if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Lake sudah ada, dilewat."
else
  gcloud dataplex lakes create "$LAKE_ID" \
    --project="$PROJECT" --location="$REGION" --display-name="$LAKE_NAME"
fi

step "Task 1b: zone '$RAW_ZONE_NAME' (RAW, regional)"
if gcloud dataplex zones describe "$RAW_ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
else
  gcloud dataplex zones create "$RAW_ZONE_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    --display-name="$RAW_ZONE_NAME" --type=RAW --resource-location-type=SINGLE_REGION
fi

step "Task 1c: zone '$CUR_ZONE_NAME' (CURATED, regional)"
if gcloud dataplex zones describe "$CUR_ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
else
  gcloud dataplex zones create "$CUR_ZONE_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    --display-name="$CUR_ZONE_NAME" --type=CURATED --resource-location-type=SINGLE_REGION
fi

step "Task 1d: asset '$GCS_ASSET_NAME' (bucket $ONLINE_BUCKET) di raw zone"
if gcloud dataplex assets describe "$GCS_ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$RAW_ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
else
  gcloud dataplex assets create "$GCS_ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$RAW_ZONE_ID" \
    --display-name="$GCS_ASSET_NAME" \
    --resource-type=STORAGE_BUCKET \
    --resource-name="projects/$PROJECT/buckets/$ONLINE_BUCKET"
fi

step "Task 1e: asset '$BQ_ASSET_NAME' (dataset $BQ_DATASET) di curated zone"
if gcloud dataplex assets describe "$BQ_ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$CUR_ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
else
  gcloud dataplex assets create "$BQ_ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$CUR_ZONE_ID" \
    --display-name="$BQ_ASSET_NAME" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name="projects/$PROJECT/datasets/$BQ_DATASET"
fi

# ----------------------------------------------------------------- Task 2
step "Task 2a: aspect type '$ASPECT_NAME' (dua field enum)"
cat > "$WORK/template.json" <<EOF
{
  "name": "$ASPECT_ID",
  "type": "record",
  "recordFields": [
    {
      "name": "$F1_ID", "type": "enum", "index": 1,
      "annotations": { "displayName": "$F1_NAME" },
      "enumValues": [ { "index": 1, "name": "Yes" }, { "index": 2, "name": "No" } ]
    },
    {
      "name": "$F2_ID", "type": "enum", "index": 2,
      "annotations": { "displayName": "$F2_NAME" },
      "enumValues": [ { "index": 1, "name": "Yes" }, { "index": 2, "name": "No" } ]
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

step "Task 2b: cari entry catalog untuk zone '$RAW_ZONE_ID'"
# Resource Dataplex (lake/zone/asset) muncul di entry group @dataplex.
# Format nama entry tidak didokumentasikan, jadi dicari, bukan ditebak.
ZONE_GUESS="dataplex.googleapis.com/projects/$PROJECT/locations/$REGION/lakes/$LAKE_ID/zones/$RAW_ZONE_ID"
ZONE_ENTRY=""
if gcloud dataplex entries lookup "$ZONE_GUESS" \
     --project="$PROJECT" --location="$REGION" --entry-group=@dataplex --view=basic >/dev/null 2>&1; then
  ZONE_ENTRY="$ZONE_GUESS"
else
  echo "Nama tebakan gagal, cari lewat listing @dataplex..."
  ZONE_ENTRY="$(gcloud dataplex entries list \
                  --project="$PROJECT" --location="$REGION" --entry-group=@dataplex \
                  --format='value(name)' 2>/dev/null \
                | grep -F "/zones/$RAW_ZONE_ID" | grep -v '/assets/' | head -1 \
                | sed 's|.*/entries/||' || true)"
fi

# Task 2b boleh gagal tanpa menjatuhkan Task 3-5. Satu task rapuh tidak layak
# memblokir tiga task yang sehat.
ASPECT_DONE=no
if [[ -z "$ZONE_ENTRY" ]]; then
  echo
  echo "PERINGATAN: entry zone tidak ketemu di entry group @dataplex."
  echo "Task 2b DILEWAT, script lanjut ke Task 3-5."
  echo "Kerjakan Task 2b lewat UI nanti (lihat docs/gsp514.md, bagian fallback)."
else
  echo "Entry zone ketemu: $ZONE_ENTRY"

  step "Task 2c: tempel aspect ke zone (kedua flag = Yes)"
  cat > "$WORK/aspects.json" <<EOF
{
  "$PROJECT.$REGION.$ASPECT_ID": {
    "data": { "$F1_ID": "Yes", "$F2_ID": "Yes" }
  }
}
EOF
  python3 -m json.tool "$WORK/aspects.json" >/dev/null
  cat "$WORK/aspects.json"

  if gcloud dataplex entries update "$ZONE_ENTRY" \
       --project="$PROJECT" --location="$REGION" --entry-group=@dataplex \
       --update-aspects="$WORK/aspects.json"; then
    ASPECT_DONE=yes
  else
    echo "PERINGATAN: penempelan aspect gagal. Task 2b dilewat, lanjut ke Task 3-5."
  fi
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: grant $ROLE_WRITER ke $USER2 di asset '$GCS_ASSET_NAME'"
# "upload file baru" = butuh tulis. dataWriter adalah role terkecil yang cukup;
# dataReader tidak bisa upload, dataOwner/admin kelebihan hak.
gcloud dataplex assets add-iam-policy-binding "$GCS_ASSET_ID" \
  --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$RAW_ZONE_ID" \
  --member="user:$USER2" --role="$ROLE_WRITER"

# ----------------------------------------------------------------- Task 4
step "Task 4: bikin $DQ_FILE lalu upload ke gs://$DQ_BUCKET"
# threshold 1 = 100% (spec pakai rasio 0..1, bukan persen)
cat > "$WORK/$DQ_FILE" <<EOF
rules:
  - nonNullExpectation: {}
    column: user_id
    dimension: COMPLETENESS
    threshold: 1
  - nonNullExpectation: {}
    column: order_id
    dimension: COMPLETENESS
    threshold: 1
postScanActions:
  bigqueryExport:
    resultsTable: //bigquery.googleapis.com/projects/$PROJECT/datasets/$DQ_RESULTS_DATASET/tables/$DQ_RESULTS_TABLE
EOF
cat "$WORK/$DQ_FILE"
gcloud storage cp "$WORK/$DQ_FILE" "gs://$DQ_BUCKET/$DQ_FILE" --project="$PROJECT"

# ----------------------------------------------------------------- Task 5
step "Task 5b: datascan '$SCAN_ID'"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
DATAPLEX_SA="service-$PROJECT_NUMBER@gcp-sa-dataplex.iam.gserviceaccount.com"
echo "Compute Engine default SA: $COMPUTE_SA"
echo "Dataplex service agent   : $DATAPLEX_SA"

# Datascan dijalankan Dataplex dengan cara MENG-IMPERSONATE compute SA. Tanpa
# izin ini, create gagal 403 "does not have permission to impersonate".
# Prasyarat ini tidak disebut di halaman lab maupun di docs gcloud datascans.
step "Task 5a: izinkan Dataplex service agent impersonate compute SA"
gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA" \
  --project="$PROJECT" \
  --member="serviceAccount:$DATAPLEX_SA" \
  --role="roles/iam.serviceAccountTokenCreator"

echo "Menunggu propagasi IAM (biasanya <1 menit)..."
sleep 20

DATA_SOURCE="//bigquery.googleapis.com/projects/$PROJECT/datasets/$BQ_DATASET/tables/$BQ_TABLE"

if gcloud dataplex datascans describe "$SCAN_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Datascan sudah ada, dilewat pembuatannya."
else
  # Binding serviceAccountTokenCreator butuh waktu menyebar. 403 di percobaan
  # awal itu normal, bukan izin yang salah. Coba ulang, jangan langsung mati.
  SCAN_OK=no
  for attempt in 1 2 3 4 5 6; do
    if gcloud dataplex datascans create data-quality "$SCAN_ID" \
         --project="$PROJECT" --location="$REGION" \
         --data-source-resource="$DATA_SOURCE" \
         --data-quality-spec-file="$WORK/$DQ_FILE" \
         --service-account="$COMPUTE_SA" \
         --on-demand=true; then
      SCAN_OK=yes; break
    fi
    echo
    echo "Percobaan $attempt gagal (kemungkinan propagasi IAM). Tunggu 20 detik..."
    sleep 20
  done
  if [[ "$SCAN_OK" != "yes" ]]; then
    echo "ERROR: datascan gagal setelah 6 percobaan (~2 menit)."
    echo "Kalau errornya tetap 403 impersonate, cek binding ini ada:"
    echo "  gcloud iam service-accounts get-iam-policy $COMPUTE_SA --project=$PROJECT"
    exit 1
  fi
fi

step "Task 5c: jalankan datascan sekarang"
gcloud dataplex datascans run "$SCAN_ID" --project="$PROJECT" --location="$REGION"

# ----------------------------------------------------------------- verifikasi
step "Verifikasi"
echo "--- zones:"
gcloud dataplex zones list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
  --format='table(name.basename(), type, state)'
echo "--- assets raw zone:"
gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$RAW_ZONE_ID" \
  --format='table(name.basename(), resourceSpec.name, state)'
echo "--- assets curated zone:"
gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$CUR_ZONE_ID" \
  --format='table(name.basename(), resourceSpec.name, state)'
echo "--- aspect di zone:"
if [[ "$ASPECT_DONE" == "yes" ]]; then
gcloud dataplex entries lookup "$ZONE_ENTRY" \
  --project="$PROJECT" --location="$REGION" --entry-group=@dataplex \
  --view=custom --aspect-types="$ASPECT_ID" --format=json \
| python3 -c '
import json, sys
a = json.load(sys.stdin).get("entry", {}).get("aspects", {})
print(f"{len(a)} aspect menempel di zone (harus 1)")
for k, v in a.items():
    print("  -", k, "=", v.get("data"))
'
else
  echo "DILEWAT (Task 2b belum berhasil, kerjakan lewat UI)"
fi
echo "--- file dq di bucket:"
gcloud storage ls "gs://$DQ_BUCKET/" --project="$PROJECT"

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk task yang sudah dikerjakan.
Status Task 2b (aspect ke zone): $ASPECT_DONE

Datascan butuh beberapa menit. Cek statusnya dengan:
  gcloud dataplex datascans jobs list --datascan=$SCAN_ID \\
    --project=$PROJECT --location=$REGION

Checkpoint Task 5 baru hijau setelah job-nya SUCCEEDED.
--------------------------------------------------------------
EOF
