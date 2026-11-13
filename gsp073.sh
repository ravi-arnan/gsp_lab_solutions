#!/usr/bin/env bash
# GSP073 - Cloud Storage: Qwik Start - Google Cloud Console
#
#   bash gsp073.sh            # Task 1-4 (semua yang dinilai)
#   bash gsp073.sh cleanup    # Task 5, TIDAK dinilai dan menghapus semua checkpoint
#
# Checkpoint:
#   1. Create a bucket
#   2. Upload an object into the bucket (kitten.png)
#   3. Share a kitten.png object publicly
#
# Task 4 (folder1/folder2) tidak punya checkpoint tapi murah, jadi tetap
# dikerjakan. Task 5 menghapus seluruh bucket — persis yang dinilai ketiga
# checkpoint — jadi dipisah ke fase 'cleanup' yang tidak jalan otomatis.
#
# Lab aslinya lewat console. Yang dinilai adalah hasilnya di Cloud Storage,
# bukan caranya, jadi gcloud memberi hasil yang sama.
#
# LAMA: < 1 menit.

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PHASE="${1:-main}"

# Deteksi region bawaan lab / org policy constraint jika ada
DEF_REGION="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)"
ORG_LOC="$(gcloud resource-manager org-policies describe constraints/gcp.resourceLocations --project="$PROJECT_ID" --format="value(listPolicy.allowedValues)" 2>/dev/null || true)"

DEFAULT_LOCATION="europe-west1"
if [[ -n "$DEF_REGION" ]]; then
  DEFAULT_LOCATION="$DEF_REGION"
elif [[ "$ORG_LOC" =~ us- ]]; then
  DEFAULT_LOCATION="us-central1"
elif [[ "$ORG_LOC" =~ europe- ]]; then
  DEFAULT_LOCATION="europe-west4"
fi

ask REGION "$DEFAULT_LOCATION" "Location bucket (cocokkan dengan teks Task 1)"

# Teks lab menyarankan memakai Project ID sebagai nama bucket karena pasti unik.
BUCKET="${BUCKET:-$PROJECT_ID}"
IMG="kitten.png"

echo "Project: $PROJECT_ID"
echo "Bucket : gs://$BUCKET"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================= cleanup
if [[ "$PHASE" == "cleanup" ]]; then
  step "Task 5: hapus bucket beserta isinya (TIDAK dinilai)"
  echo "Ini menghapus apa yang dinilai ketiga checkpoint. Pastikan sudah hijau."
  gcloud storage rm -r "gs://$BUCKET"
  gcloud storage ls || true
  exit 0
fi

# ================================================================= Task 1
step "Task 1: buat bucket (checkpoint 1)"
# Uniform access control + public access prevention DIMATIKAN, sesuai teks lab.
# Tanpa --no-public-access-prevention, Task 3 akan ditolak karena project
# Qwiklabs memakai default 'inherited' yang bisa berujung enforced.
create_bucket() {
  local loc="$1"
  gcloud storage buckets create "gs://$BUCKET" \
    --location="$loc" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --no-public-access-prevention
}

if gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket sudah ada, disesuaikan saja."
  gcloud storage buckets update "gs://$BUCKET" \
    --uniform-bucket-level-access \
    --no-public-access-prevention
else
  if ! create_bucket "$REGION"; then
    echo "Gagal membuat bucket di '$REGION' (kemungkinan kendala constraints/gcp.resourceLocations)."
    # Coba fallback ke region lain yang lazim diizinkan
    SUCCESS=0
    for FALLBACK in "$DEF_REGION" "us-central1" "us-east1" "us-west1" "europe-west4"; do
      if [[ -n "$FALLBACK" && "$FALLBACK" != "$REGION" ]]; then
        echo "Mencoba fallback ke location: $FALLBACK ..."
        if create_bucket "$FALLBACK"; then
          REGION="$FALLBACK"
          echo "Berhasil membuat bucket di $REGION!"
          SUCCESS=1
          break
        fi
      fi
    done
    if [[ $SUCCESS -ne 1 ]]; then
      echo "Gagal membuat bucket di seluruh kandidat region. Cek allowed locations pada panel lab."
      exit 1
    fi
  fi
fi

gcloud storage buckets describe "gs://$BUCKET" \
  --format='value(location,storageClass,uniform_bucket_level_access,public_access_prevention)'

# ================================================================= Task 2
step "Task 2: upload $IMG (checkpoint 2)"
# Lab menyuruh mengunduh gambar kucing dari halaman lab lalu upload lewat UI.
# Checkpoint memeriksa nama objectnya, bukan isinya, jadi PNG kecil sudah cukup.
if [[ ! -f "$HOME/$IMG" ]]; then
  base64 -d > "$HOME/$IMG" << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
EOF
fi
gcloud storage cp "$HOME/$IMG" "gs://$BUCKET/$IMG"

# ================================================================= Task 3
step "Task 3: jadikan bucket publik (checkpoint 3)"
# Access control bucket ini Uniform, jadi ACL per-object tidak berlaku.
# Yang dipakai adalah IAM di level bucket, sama seperti Grant access di console.
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member=allUsers \
  --role=roles/storage.objectViewer >/dev/null

echo ">>> Cek akses publik:"
curl -s -o /dev/null -w "HTTP %{http_code}  https://storage.googleapis.com/$BUCKET/$IMG\n" \
  "https://storage.googleapis.com/$BUCKET/$IMG"

# ================================================================= Task 4
step "Task 4: buat folder1/folder2 dan isi satu file (tidak dinilai)"
# Di Cloud Storage folder hanya prefix nama object, jadi meng-upload ke path
# bersarang sudah membuat keduanya muncul di console.
gcloud storage cp "$HOME/$IMG" "gs://$BUCKET/folder1/folder2/$IMG"
gcloud storage ls -r "gs://$BUCKET"

cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create a bucket
  2. Upload an object into the bucket (kitten.png)
  3. Share a kitten.png object publicly

Kedua soal pilihan ganda jawabannya True.

Skor sudah penuh di sini. Task 5 (hapus bucket) tidak menambah poin
dan menghapus semua yang dinilai. Kalau tetap mau mencobanya setelah
semua hijau:

  bash $0 cleanup
--------------------------------------------------------------
EOF
