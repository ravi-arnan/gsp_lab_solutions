#!/usr/bin/env bash
# GSP1043 - Consuming Customer Specific Datasets from Data Sharing Partners using BigQuery
#
#   curl -sLO .../gsp1043.sh
#   bash gsp1043.sh partner     # Cloud Shell Data Sharing Partner Project
#   bash gsp1043.sh publisher   # Cloud Shell Data Publisher Project
#   bash gsp1043.sh customer    # Cloud Shell Customer (Data Twin) Project
#   bash gsp1043.sh insert      # kembali ke Partner, Task 4 (tanpa checkpoint)
#
# Checkpoint:
#   Task 1 - Created an Authorized Table                    (fase partner)
#   Task 2 - Create an authorized view in the Data Publishing project (fase publisher)
#   Task 3 - Access the authorized view as a Data Twin      (fase customer)
#   Task 4 - Confirm functionality (tanpa checkpoint)       (fase insert)
#
# TIGA project dengan kredensial berbeda, jadi tidak bisa sekali jalan dari
# satu Cloud Shell. Buka console tiap project dari panel lab, lalu jalankan
# fase yang sesuai di Cloud Shell masing-masing. Urutannya mengikat: publisher
# butuh tabel dari partner, customer butuh view dari publisher.
#
# LAMA: ~2 menit per fase.

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

PHASE="${1:-}"
case "$PHASE" in
  partner|publisher|customer|insert) ;;
  *) echo "Pakai: bash gsp1043.sh <partner|publisher|customer|insert>"; exit 1 ;;
esac

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Fase   : $PHASE"
echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Tambahkan entry ke access[] sebuah dataset lalu update. $1 = dataset,
# $2 = JSON entry. Idempoten, entry yang sudah ada tidak diduplikasi.
authorize_entry() {
  local dataset="$1" entry="$2" tmp=/tmp/gsp1043_ds.json
  bq show --format=prettyjson "${PROJECT}:${dataset}" > "$tmp"
  ENTRY="$entry" python3 - "$tmp" <<'PY'
import json, os, sys, pathlib
path = pathlib.Path(sys.argv[1])
ds = json.loads(path.read_text())
access = ds.setdefault("access", [])
entry = json.loads(os.environ["ENTRY"])
if entry in access:
    print("sudah terotorisasi:", entry)
else:
    access.append(entry)
    print("tambah otorisasi:", entry)
path.write_text(json.dumps(ds))
PY
  bq update --source "$tmp" "${PROJECT}:${dataset}"
}

# =================================================================== partner
if [[ "$PHASE" == "partner" ]]; then
  ask PUBLISHER_USER "" "Email Data Publisher (student-...@qwiklabs.net)"
  ask CUSTOMER_USER "" "Email Customer/Data Twin (student-...@qwiklabs.net)"
  for v in PUBLISHER_USER CUSTOMER_USER; do
    [[ -n "${!v}" ]] || { echo "$v wajib diisi, lihat teks Task 1 di halaman lab."; exit 1; }
  done

  DATASET="demo_dataset"

  step "Task 1: Buat authorized_table (top 10 kota per state)"
  bq query --use_legacy_sql=false --replace \
    --destination_table="${PROJECT}:${DATASET}.authorized_table" \
    'SELECT * FROM (
SELECT *, ROW_NUMBER() OVER (PARTITION BY state_code ORDER BY area_land_meters DESC) AS cities_by_area
FROM `bigquery-public-data.geo_us_boundaries.zip_codes`) cities
WHERE cities_by_area <= 10 ORDER BY cities.state_code
LIMIT 1000'
  bq show "${PROJECT}:${DATASET}.authorized_table"

  step "Task 1: Authorize dataset $DATASET"
  authorize_entry "$DATASET" \
    "{\"dataset\": {\"dataset\": {\"projectId\": \"$PROJECT\", \"datasetId\": \"$DATASET\"}, \"targetTypes\": [\"VIEWS\"]}}"

  step "Task 1: Beri BigQuery Data Viewer ke publisher dan customer"
  for u in "$PUBLISHER_USER" "$CUSTOMER_USER"; do
    bq add-iam-policy-binding \
      --member="user:${u}" --role=roles/bigquery.dataViewer \
      "${PROJECT}:${DATASET}.authorized_table"
  done

  cat <<EOF

==============================================================
FASE PARTNER SELESAI!

Klik Check my progress untuk Task 1.

Project partner ini: $PROJECT
Catat ID-nya, dibutuhkan di fase publisher.

Lanjut: buka Data Publisher Project Console -> Cloud Shell:
  PARTNER_PROJECT=$PROJECT bash gsp1043.sh publisher
==============================================================
EOF
  exit 0
fi

