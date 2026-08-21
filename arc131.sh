#!/usr/bin/env bash
# ARC131 - Using the Google Cloud Speech API: Challenge Lab
#
#   bash arc131.sh
#
# Checkpoint:
#   Task 1 - Create an API key
#   Task 2 - API request transcription bahasa Inggris  (speech_request.json + response.json)
#   Task 3 - API request transcription bahasa Spanyol  (request_speech_sp.json + response_sp.json)
#
# Ketiga file JSON harus ada DI VM lab-vm, bukan di Cloud Shell — itu yang
# diperiksa grader. Script ini membuat API key dari Cloud Shell lalu mengerjakan
# sisanya di lab-vm lewat gcloud compute ssh.
#
# LAMA: 1-2 menit (paling lama menunggu SSH pertama siap).

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-lab-vm}"
KEY_DISPLAY_NAME="arc131-key"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: buat API key (checkpoint 1)"
gcloud services enable apikeys.googleapis.com speech.googleapis.com --project="$PROJECT"

# 'api-keys create' mengembalikan objek operation, bukan key-nya, jadi
# --format='value(name)' di situ memberi nama operation dan get-key-string
# akan balas 404. Nama key selalu diambil lewat list.
find_key() {
  gcloud services api-keys list \
    --project="$PROJECT" \
    --filter="displayName=$KEY_DISPLAY_NAME" \
    --format='value(name)' 2>/dev/null | head -1
}

KEY_NAME=$(find_key)
if [[ -n "$KEY_NAME" ]]; then
  echo "API key '$KEY_DISPLAY_NAME' sudah ada, dipakai ulang."
else
  gcloud services api-keys create \
    --display-name="$KEY_DISPLAY_NAME" \
    --project="$PROJECT" >/dev/null
  KEY_NAME=$(find_key)
fi
[[ -n "$KEY_NAME" ]] || { echo "API key tidak ditemukan setelah dibuat."; exit 1; }

API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format='value(keyString)')
[[ -n "$API_KEY" ]] || { echo "Gagal mengambil key string."; exit 1; }
echo "API key siap (simpan kalau perlu): $API_KEY"

# ----------------------------------------------------------------- VM
step "Cari VM $VM"
ZONE=$(gcloud compute instances list --project="$PROJECT" \
  --filter="name=$VM" --format='value(zone)' | head -1)
[[ -n "$ZONE" ]] || { echo "VM $VM tidak ditemukan. Cek nama di teks lab."; exit 1; }
echo "$VM ada di zone $ZONE"

# ----------------------------------------------------------------- Task 2-3
step "Task 2-3: buat request dan panggil Speech API dari dalam $VM (checkpoint 2-3)"

# Semua dikerjakan di satu sesi SSH. Encoding dan sampleRateHertz sengaja tidak
# diisi: untuk file WAV dan FLAC di Cloud Storage, Speech API membaca headernya
# sendiri, dan menebak angka yang salah justru membuat request ditolak.
#
# question_en.wav ternyata STEREO. Speech API menolak audio multi-channel
# ("Must use single channel (mono) audio, but WAV header indicates 2 channels")
# kecuali jumlah channelnya disebut eksplisit lewat audioChannelCount. File
# Spanyolnya mono, jadi tidak butuh field itu.
REMOTE=$(cat <<REMOTE_EOF
set -e

cat > speech_request.json << 'JSON'
{
  "config": {
    "languageCode": "en-US",
    "audioChannelCount": 2
  },
  "audio": {
    "uri": "gs://spls/arc131/question_en.wav"
  }
}
JSON

cat > request_speech_sp.json << 'JSON'
{
  "config": {
    "languageCode": "es-ES"
  },
  "audio": {
    "uri": "gs://spls/arc131/multi_es.flac"
  }
}
JSON

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @speech_request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" > response.json

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request_speech_sp.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" > response_sp.json

echo "--- response.json (Inggris) ---"
cat response.json
echo
echo "--- response_sp.json (Spanyol) ---"
cat response_sp.json
echo
ls -l speech_request.json request_speech_sp.json response.json response_sp.json
REMOTE_EOF
)

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="$REMOTE"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk ketiga task:
  1. Create an API key
  2. Create API request for transcription in English language
  3. Create API request for transcription in Spanish language

Kalau response.json berisi blok "error", transcript tidak terbentuk dan
checkpoint tidak akan hijau. Penyebab tersering: API key baru dibuat dan
belum aktif. Tunggu semenit lalu jalankan ulang script ini — key yang ada
akan dipakai ulang, tidak dibuat dua kali.
==============================================================
EOF
