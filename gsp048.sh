#!/usr/bin/env bash
# GSP048 - Transkripsi Speech-to-Text dengan Speech-to-Text API
#
#   bash gsp048.sh
#
# Checkpoint:
#   Task 1 (0 pts)  - Manual: buat API key di Console (APIs & Services > Credentials),
#                     restrict ke Cloud Speech-to-Text API
#   Task 2          - Buat request.json (bahasa Inggris)
#   Task 3          - Panggil Speech-to-Text API untuk audio Inggris
#   Task 4          - Panggil Speech-to-Text API untuk audio Prancis
#
# LAMA: ~3 menit.

set -euo pipefail

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask API_KEY "" "API key dari Task 1 (APIs & Services > Credentials)"
[[ -n "$API_KEY" ]] || { echo "API_KEY kosong. Buat dulu di Console (Task 1)."; exit 1; }
export API_KEY

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable Speech-to-Text API"
gcloud services enable speech.googleapis.com --project="$PROJECT"

step "Task 2: Buat request.json (Inggris)"
cat > request.json <<'EOF'
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "en-US"
  },
  "audio": {
      "uri":"gs://cloud-samples-data/speech/brooklyn_bridge.flac"
  }
}
EOF
cat request.json

step "Task 3: Panggil Speech-to-Text API (Inggris)"
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json
cat result.json
echo
grep -q '"transcript"' result.json || { echo "ERROR: tidak ada transcript di result.json"; cat result.json; exit 1; }

step "Task 4: Ganti ke audio Prancis + panggil lagi"
cat > request.json <<'EOF'
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "fr"
  },
  "audio": {
      "uri":"gs://cloud-samples-data/speech/corbeau_renard.flac"
  }
}
EOF
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json
cat result.json
echo
grep -q '"transcript"' result.json || { echo "ERROR: tidak ada transcript di result.json"; cat result.json; exit 1; }

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  - Task 2: Membuat permintaan Speech API"
echo "  - Task 3: Memanggil Speech API untuk bahasa Inggris"
echo "  - Task 4: Memanggil Speech API untuk bahasa Prancis"
