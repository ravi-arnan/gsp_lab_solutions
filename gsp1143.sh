#!/usr/bin/env bash
# GSP1143 - Knowledge Catalog (Dataplex): Qwik Start - Console
#
# PENTING: script ini DUA FASE, jangan digabung.
#   Task 4 menghapus semua yang dibuat Task 1-3. Kalau create dan delete
#   dijalankan sekaligus, checkpoint task 1-3 gagal karena resource sudah hilang.
#
#   1) bash gsp1143.sh create   -> Task 1, 2, 3
#   2) klik Check my progress untuk task 1, 2, DAN 3 sampai hijau
#   3) bash gsp1143.sh delete   -> Task 4
#
# REGION: di halaman lab tertulis "Region ____" dan diisi per instance.
# Cocokkan sebelum jalan, override begini kalau bukan us-central1:
#   REGION=europe-west1 bash gsp1143.sh create

set -euo pipefail

# ----------------------------------------------------------------- parameter
REGION="${REGION:-us-east1}"
LAKE_ID="sensors"
LAKE_NAME="sensors"
ZONE_ID="temperature-raw-data"
ZONE_NAME="temperature raw data"
ASSET_ID="measurements"
ASSET_NAME="measurements"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET="$PROJECT"   # lab minta nama bucket = Project ID

[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PHASE="${1:-}"
case "$PHASE" in
  create|delete) ;;
  *) echo "Pakai: bash gsp1143.sh create   (Task 1-3)"
     echo "       bash gsp1143.sh delete   (Task 4, jalankan SETELAH check my progress task 1-3 hijau)"
     exit 1 ;;
esac

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "Fase   : $PHASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== CREATE
if [[ "$PHASE" == "create" ]]; then

  step "Enable Cloud Dataplex API (bisa ~1 menit)"
  gcloud services enable dataplex.googleapis.com --project="$PROJECT"

  step "Task 1: lake '$LAKE_NAME' di $REGION (bisa ~3 menit)"
  gcloud dataplex lakes create "$LAKE_ID" \
    --project="$PROJECT" \
    --location="$REGION" \
    --display-name="$LAKE_NAME"

  step "Task 2: zone '$ZONE_NAME' (RAW, regional, discovery on) (bisa ~2 menit)"
  gcloud dataplex zones create "$ZONE_ID" \
    --project="$PROJECT" \
    --location="$REGION" \
    --lake="$LAKE_ID" \
    --display-name="$ZONE_NAME" \
    --type=RAW \
    --resource-location-type=SINGLE_REGION \
    --discovery-enabled

  step "Task 3a: bucket gs://$BUCKET"
  if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Bucket sudah ada, dilewat."
  else
    gcloud storage buckets create "gs://$BUCKET" \
      --project="$PROJECT" \
      --location="$REGION" \
      --uniform-bucket-level-access \
      --public-access-prevention
  fi

  step "Task 3b: attach asset '$ASSET_NAME' ke zone"
  # Tanpa flag discovery = inherit dari zone, sesuai instruksi lab.
  gcloud dataplex assets create "$ASSET_ID" \
    --project="$PROJECT" \
    --location="$REGION" \
    --lake="$LAKE_ID" \
    --zone="$ZONE_ID" \
    --display-name="$ASSET_NAME" \
    --resource-type=STORAGE_BUCKET \
    --resource-name="projects/$PROJECT/buckets/$BUCKET"

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
  bash gsp1143.sh delete
--------------------------------------------------------------
EOF

# ================================================================== DELETE
else

  step "Task 4a: detach asset '$ASSET_ID' (data di bucket tidak ikut terhapus)"
  gcloud dataplex assets delete "$ASSET_ID" --quiet \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID"

  step "Task 4b: hapus zone '$ZONE_ID'"
  gcloud dataplex zones delete "$ZONE_ID" --quiet \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID"

  step "Task 4c: hapus lake '$LAKE_ID'"
  gcloud dataplex lakes delete "$LAKE_ID" --quiet \
    --project="$PROJECT" --location="$REGION"

  step "Verifikasi: daftar lake harus kosong"
  gcloud dataplex lakes list --project="$PROJECT" --location="$REGION"

  echo
  echo "Selesai. Klik Check my progress untuk task 4."
fi
