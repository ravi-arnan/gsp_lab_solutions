#!/usr/bin/env bash
# GSP1041 - Data Publishing on BigQuery using Authorized Views for Data Sharing Partners
#
#   curl -sLO .../gsp1041.sh
#   bash gsp1041.sh partner    # di Cloud Shell Data Sharing Partner Project
#   bash gsp1041.sh a          # di Cloud Shell Customer Project A
#   bash gsp1041.sh b          # di Cloud Shell Customer Project B
#
# Checkpoint:
#   Task 1 - Create Authorized Views                  (fase partner)
#   Task 2 - Assign IAM permissions to both the views (fase partner)
#   Task 3 - Grant permissions to the users           (fase partner)
#   Task 4 - Verify shared authorized views           (fase a + fase b)
#
# Lab ini memakai TIGA project dengan kredensial berbeda, jadi tidak bisa
# dijalankan sekali dari satu Cloud Shell. Buka console tiap project dari
# panel lab, lalu jalankan fase yang sesuai di Cloud Shell masing-masing.
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
  partner|a|b) ;;
  *) echo "Pakai: bash gsp1041.sh <partner|a|b>"; exit 1 ;;
esac

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PUBLIC_TABLE='bigquery-public-data.geo_us_boundaries.zip_codes'

echo "Fase   : $PHASE"
echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# =================================================================== partner
if [[ "$PHASE" == "partner" ]]; then
  ask CUSTOMER_A_USER "" "Email Customer A (student-...@qwiklabs.net)"
  ask CUSTOMER_B_USER "" "Email Customer B (student-...@qwiklabs.net)"
  for v in CUSTOMER_A_USER CUSTOMER_B_USER; do
    [[ -n "${!v}" ]] || { echo "$v wajib diisi, lihat teks Task 3 di halaman lab."; exit 1; }
  done

  DATASET="demo_dataset"

  # ------------------------------------------------------------- Task 1
  step "Task 1: Buat authorized_view_a (TX) dan authorized_view_b (CA)"
  make_view() {  # $1 = nama view, $2 = state code
    if bq show "${PROJECT}:${DATASET}.$1" >/dev/null 2>&1; then
      echo "View $1 sudah ada, lewati."
    else
      bq mk --use_legacy_sql=false \
        --view "SELECT * FROM \`${PUBLIC_TABLE}\` WHERE state_code=\"$2\" LIMIT 4000" \
        "${PROJECT}:${DATASET}.$1"
    fi
  }
  make_view authorized_view_a TX
  make_view authorized_view_b CA
  bq ls "${PROJECT}:${DATASET}"

  # ------------------------------------------------------------- Task 2
  step "Task 2: Otorisasi kedua view pada dataset $DATASET"
  bq show --format=prettyjson "${PROJECT}:${DATASET}" > /tmp/gsp1041_ds.json
  PROJECT="$PROJECT" DATASET="$DATASET" python3 - <<'PY'
import json, os, pathlib

path = pathlib.Path("/tmp/gsp1041_ds.json")
ds = json.loads(path.read_text())
access = ds.setdefault("access", [])
project, dataset = os.environ["PROJECT"], os.environ["DATASET"]

for view in ("authorized_view_a", "authorized_view_b"):
    entry = {"view": {"projectId": project, "datasetId": dataset, "tableId": view}}
    if entry not in access:
        access.append(entry)
        print("tambah otorisasi:", view)
    else:
        print("sudah terotorisasi:", view)

path.write_text(json.dumps(ds))
PY
  bq update --source /tmp/gsp1041_ds.json "${PROJECT}:${DATASET}"
  bq show --format=prettyjson "${PROJECT}:${DATASET}" | grep -A3 '"view"' || true

  # ------------------------------------------------------------- Task 3
  step "Task 3: Beri BigQuery Data Viewer ke tiap customer"
  bq add-iam-policy-binding \
    --member="user:${CUSTOMER_A_USER}" --role=roles/bigquery.dataViewer \
    "${PROJECT}:${DATASET}.authorized_view_a"
  bq add-iam-policy-binding \
    --member="user:${CUSTOMER_B_USER}" --role=roles/bigquery.dataViewer \
    "${PROJECT}:${DATASET}.authorized_view_b"

  cat <<EOF

==============================================================
FASE PARTNER SELESAI!

Klik Check my progress untuk Task 1, 2, dan 3.

Project partner ini: $PROJECT
Catat ID-nya, dibutuhkan di dua fase berikutnya.

Lanjut:
  Buka Customer Project A Console -> Cloud Shell:
    bash gsp1041.sh a
  Buka Customer Project B Console -> Cloud Shell:
    bash gsp1041.sh b
==============================================================
EOF
  exit 0
fi

# =============================================================== customer a/b
ask PARTNER_PROJECT "" "Project ID Data Sharing Partner"
[[ -n "$PARTNER_PROJECT" ]] || { echo "PARTNER_PROJECT wajib diisi."; exit 1; }

if [[ "$PHASE" == "a" ]]; then
  VIEW="authorized_view_a";  DATASET="customer_a_dataset"; TABLE="customer_a_table"
  OTHER_VIEW="authorized_view_b"
else
  VIEW="authorized_view_b";  DATASET="customer_b_dataset"; TABLE="customer_b_table"
  OTHER_VIEW="authorized_view_a"
fi

SRC="${PARTNER_PROJECT}.demo_dataset.${VIEW}"

step "Task 4: Query view partner lalu simpan sebagai $DATASET.$TABLE"
bq query --use_legacy_sql=false --max_rows=5 "SELECT * FROM \`${SRC}\` LIMIT 5"

if bq show "${PROJECT}:${DATASET}.${TABLE}" >/dev/null 2>&1; then
  echo "View $TABLE sudah ada, lewati."
else
  bq mk --use_legacy_sql=false \
    --view "SELECT * FROM \`${SRC}\`" \
    "${PROJECT}:${DATASET}.${TABLE}"
fi
bq ls "${PROJECT}:${DATASET}"

step "Join dengan customer_info milik customer sendiri"
bq query --use_legacy_sql=false --max_rows=10 "
SELECT geos.zip_code, geos.city, cust.last_name, cust.first_name
FROM \`${PROJECT}.${DATASET}.customer_info\` AS cust
JOIN \`${SRC}\` AS geos
ON geos.zip_code = cust.postal_code" || true

step "Bukti isolasi: query $OTHER_VIEW harus DITOLAK"
if bq query --use_legacy_sql=false --max_rows=1 \
     "SELECT * FROM \`${PARTNER_PROJECT}.demo_dataset.${OTHER_VIEW}\`" 2>&1 | head -5; then
  echo "(kalau di atas muncul Access Denied, itu memang yang diharapkan)"
fi

cat <<EOF

==============================================================
FASE $PHASE SELESAI!

$DATASET.$TABLE sudah dibuat di project $PROJECT.

Klik Check my progress untuk Task 4 setelah KEDUA fase
customer (a dan b) selesai.
==============================================================
EOF
