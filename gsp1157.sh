#!/usr/bin/env bash
# GSP1157 - Implementing Security in Knowledge Catalog
#
# LAB INI PAKAI DUA USER. Cloud Shell login sebagai User 1 saja, jadi:
#   Task 1, 2, 4  -> script ini (sebagai User 1)
#   Task 3, 5     -> HARUS lewat console UI sebagai User 2 (lihat docs/gsp1157.md)
#
# DUA FASE, jangan digabung. Task 4 mengganti role User 2 dari Reader jadi Writer.
# Kalau dijalankan sebelum checkpoint "Data Reader" diklik, checkpoint itu gagal.
#
#   1) USER2=<email> REGION=<region> bash gsp1157.sh reader   -> Task 1 + 2
#   2) klik Check my progress: "Create a lake, zone, and asset"
#                              "Assign Knowledge Catalog Data Reader role"
#   3) (opsional) Task 3: login UI sbg User 2, coba upload, HARUS gagal
#   4) USER2=<email> REGION=<region> bash gsp1157.sh writer   -> Task 4
#   5) klik Check my progress: "Assign Knowledge Catalog Data Writer role"
#   6) Task 5: login UI sbg User 2, upload file, harus berhasil

set -euo pipefail

# ----------------------------------------------------------------- parameter
REGION="${REGION:-us-central1}"
USER2="${USER2:-}"
LAKE_ID="customer-info-lake"
LAKE_NAME="Customer Info Lake"
ZONE_ID="customer-raw-zone"
ZONE_NAME="Customer Raw Zone"
ASSET_ID="customer-online-sessions"
ASSET_NAME="Customer Online Sessions"
ROLE_READER="roles/dataplex.dataReader"
ROLE_WRITER="roles/dataplex.dataWriter"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PHASE="${1:-}"
case "$PHASE" in
  reader|writer) ;;
  *) echo "Pakai: USER2=<email User 2> REGION=<region> bash gsp1157.sh reader"
     echo "       USER2=<email User 2> REGION=<region> bash gsp1157.sh writer"
     echo
     echo "Jalankan 'writer' hanya SETELAH checkpoint Data Reader hijau."
     exit 1 ;;
esac

[[ -n "$USER2" ]] || { echo "USER2 belum diisi. Ambil email User 2 dari panel Lab setup, lalu:"
                       echo "  USER2=student-02-xxxx@qwiklabs.net REGION=$REGION bash gsp1157.sh $PHASE"; exit 1; }

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "User 2 : $USER2"
echo "Fase   : $PHASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================== READER
if [[ "$PHASE" == "reader" ]]; then

  step "Enable Cloud Dataplex API"
  gcloud services enable dataplex.googleapis.com --project="$PROJECT"

  # Bucket disiapkan lab dengan pola '<sesuatu>-bucket'. Deteksi, jangan tebak.
  step "Cari bucket pre-created (pola *-bucket)"
  # Buang prefix gs:// dan slash kalau ada: format 'value(name)' tidak dijamin polos,
  # sementara --resource-name butuh nama telanjang.
  BUCKET="$(gcloud storage buckets list --project="$PROJECT" --format='value(name)' 2>/dev/null \
            | sed 's|^gs://||; s|/$||' | grep -- '-bucket$' | head -1 || true)"
  if [[ -z "$BUCKET" ]]; then
    echo "ERROR: tidak ada bucket berakhiran '-bucket' di project ini."
    echo "Bucket itu resource pre-created lab. Bucket yang ada sekarang:"
    gcloud storage buckets list --project="$PROJECT" --format='value(name)' || true
    exit 1
  fi
  echo "Bucket ketemu: $BUCKET"

  step "Task 1a: lake '$LAKE_NAME' (bisa ~3 menit)"
  if gcloud dataplex lakes describe "$LAKE_ID" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
    echo "Lake sudah ada, dilewat."
  else
    gcloud dataplex lakes create "$LAKE_ID" \
      --project="$PROJECT" --location="$REGION" --display-name="$LAKE_NAME"
  fi

  step "Task 1b: zone '$ZONE_NAME' (RAW, regional, discovery on) (bisa ~2 menit)"
  if gcloud dataplex zones describe "$ZONE_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" >/dev/null 2>&1; then
    echo "Zone sudah ada, dilewat."
  else
    gcloud dataplex zones create "$ZONE_ID" \
      --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" \
      --display-name="$ZONE_NAME" \
      --type=RAW \
      --resource-location-type=SINGLE_REGION \
      --discovery-enabled
  fi

  step "Task 1c: attach asset '$ASSET_NAME' (bucket $BUCKET)"
  # Tanpa flag discovery = inherit dari zone, sesuai instruksi lab.
  if gcloud dataplex assets describe "$ASSET_ID" --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" >/dev/null 2>&1; then
    echo "Asset sudah ada, dilewat."
  else
    gcloud dataplex assets create "$ASSET_ID" \
      --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
      --display-name="$ASSET_NAME" \
      --resource-type=STORAGE_BUCKET \
      --resource-name="projects/$PROJECT/buckets/$BUCKET"
  fi

  step "Task 2: grant $ROLE_READER ke $USER2 (level asset)"
  gcloud dataplex assets add-iam-policy-binding "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --member="user:$USER2" --role="$ROLE_READER"

  step "Verifikasi: IAM policy asset"
  gcloud dataplex assets get-iam-policy "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID"

  cat <<EOF