# ================================================================= publisher
if [[ "$PHASE" == "publisher" ]]; then
  ask PARTNER_PROJECT "" "Project ID Data Sharing Partner"
  ask CUSTOMER_USER "" "Email Customer/Data Twin (student-...@qwiklabs.net)"
  for v in PARTNER_PROJECT CUSTOMER_USER; do
    [[ -n "${!v}" ]] || { echo "$v wajib diisi."; exit 1; }
  done

  DATASET="data_publisher_dataset"
  SRC="${PARTNER_PROJECT}.demo_dataset.authorized_table"

  step "Task 2: Buat authorized_view (state NY) dari tabel partner"
  bq query --use_legacy_sql=false --max_rows=5 \
    "SELECT * FROM \`${SRC}\` WHERE state_code=\"NY\" LIMIT 5"

  if bq show "${PROJECT}:${DATASET}.authorized_view" >/dev/null 2>&1; then
    echo "View authorized_view sudah ada, lewati."
  else
    bq mk --use_legacy_sql=false \
      --view "SELECT *
FROM \`${SRC}\`
WHERE state_code=\"NY\"
LIMIT 1000" \
      "${PROJECT}:${DATASET}.authorized_view"
  fi
  bq ls "${PROJECT}:${DATASET}"

  step "Task 2: Otorisasi authorized_view pada dataset $DATASET"
  authorize_entry "$DATASET" \
    "{\"view\": {\"projectId\": \"$PROJECT\", \"datasetId\": \"$DATASET\", \"tableId\": \"authorized_view\"}}"

  step "Task 2: Beri BigQuery Data Viewer ke customer"
  bq add-iam-policy-binding \
    --member="user:${CUSTOMER_USER}" --role=roles/bigquery.dataViewer \
    "${PROJECT}:${DATASET}.authorized_view"

  cat <<EOF

==============================================================
FASE PUBLISHER SELESAI!

Klik Check my progress untuk Task 2.

Project publisher ini: $PROJECT
Catat ID-nya, dibutuhkan di fase customer.

Lanjut: buka Customer (Data Twin) Project Console -> Cloud Shell:
  PUBLISHER_PROJECT=$PROJECT bash gsp1043.sh customer
==============================================================
EOF
  exit 0
fi

# ================================================================== customer
if [[ "$PHASE" == "customer" ]]; then
  ask PUBLISHER_PROJECT "" "Project ID Data Publisher"
  [[ -n "$PUBLISHER_PROJECT" ]] || { echo "PUBLISHER_PROJECT wajib diisi."; exit 1; }

  DATASET="customer_dataset"
  JOIN_SQL="SELECT cities.zip_code, cities.city, cities.state_code, customers.last_name, customers.first_name
FROM \`${PROJECT}.${DATASET}.customer_info\` AS customers
JOIN \`${PUBLISHER_PROJECT}.data_publisher_dataset.authorized_view\` AS cities
ON cities.state_code = customers.state"

  step "Task 3: Join data customer dengan authorized_view publisher"
  bq query --use_legacy_sql=false --max_rows=10 "$JOIN_SQL"

  step "Task 3: Simpan sebagai view $DATASET.customer_table"
  if bq show "${PROJECT}:${DATASET}.customer_table" >/dev/null 2>&1; then
    echo "View customer_table sudah ada, lewati."
  else
    bq mk --use_legacy_sql=false --view "$JOIN_SQL" "${PROJECT}:${DATASET}.customer_table"
  fi
  bq ls "${PROJECT}:${DATASET}"

  cat <<EOF

==============================================================
FASE CUSTOMER SELESAI!

Klik Check my progress untuk Task 3.

Task 4 (tanpa checkpoint) membuktikan Data Twin ikut terbarui:
  1. Kembali ke Data Sharing Partner Console -> Cloud Shell:
       bash gsp1043.sh insert
  2. Kembali ke sini, jalankan lagi query-nya:
       bq query --use_legacy_sql=false '$(echo "$JOIN_SQL" | tr '\n' ' ')'
     Baris "New City" harus ikut muncul.
==============================================================
EOF
  exit 0
fi

# ==================================================================== insert
step "Task 4: Sisipkan baris baru ke authorized_table"
bq query --use_legacy_sql=false \
  "INSERT INTO
 \`${PROJECT}.demo_dataset.authorized_table\` (zip_code,
   city,
   county,
   state_fips_code,
   state_code,
   state_name,
   fips_class_code,
   functional_status,
   area_land_meters,
   area_water_meters,
   cities_by_area)
VALUES
 (\"11012\", \"New City\", \"New County\", \"02\", \"NY\", \"New York\", \"B5\", \"S\", 123632007174.0, 544474039.0, 10)"

cat <<EOF

==============================================================
FASE INSERT SELESAI!

Baris "New City" sudah masuk ke authorized_table.

Kembali ke Customer (Data Twin) Console dan jalankan ulang
query join-nya — baris itu harus ikut muncul tanpa perlu
menyalin data apa pun. Itu inti demonstrasi Data Twin.

Task 4 tidak punya checkpoint.
==============================================================
EOF
