#!/usr/bin/env bash
# GSP1158 - Assessing Data Quality with Knowledge Catalog (dulu "with Dataplex")
#
#   bash gsp1158.sh
#
# REGION dibaca dari metadata project. Override kalau tidak cocok dengan lab:
#   REGION=europe-west1 bash gsp1158.sh
#
# Checkpoint (5 x 20 poin):
#   Task 1  Create a lake, zone, and asset in Knowledge Catalog   -> OTOMATIS
#   Task 2  Query BigQuery table to review data quality           -> MANUAL, lihat di bawah
#   Task 3  Create and upload a data quality specification file   -> OTOMATIS
#   Task 4  Define and run a data quality job                     -> OTOMATIS
#   Task 5  Review data quality results in the BigQuery table     -> MANUAL, lihat di bawah
#
# KENAPA TASK 2 DAN 5 MANUAL
# Checkpoint keduanya memeriksa job history BigQuery, bukan perubahan resource.
# Job dari Console ber-ID `bquxjob_...`, job dari `bq query` di shell ber-ID
# `bqjob_...`. Query yang identik dari Cloud Shell tetap dinilai 0. Ini pola yang
# sama dengan GSP1154 di repo ini: API call sukses, artefaknya bukan yang dicari.
# Jadi 60 dari 100 poin otomatis, 40 sisanya wajib diklik di Console.

set -euo pipefail

# ----------------------------------------------------------------- parameter
LAKE_ID="ecommerce-lake"
LAKE_NAME="Ecommerce Lake"
ZONE_ID="customer-contact-raw-zone"
ZONE_NAME="Customer Contact Raw Zone"
ASSET_ID="contact-info"
ASSET_NAME="Contact Info"
BQ_DATASET="customers"
BQ_TABLE="contact_info"
DQ_DATASET="customers_dq_dataset"   # teks lab menulis "customer_dq_dataset" di prosa, itu typo
DQ_TABLE="dq_results"
SCAN_ID="customer-orders-data-quality-job"
YAML_NAME="dq-customer-raw-data.yaml"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

REGION="${REGION:-$(gcloud compute project-info describe \
  --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null)}"
[[ -n "$REGION" ]] || { echo "REGION tidak terbaca. Ambil dari panel lab, lalu: REGION=<region> bash gsp1158.sh"; exit 1; }

BUCKET="${PROJECT}-bucket"

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Bucket : gs://$BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

