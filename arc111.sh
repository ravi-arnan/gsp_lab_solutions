#!/usr/bin/env bash
# ARC111 - Implement Cloud Storage and Data Protection Solutions: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc111.sh
#   B1=<Bucket1_name> B2=<Bucket2_name> B3=<Bucket3_name> bash arc111.sh
#
# Checkpoint (form-3):
#   Task 1 - Buat bucket Bucket1 dengan storage class NEARLINE
#   Task 2 - Ubah isi sample.txt di dalam Bucket2
#   Task 3 - Ubah storage class Bucket3 dari Standard ke ARCHIVE
#
# Nama bucket diacak per instance (ada suffix random seperti 'w9kj'), jadi
# TIDAK bisa diturunkan dari PROJECT_ID. Ambil ketiganya dari panel lab.
# Task juga diacak: variabel yang tidak diisi akan dilewati.
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

ask REGION "europe-west1" "Region (cocokkan dengan panel lab)"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask B1 "" "Nama bucket 1 (cocokkan dengan teks task)"
ask B2 "" "Nama bucket 2 (cocokkan dengan teks task)"
ask B3 "" "Nama bucket 3 (cocokkan dengan teks task)"

if [[ -z "$B1$B2$B3" ]]; then
  cat <<EOF
Tidak ada nama bucket yang diisi. Ambil dari panel lab, lalu:

  B1=<Bucket1_name> B2=<Bucket2_name> B3=<Bucket3_name> bash $0

Isi hanya yang muncul di instance-mu; sisanya boleh dikosongkan.
EOF
  exit 1
fi

echo "Project: $PROJECT"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
if [[ -n "$B1" ]]; then
  step "Task 1: Buat gs://$B1 (NEARLINE)"
  if gcloud storage buckets describe "gs://$B1" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Bucket sudah ada, pastikan class-nya NEARLINE."
    gcloud storage buckets update "gs://$B1" --default-storage-class=NEARLINE --project="$PROJECT"
  else
    gcloud storage buckets create "gs://$B1" \
      --location="$REGION" \
      --default-storage-class=NEARLINE \
      --project="$PROJECT"
  fi
  gcloud storage buckets describe "gs://$B1" --project="$PROJECT" --format='value(storageClass)'
fi

# ----------------------------------------------------------------- Task 2
if [[ -n "$B2" ]]; then
  step "Task 2: Ubah isi gs://$B2/sample.txt"
  LINE="This is an example of editing the file content for cloud storage object"
  TMP=$(mktemp)

  # Soal bilang "Add the below content", bukan "replace". Kalau file lama sudah
  # ada isinya, baris ini ditambahkan di bawahnya supaya isi asli tidak hilang.
  if gcloud storage cp "gs://$B2/sample.txt" "$TMP" --project="$PROJECT" 2>/dev/null; then
    echo "File lama ($(wc -c < "$TMP") byte) diunduh."
  else
    echo "sample.txt belum ada, dibuat baru."
    : > "$TMP"
  fi

  if grep -qF "$LINE" "$TMP"; then
    echo "Baris sudah ada di file, tidak ditambahkan dua kali."
  elif [[ -s "$TMP" ]]; then
    printf '\n%s\n' "$LINE" >> "$TMP"
  else
    printf '%s\n' "$LINE" > "$TMP"
  fi

  # Nama file harus tetap sample.txt.
  gcloud storage cp "$TMP" "gs://$B2/sample.txt" --project="$PROJECT"
  rm -f "$TMP"
  echo "--- isi sekarang ---"
  gcloud storage cat "gs://$B2/sample.txt" --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 3
if [[ -n "$B3" ]]; then
  step "Task 3: gs://$B3 -> ARCHIVE"
  # Yang dinilai adalah default storage class di level bucket; object lama
  # tetap di class lamanya dan itu tidak masalah untuk checkpoint ini.
  gcloud storage buckets update "gs://$B3" --default-storage-class=ARCHIVE --project="$PROJECT"
  gcloud storage buckets describe "gs://$B3" --project="$PROJECT" --format='value(storageClass)'
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk tiap task yang dikerjakan.
==============================================================
EOF
