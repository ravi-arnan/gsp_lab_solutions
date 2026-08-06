#!/usr/bin/env bash
# GSP1144 - Knowledge Catalog: Qwik Start - Command Line
#
# PENTING: script ini DUA FASE, jangan digabung.
#   Task 4 menghapus semua yang dibuat Task 1-3. Kalau create dan delete
#   dijalankan sekaligus, checkpoint task 1-3 gagal karena resource sudah hilang.
#
#   1) bash gsp1144.sh create   -> Task 1, 2, 3
#   2) klik Check my progress untuk task 1, 2, DAN 3 sampai hijau
#   3) bash gsp1144.sh delete   -> Task 4
#
# Checkpoint:
#   Task 1 (25 pts) - Create a Knowledge Catalog lake
#   Task 2 (25 pts) - Add a zone to your lake
#   Task 3 (25 pts) - Attach an asset to a zone
#   Task 4 (25 pts) - Delete assets, zone and dataplex lake
#
# Lab ini memakai region tetap us-east1. Override kalau lab-mu beda:
#   REGION=us-central1 bash gsp1144.sh create

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
ask REGION "us-east1" "Region (cocokkan dengan panel lab)"
LAKE_ID="ecommerce"
ZONE_ID="orders-curated-zone"
ASSET_ID="orders-curated-dataset"
DATASET="orders"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PHASE="${1:-}"
case "$PHASE" in
  create|delete) ;;
  *) echo "Pakai: bash gsp1144.sh create   (Task 1-3)"
     echo "       bash gsp1144.sh delete   (Task 4, jalankan SETELAH check my progress task 1-3 hijau)"
     exit 1 ;;
esac

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Fase   : $PHASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== CREATE
if [[ "$PHASE" == "create" ]]; then

  step "Enable Dataplex API (bisa ~1 menit)"
  gcloud services enable dataplex.googleapis.com --project="$PROJECT"

  step "Task 1: lake 'Ecommerce' di $REGION (bisa ~3 menit)"
  if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
    echo "Lake sudah ada, dilewat."
  else
    gcloud dataplex lakes create "$LAKE_ID" \
      --project="$PROJECT" \
      --location="$REGION" \
      --display-name="Ecommerce" \
      --description="Ecommerce Domain"
  fi

  step "Task 2: zone 'Orders Curated Zone' (CURATED, regional, discovery tiap jam) (bisa ~2 menit)"
  if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
    echo "Zone sudah ada, dilewat."
  else
    gcloud dataplex zones create "$ZONE_ID" \
      --project="$PROJECT" \
      --location="$REGION" \
      --lake="$LAKE_ID" \
      --display-name="Orders Curated Zone" \
      --resource-location-type=SINGLE_REGION \
      --type=CURATED \
      --discovery-enabled \
      --discovery-schedule="0 * * * *"
  fi

  step "Task 3a: BigQuery dataset '$DATASET'"
  if bq --project_id="$PROJECT" show --dataset "$PROJECT:$DATASET" >/dev/null 2>&1; then
    echo "Dataset sudah ada, dilewat."
  else
    bq --project_id="$PROJECT" mk --location="$REGION" --dataset "$DATASET"
  fi

  step "Task 3b: attach asset 'Orders Curated Dataset' ke zone (bisa ~2 menit)"
  if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
    echo "Asset sudah ada, dilewat."
  else
    gcloud dataplex assets create "$ASSET_ID" \
      --project="$PROJECT" \
      --location="$REGION" \
      --lake="$LAKE_ID" \
      --zone="$ZONE_ID" \
      --display-name="Orders Curated Dataset" \
      --resource-type=BIGQUERY_DATASET \
      --resource-name="projects/$PROJECT/datasets/$DATASET" \
      --discovery-enabled
  fi

  step "Hasil"
  gcloud dataplex lakes list  --project="$PROJECT" --location="$REGION"
  gcloud dataplex zones list  --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID"
  gcloud dataplex assets list --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID"

  cat <<EOF

--------------------------------------------------------------
BERHENTI DI SINI.

Klik Check my progress untuk task 1, 2, dan 3 sampai hijau.
Fase delete akan MENGHAPUS resource ini, jadi kalau dijalankan
sekarang, task 1-3 tidak akan bisa diverifikasi lagi.

Kalau ketiganya sudah hijau, baru jalankan:
  bash gsp1144.sh delete
--------------------------------------------------------------
EOF

# ================================================================== DELETE
else

  # `|| echo` supaya fase delete aman diulang kalau gagal di tengah.
  step "Task 4a: detach asset '$ASSET_ID' (dataset BigQuery tidak ikut terhapus)"
  gcloud dataplex assets delete "$ASSET_ID" --quiet \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    || echo "Asset tidak ada, dilewat."

  step "Task 4b: hapus zone '$ZONE_ID'"
  gcloud dataplex zones delete "$ZONE_ID" --quiet \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
    || echo "Zone tidak ada, dilewat."

  step "Task 4c: hapus lake '$LAKE_ID'"
  gcloud dataplex lakes delete "$LAKE_ID" --quiet \
    --project="$PROJECT" --location="$REGION" \
    || echo "Lake tidak ada, dilewat."

  step "Verifikasi: daftar lake harus kosong"
  gcloud dataplex lakes list --project="$PROJECT" --location="$REGION"

  echo
  echo "SELESAI! Klik Check my progress untuk verifikasi:"
  echo "  Task 4 - Delete assets, zone and dataplex lake"
fi
