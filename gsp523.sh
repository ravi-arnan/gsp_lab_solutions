#!/usr/bin/env bash
# GSP523 - Implement Multimodal Vector Search with BigQuery: Challenge Lab
#
#   curl -sL https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp523.sh | bash
#
# Checkpoint:
#   Task 1 - Create a source connection and grant IAM permissions
#   Task 2 - Create an object table
#   Task 3 - Create a new model and generate embeddings
#   Task 4 - Run a vector search
#
# Dataset (`gcc_bqml_dataset`) sudah disiapkan lab. Script MENDETEKSI dataset
# itu sendiri lalu mengambil dua hal darinya: lokasi (region connection wajib
# sama dengan dataset) dan prefiks nama (`gcc`), yang dipakai untuk menebak
# nama tabel/model. Jadi varian lab dengan prefiks lain tetap jalan tanpa
# diubah. Semua nama masih bisa ditimpa lewat env var.
#
# LAMA: ~5-8 menit. Yang lama: propagasi IAM (60 detik) dan ML.GENERATE_EMBEDDING
# yang memanggil multimodalembedding@001 sekali per gambar di bucket.

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# ================================================================= persiapan
step "Persiapan: API, dataset, dan penamaan"

gcloud services enable bigqueryconnection.googleapis.com aiplatform.googleapis.com \
  bigquery.googleapis.com --quiet

# Cari dataset bawaan lab. Namanya berakhiran _bqml_dataset; prefiks di depannya
# (gcc) dipakai lagi untuk nama tabel dan model.
if [[ -z "${DATASET:-}" ]]; then
  DATASET=$(bq ls --format=json --max_results=1000 2>/dev/null \
    | jq -r '.[].datasetReference.datasetId' | grep -m1 'bqml_dataset' || true)
fi
[[ -n "${DATASET:-}" ]] || { echo "Dataset *_bqml_dataset tidak ketemu. Isi manual: DATASET=<nama> bash $0"; exit 1; }
echo "DATASET = $DATASET"

PREFIX="${DATASET%_bqml_dataset}"
echo "PREFIX = $PREFIX"

# Region connection HARUS sama dengan lokasi dataset, kalau tidak object table
# dan model ditolak dengan "Not found: Connection".
REGION="${REGION:-$(bq show --format=json "${PROJECT}:${DATASET}" | jq -r '.location' | tr 'A-Z' 'a-z')}"
echo "REGION = $REGION"

CONN="${CONN:-vector_conn}"
OBJECT_TABLE="${OBJECT_TABLE:-${PREFIX}_image_object_table}"
MODEL="${MODEL:-${PREFIX}_embedding}"
EMBED_TABLE="${EMBED_TABLE:-${PREFIX}_retail_store_embeddings}"
SEARCH_TABLE="${SEARCH_TABLE:-${PREFIX}_vector_search_table}"
BUCKET="${BUCKET:-$PROJECT}"
ask SEARCH_PHRASE "Men Sweaters" "Frasa pencarian (Task 4)"
TOP_K="${TOP_K:-2}"

echo "CONN=$CONN OBJECT_TABLE=$OBJECT_TABLE MODEL=$MODEL"
echo "EMBED_TABLE=$EMBED_TABLE SEARCH_TABLE=$SEARCH_TABLE BUCKET=gs://$BUCKET"

# Semua query dijalankan dengan --location eksplisit; bq tidak selalu bisa
# menyimpulkannya dari nama tabel di dalam SQL.
run_sql() { bq query --project_id="$PROJECT" --location="$REGION" --use_legacy_sql=false --quiet "$1"; }

# ------------------------------------------------------------------- Task 1
step "Task 1: connection $CONN + IAM"

if bq show --connection --project_id="$PROJECT" --location="$REGION" "$CONN" >/dev/null 2>&1; then
  echo "--- Connection $CONN sudah ada"
else
  bq mk --connection --project_id="$PROJECT" --location="$REGION" \
    --connection_type=CLOUD_RESOURCE "$CONN"
fi