--------------------------------------------------------------
BERHENTI DI SINI.

Klik Check my progress sampai hijau untuk:
  - Create a lake, zone, and asset in Knowledge Catalog
  - Assign Knowledge Catalog Data Reader role to another user

Fase 'writer' MENGGANTI role User 2 dari Reader jadi Writer.
Kalau dijalankan sekarang, checkpoint Data Reader tidak akan
bisa diverifikasi lagi.

Opsional (Task 3, tanpa checkpoint): logout, login UI sebagai
User 2, coba upload file ke bucket $BUCKET. Harus DITOLAK.
Itu memang inti pelajarannya.

Kalau checkpoint sudah hijau, login lagi sebagai User 1, lalu:
  USER2=$USER2 REGION=$REGION bash gsp1157.sh writer
--------------------------------------------------------------
EOF

# ================================================================== WRITER
else

  step "Task 4: ganti role $USER2 dari Reader jadi Writer"
  # Console 'Edit principal' mengganti role, bukan menumpuk. Tiru persis:
  # cabut reader dulu, baru pasang writer.
  gcloud dataplex assets remove-iam-policy-binding "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --member="user:$USER2" --role="$ROLE_READER" >/dev/null 2>&1 \
    || echo "(binding reader tidak ada, dilewat)"

  gcloud dataplex assets add-iam-policy-binding "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID" \
    --member="user:$USER2" --role="$ROLE_WRITER"

  step "Verifikasi: IAM policy asset (harus dataWriter, bukan dataReader)"
  gcloud dataplex assets get-iam-policy "$ASSET_ID" \
    --project="$PROJECT" --location="$REGION" --lake="$LAKE_ID" --zone="$ZONE_ID"

  # Buang prefix gs:// dan slash kalau ada: format 'value(name)' tidak dijamin polos,
  # sementara --resource-name butuh nama telanjang.
  BUCKET="$(gcloud storage buckets list --project="$PROJECT" --format='value(name)' 2>/dev/null \
            | sed 's|^gs://||; s|/$||' | grep -- '-bucket$' | head -1 || true)"

  cat <<EOF

--------------------------------------------------------------
Klik Check my progress untuk:
  - Assign Knowledge Catalog Data Writer role to another user

Sisanya TIDAK BISA diotomasi dari sini. Task 5 harus dikerjakan
sebagai User 2, sementara Cloud Shell ini login sebagai User 1.

Task 5: logout, login console sebagai User 2, buka
Cloud Storage > Buckets > $BUCKET, Upload > Upload files,
pilih file apa saja. Kali ini harus BERHASIL.
Lalu klik Check my progress terakhir.

Permission butuh beberapa menit untuk menyebar. Kalau upload
masih ditolak, tunggu sebentar lalu coba lagi.
--------------------------------------------------------------
EOF
fi
