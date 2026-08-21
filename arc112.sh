#!/usr/bin/env bash
# ARC112 - Deploy and Manage Applications on Google App Engine: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc112.sh
#   bash arc112.sh            # Task 1-2 -> checkpoint 1 dan 2
#   # klik Check my progress 1 dan 2 sampai hijau
#   bash arc112.sh update     # Task 3  -> checkpoint 3
#
# Checkpoint:
#   Task 1 - Download the Hello World app     (repo ter-clone di $HOME VM)
#   Task 2 - Deploy the application           (App Engine standard, us-east4)
#   Task 3 - Deploy updates to your application ("Welcome to this world!")
#
# Semua dikerjakan DI VM lab-setup, bukan di Cloud Shell — teks lab menyuruh
# begitu dan grader memeriksa file di sana.
#
# Kenapa dua fase: checkpoint 2 dinilai saat aplikasi masih memuat pesan
# bawaan "Hello World!". Kalau langsung ditimpa pesan baru, checkpoint itu
# berisiko tidak pernah terlihat hijau.
#
# LAMA: fase 1 sekitar 4-6 menit (clone repo + deploy pertama), fase 2 sekitar 2 menit.

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

PHASE="${1:-main}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "us-east4" "Region App Engine (cocokkan dengan teks Task 2)"
VM="${VM:-lab-setup}"
APP_DIR="python-docs-samples/appengine/standard_python3/hello_world"

echo "Project: $PROJECT"
echo "Region : $REGION"
echo "VM     : $VM"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

ZONE=$(gcloud compute instances list --project="$PROJECT" \
  --filter="name=$VM" --format='value(zone)' | head -1)
[[ -n "$ZONE" ]] || { echo "VM $VM tidak ditemukan. Cek nama di teks lab."; exit 1; }
echo "$VM ada di zone $ZONE"

on_vm() {
  gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet --command="$1"
}

# ================================================================= fase update
if [[ "$PHASE" == "update" ]]; then
  step "Task 3: ubah pesan jadi 'Welcome to this world!' lalu deploy ulang (checkpoint 3)"
  on_vm "
set -e
cd \$HOME/$APP_DIR
sed -i 's/Hello World!/Welcome to this world!/' main.py
grep -n 'Welcome to this world' main.py
gcloud app deploy --quiet
echo '--- isi yang disajikan sekarang ---'
curl -s \$(gcloud app browse --no-launch-browser 2>&1 | grep -o 'https://[^ ]*') | head -5
"
  cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk:
  3. Deploy updates to your application
--------------------------------------------------------------
EOF
  exit 0
fi

# ================================================================= Task 1
step "Task 1: clone Hello World app di \$HOME VM (checkpoint 1)"
# Sengaja pakai Python: repo-nya paling ringan disiapkan dan tidak perlu
# menambal versi runtime seperti jalur PHP.
on_vm "
set -e
cd \$HOME
if [ -d python-docs-samples ]; then
  echo 'Repo sudah ada, clone dilewat.'
else
  git clone --depth 1 https://github.com/GoogleCloudPlatform/python-docs-samples.git
fi
ls \$HOME/$APP_DIR
"

# ================================================================= Task 2
step "Task 2: buat app App Engine dan deploy (checkpoint 2)"
if gcloud app describe --project="$PROJECT" >/dev/null 2>&1; then
  echo "App Engine app sudah ada, dilewat."
else
  gcloud app create --region="$REGION" --project="$PROJECT"
fi

on_vm "
set -e
cd \$HOME/$APP_DIR
# Batasi instance sesuai catatan lab supaya tidak menabrak kuota project.
if ! grep -q automatic_scaling app.yaml; then
  cat >> app.yaml << 'YAML'

automatic_scaling:
  max_instances: 1
YAML
fi
cat app.yaml
gcloud app deploy --quiet
gcloud app browse --no-launch-browser
"

cat <<EOF

--------------------------------------------------------------
Fase 1 selesai. Klik Check my progress untuk:
  1. Download the Hello World app
  2. Deploy the application

Buka URL yang dicetak di atas — harusnya masih "Hello World!".

Setelah keduanya HIJAU, jalankan fase kedua (ganti pesan lalu deploy ulang):

  bash $0 update
--------------------------------------------------------------
EOF