# Service account-nya dibuat otomatis oleh connection, namanya tidak bisa ditebak.
SA=$(bq show --connection --format=json --project_id="$PROJECT" --location="$REGION" "$CONN" \
  | jq -r '.cloudResource.serviceAccountId')
[[ -n "$SA" && "$SA" != "null" ]] || { echo "Service account connection tidak terbaca."; exit 1; }
echo "--- Service account: $SA"

# "Agent Platform User" adalah nama baru dari Vertex AI User.
for ROLE in roles/bigquery.dataOwner roles/storage.objectViewer roles/aiplatform.user; do
  echo "--- Binding $ROLE"
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA" --role="$ROLE" \
    --condition=None --quiet >/dev/null
done

echo "--- Menunggu 60 detik propagasi IAM sebelum memakai connection"
sleep 60

# ------------------------------------------------------------------- Task 2
step "Task 2: object table $OBJECT_TABLE"

run_sql "
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT}.${DATASET}.${OBJECT_TABLE}\`
WITH CONNECTION \`${PROJECT}.${REGION}.${CONN}\`
OPTIONS (
  object_metadata = 'SIMPLE',
  uris = ['gs://${BUCKET}/*']
)"

# ------------------------------------------------------------------- Task 3
step "Task 3: model $MODEL + tabel embedding $EMBED_TABLE"

run_sql "
CREATE OR REPLACE MODEL \`${PROJECT}.${DATASET}.${MODEL}\`
REMOTE WITH CONNECTION \`${PROJECT}.${REGION}.${CONN}\`
OPTIONS (endpoint = 'multimodalembedding@001')"

echo "--- Membangkitkan embedding (satu panggilan model per gambar, sabar)"
run_sql "
CREATE OR REPLACE TABLE \`${PROJECT}.${DATASET}.${EMBED_TABLE}\` AS
SELECT *, REGEXP_EXTRACT(uri, r'[^/]+$') AS product_name
FROM ML.GENERATE_EMBEDDING(
  MODEL \`${PROJECT}.${DATASET}.${MODEL}\`,
  TABLE \`${PROJECT}.${DATASET}.${OBJECT_TABLE}\`
)"

# Baris yang gagal di-embed tetap masuk tabel dengan ml_generate_embedding_status
# terisi; kalau semuanya gagal, VECTOR_SEARCH di Task 4 akan kosong.
echo "--- Ringkasan hasil embedding:"
bq query --project_id="$PROJECT" --location="$REGION" --use_legacy_sql=false \
  "SELECT COUNT(*) AS baris,
          COUNTIF(ml_generate_embedding_status != '') AS gagal
   FROM \`${PROJECT}.${DATASET}.${EMBED_TABLE}\`"

# ------------------------------------------------------------------- Task 4
step "Task 4: vector search -> $SEARCH_TABLE"

run_sql "
CREATE OR REPLACE TABLE \`${PROJECT}.${DATASET}.${SEARCH_TABLE}\` AS
SELECT base.uri, base.product_name, base.content_type, distance
FROM VECTOR_SEARCH(
  TABLE \`${PROJECT}.${DATASET}.${EMBED_TABLE}\`, 'ml_generate_embedding_result',
  (
    SELECT ml_generate_embedding_result AS embedding_col
    FROM ML.GENERATE_EMBEDDING(
      MODEL \`${PROJECT}.${DATASET}.${MODEL}\`,
      (SELECT '${SEARCH_PHRASE}' AS content),
      STRUCT(TRUE AS flatten_json_output)
    )
  ),
  top_k => ${TOP_K},
  distance_type => 'COSINE'
)"

echo "--- Isi $SEARCH_TABLE:"
bq query --project_id="$PROJECT" --location="$REGION" --use_legacy_sql=false \
  "SELECT * FROM \`${PROJECT}.${DATASET}.${SEARCH_TABLE}\` ORDER BY distance"

cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk:
  Task 1 - Create a source connection and grant IAM permissions
  Task 2 - Create an object table
  Task 3 - Create a new model and generate embeddings
  Task 4 - Run a vector search
--------------------------------------------------------------
EOF