pause() { # pause "<instruksi>"
  echo
  echo "--------------------------------------------------------------"
  echo "$1"
  echo "--------------------------------------------------------------"
  read -r -p "Tekan ENTER kalau checkpoint sudah hijau, script lanjut. "
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Bucket ini di-provision lab, bukan dibuat script. Kalau belum ada, provisioning
# belum selesai — bikin sendiri berisiko salah region, jadi berhenti saja.
gcloud storage ls "gs://$BUCKET" >/dev/null 2>&1 || {
  echo "Bucket gs://$BUCKET belum ada. Tunggu provisioning lab selesai, lalu jalankan ulang."
  exit 1
}

step "Enable Dataplex API (bisa ~1 menit)"
gcloud services enable dataplex.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
# `gcloud dataplex ... create` tidak punya --force, jadi cek dulu supaya script
# aman dijalankan ulang setelah gagal di tengah.
step "Task 1a: lake '$LAKE_NAME' (bisa ~3 menit)"
if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Lake sudah ada, dilewat."
else
  gcloud dataplex lakes create "$LAKE_ID" \
    --project="$PROJECT" --location="$REGION" \
    --display-name="$LAKE_NAME"
fi

step "Task 1b: zone '$ZONE_NAME' (bisa ~2 menit)"
# Discovery settings di lab = "Inherit", jadi JANGAN kirim --discovery-enabled.
if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
  echo "Zone sudah ada, dilewat."
else
  gcloud dataplex zones create "$ZONE_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    --display-name="$ZONE_NAME" \
    --type=RAW --resource-location-type=SINGLE_REGION
fi

step "Task 1c: asset '$ASSET_NAME' -> dataset $BQ_DATASET"
if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
  echo "Asset sudah ada, dilewat."
else
  gcloud dataplex assets create "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" \
    --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --display-name="$ASSET_NAME" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name="projects/$PROJECT/datasets/$BQ_DATASET"
fi

pause "Klik Check my progress Task 1 sekarang."

# ----------------------------------------------------------------- Task 2
step "Task 2: MANUAL — query harus dijalankan dari Console"

# Query ini dijalankan juga dari shell, tapi HANYA supaya kamu lihat datanya.
# Job-nya ber-ID bqjob_ dan tidak akan menghijaukan checkpoint.
echo "Pratinjau isi tabel (ini TIDAK menghijaukan checkpoint):"
bq --project_id="$PROJECT" query --use_legacy_sql=false --format=pretty \
  "SELECT * FROM \`$PROJECT.$BQ_DATASET.$BQ_TABLE\` ORDER BY id LIMIT 50" || true

pause "Buka Console > BigQuery > SQL Editor, jalankan query ini DI SANA:

  SELECT * FROM \`$PROJECT.$BQ_DATASET.$BQ_TABLE\` ORDER BY id LIMIT 50

Lalu klik Check my progress Task 2.
Query dari Cloud Shell tidak dihitung — checkpoint mencari job Console (bquxjob_)."

# ----------------------------------------------------------------- Task 3
step "Task 3: tulis dan upload $YAML_NAME"

# Heredoc di-quote ('EOF') supaya regex mentah tidak disentuh bash — ada `$` di
# ujung pola dan `{1}` di tengahnya. Project ID disisipkan lewat sed setelahnya.
cat > "$WORK/$YAML_NAME" <<'EOF'
rules:
- nonNullExpectation: {}
  column: id
  dimension: COMPLETENESS
  threshold: 1
- regexExpectation:
    regex: '^[^@]+[@]{1}[^@]+$'
  column: email
  dimension: CONFORMANCE
  ignoreNull: true
  threshold: .85
postScanActions:
  bigqueryExport:
    resultsTable: projects/PROJECT_ID/datasets/DQ_DATASET/tables/DQ_TABLE
EOF

sed -i "s|PROJECT_ID|$PROJECT|g; s|DQ_DATASET|$DQ_DATASET|g; s|DQ_TABLE|$DQ_TABLE|g" "$WORK/$YAML_NAME"
cat "$WORK/$YAML_NAME"

gcloud storage cp "$WORK/$YAML_NAME" "gs://$BUCKET/$YAML_NAME"

pause "Klik Check my progress Task 3 sekarang."

# ----------------------------------------------------------------- Task 4
step "Task 4a: buat data quality scan '$SCAN_ID'"
if gcloud dataplex datascans describe "$SCAN_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
  echo "Scan sudah ada, dilewat."
else
  gcloud dataplex datascans create data-quality "$SCAN_ID" \
    --project="$PROJECT" --location="$REGION" \
    --data-source-resource="//bigquery.googleapis.com/projects/$PROJECT/datasets/$BQ_DATASET/tables/$BQ_TABLE" \
    --data-quality-spec-file="gs://$BUCKET/$YAML_NAME"
fi

step "Task 4b: jalankan scan"
gcloud dataplex datascans run "$SCAN_ID" --project="$PROJECT" --location="$REGION"

step "Task 4c: tunggu job selesai"
# Batas iterasi wajib: kalau API balas error transien, state jadi kosong dan
# loop tanpa batas menggantung Cloud Shell sampai sesinya mati sendiri.
JOB=""
for (( i = 1; i <= 40; i++ )); do
  JOB=$(gcloud dataplex datascans jobs list \
          --project="$PROJECT" --location="$REGION" --datascan="$SCAN_ID" \
          --format="value(name)" 2>/dev/null | head -n 1)
  [[ -n "$JOB" ]] && break
  echo "  menunggu job muncul ($i/40)"
  sleep 10
done

if [[ -n "$JOB" ]]; then
  for (( i = 1; i <= 40; i++ )); do
    ST=$(gcloud dataplex datascans jobs describe "$JOB" \
           --project="$PROJECT" --location="$REGION" --datascan="$SCAN_ID" \
           --format="value(state)" 2>/dev/null || echo "")
    echo "  -> ${ST:-UNKNOWN} ($i/40)"
    [[ "$ST" == "SUCCEEDED" ]] && break
    [[ "$ST" == "FAILED" || "$ST" == "CANCELLED" ]] && { echo "Job berakhir: $ST"; break; }
    sleep 15
  done
else
  echo "Job tidak muncul. Jalankan Run Now manual di Console kalau checkpoint tidak hijau."
fi

# Satu rule GAGAL memang hasil yang benar di lab ini: kolom id 10% null lawan
# threshold 100%. Jangan diperlakukan sebagai error.
echo
echo "Hasil yang diharapkan: 1 dimension / 1 rule FAILED."
echo "  rule id    -> GAGAL (10% null, threshold 1.0)   <- ini memang seharusnya gagal"
echo "  rule email -> LULUS (~10.5% invalid, threshold .85)"

pause "Klik Check my progress Task 4 sekarang.
Kalau belum hijau, buka Knowledge Catalog > Govern > Data profiling & quality >
$SCAN_ID, lalu klik Run Now di Console."

# ----------------------------------------------------------------- Task 5
step "Task 5: MANUAL — query hasil harus dijalankan dari Console"

echo "Pratinjau query kegagalan yang tersimpan (ini TIDAK menghijaukan checkpoint):"
bq --project_id="$PROJECT" query --use_legacy_sql=false --format=pretty \
  "SELECT rule_failed_records_query FROM \`$PROJECT.$DQ_DATASET.$DQ_TABLE\`" || true

cat <<EOF

Buka Console > BigQuery > SQL Editor dan kerjakan DI SANA:

  1. Preview tabel $PROJECT.$DQ_DATASET.$DQ_TABLE
  2. Salin isi kolom rule_failed_records_query (ada 2 baris: email dan id)
  3. Jalankan kedua query itu di SQL Editor (keduanya dimulai dengan WITH)

Lalu klik Check my progress Task 5.
EOF

echo
echo "=============================================================="
echo ">> Selesai. Otomatis: Task 1, 3, 4 (60 poin)."
echo "   Manual di Console: Task 2 dan Task 5 (40 poin)."
echo "=============================================================="
