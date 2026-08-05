#!/usr/bin/env bash
# GSP375 - Share Data using Google Data Cloud: Challenge Lab
#
#   curl -sLO .../gsp375.sh
#   bash gsp375.sh partner    # Cloud Shell Data Sharing Partner Project
#   bash gsp375.sh customer   # Cloud Shell Customer Project
#
# Checkpoint:
#   1 - Create the partner authorized view                  (fase partner)
#   2 - Authorize the view + IAM untuk customer user        (fase partner)
#   3 - Create the customer authorized view                 (fase customer)
#   4 - Authorize the view + IAM untuk partner user         (fase customer)
#   5 - Connect BigQuery to Data Studio                     (MANUAL, lihat bawah)
#
# SKOR MAKSIMUM LEWAT SCRIPT: 80/100.
# Checkpoint terakhir menilai report Looker Studio, yang tidak punya API.
# Grader lab keluarga ini memang bisa melihatnya (terbukti di gsp1042), jadi
# bagian itu wajib dikerjakan manual. Langkahnya dicetak di penutup.
#
# Nama view diacak per peserta (authorized_view_XXXX,
# customer_authorized_view_XXXX), jadi ditanyakan di awal.
#
# Task 2 lab (UPDATE county di customer_info) tidak punya checkpoint tapi
# tetap dijalankan — tanpa itu view customer isinya kosong.
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
  partner|customer) ;;
  *) echo "Pakai: bash gsp375.sh <partner|customer>"; exit 1 ;;
esac

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Fase   : $PHASE"
echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Tambah entry ke access[] sebuah dataset lalu update. Idempoten.
authorize_entry() {
  local dataset="$1" entry="$2" tmp=/tmp/gsp375_ds.json
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
  ask PARTNER_VIEW "" "Nama partner view (mis. authorized_view_pzlt)"
  ask CUSTOMER_USER "" "Email Customer (student-...@qwiklabs.net)"
  for v in PARTNER_VIEW CUSTOMER_USER; do
    [[ -n "${!v}" ]] || { echo "$v wajib diisi, lihat teks Task 1 di halaman lab."; exit 1; }
  done

  DATASET="demo_dataset"

  step "Task 1: Buat $DATASET.$PARTNER_VIEW"
  if bq show "${PROJECT}:${DATASET}.${PARTNER_VIEW}" >/dev/null 2>&1; then
    echo "View sudah ada, lewati."
  else
    bq mk --use_legacy_sql=false \
      --view 'SELECT
 *
FROM
 `bigquery-public-data.geo_us_boundaries.zip_codes`' \
      "${PROJECT}:${DATASET}.${PARTNER_VIEW}"
  fi
  bq ls "${PROJECT}:${DATASET}"

  step "Task 1: Otorisasi view pada dataset $DATASET"
  authorize_entry "$DATASET" \
    "{\"view\": {\"projectId\": \"$PROJECT\", \"datasetId\": \"$DATASET\", \"tableId\": \"$PARTNER_VIEW\"}}"

  step "Task 1: BigQuery Data Viewer untuk customer"
  bq add-iam-policy-binding \
    --member="user:${CUSTOMER_USER}" --role=roles/bigquery.dataViewer \
    "${PROJECT}:${DATASET}.${PARTNER_VIEW}"

  cat <<EOF

==============================================================
FASE PARTNER SELESAI!

Klik Check my progress untuk dua checkpoint pertama.

Project partner ini: $PROJECT
Catat ID-nya, dibutuhkan di fase customer.

Lanjut: buka Customer Project Console -> Cloud Shell:
  PARTNER_PROJECT=$PROJECT PARTNER_VIEW=$PARTNER_VIEW \\
  bash gsp375.sh customer
==============================================================
EOF
  exit 0
fi

# ================================================================== customer
ask PARTNER_PROJECT "" "Project ID Data Sharing Partner"
ask PARTNER_VIEW "" "Nama partner view (mis. authorized_view_pzlt)"
ask CUSTOMER_VIEW "" "Nama customer view (mis. customer_authorized_view_yodr)"
ask PARTNER_USER "" "Email Data Sharing Partner (student-...@qwiklabs.net)"
for v in PARTNER_PROJECT PARTNER_VIEW CUSTOMER_VIEW PARTNER_USER; do
  [[ -n "${!v}" ]] || { echo "$v wajib diisi."; exit 1; }
done

DATASET="customer_dataset"
CUST_TABLE="${PROJECT}.${DATASET}.customer_info"

step "Task 2: UPDATE kolom county di customer_info"
bq query --use_legacy_sql=false "UPDATE
 \`${CUST_TABLE}\` cust
SET
cust.county=vw.county
FROM
\`${PARTNER_PROJECT}.demo_dataset.${PARTNER_VIEW}\` vw
WHERE
vw.zip_code=cust.postal_code"

step "Task 3: Buat $DATASET.$CUSTOMER_VIEW"
if bq show "${PROJECT}:${DATASET}.${CUSTOMER_VIEW}" >/dev/null 2>&1; then
  echo "View sudah ada, lewati."
else
  bq mk --use_legacy_sql=false \
    --view "SELECT
  county,
COUNT(1) AS Count
FROM
 \`${CUST_TABLE}\` cust
GROUP BY
 county
HAVING county is not null" \
    "${PROJECT}:${DATASET}.${CUSTOMER_VIEW}"
fi
bq query --use_legacy_sql=false --max_rows=10 \
  "SELECT * FROM \`${PROJECT}.${DATASET}.${CUSTOMER_VIEW}\`"

step "Task 3: Otorisasi view pada dataset $DATASET"
authorize_entry "$DATASET" \
  "{\"view\": {\"projectId\": \"$PROJECT\", \"datasetId\": \"$DATASET\", \"tableId\": \"$CUSTOMER_VIEW\"}}"

step "Task 3: BigQuery Data Viewer untuk partner"
bq add-iam-policy-binding \
  --member="user:${PARTNER_USER}" --role=roles/bigquery.dataViewer \
  "${PROJECT}:${DATASET}.${CUSTOMER_VIEW}"

cat <<EOF

==============================================================
FASE CUSTOMER SELESAI!

Klik Check my progress untuk dua checkpoint berikutnya.

TASK 4 WAJIB MANUAL (checkpoint terakhir, tidak ada API-nya).
Kerjakan DENGAN AKUN PARTNER, bukan akun customer ini:

  1. Buka lookerstudio.google.com dari jendela console PARTNER
  2. Blank Report -> cari BigQuery -> Authorize -> Allow
  3. Panel kiri MY PROJECTS -> project customer ($PROJECT)
     -> $DATASET -> $CUSTOMER_VIEW
     -> Add -> Add to report
  4. Ganti judul report jadi "Data Sharing Partner Vizualization"
     (ejaan 'Vizualization' memang begitu di instruksi lab)
  5. Insert -> Column chart (Vertical bar chart)
  6. Dimension: county
     Breakdown Dimension: Count
     Metric: Count

Kalau MY PROJECTS cuma menampilkan project partner dengan
demo_dataset, berarti Looker Studio masih pakai sesi akun yang
salah. Sign out, masuk sebagai partner, ulangi.
==============================================================
EOF
