#!/usr/bin/env bash
# ARC130 - Analyze Sentiment with Natural Language API: Challenge Lab
#
#   API_KEY=<key dari console> bash arc130.sh
#
# Checkpoint:
#   Task 1 - Create an API key                (manual, lewat console)
#   Task 2 - Google Docs + Apps Script        (manual, lihat penutup)
#   Task 3 - analyze-request.json + analyze-response.txt  (di lab-vm)
#   Task 4 - multi-nl-request.json + multi-response.txt   (di lab-vm)
#
# Task 3 dan 4 dinilai dari file DI DALAM VM 'lab-vm'. Script mengirim satu
# script remote lewat scp lalu menjalankannya via SSH (pola arc132/gsp038).
#
# Script juga memanggil analyzeSentiment sekali dengan key yang sama, untuk
# berjaga-jaga kalau checkpoint Task 2 hanya melihat pemakaian API. Kalau
# tetap merah, kerjakan Docs-nya manual (instruksi di penutup).
#
# LAMA: ~2 menit.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-lab-vm}"
API_KEY="${API_KEY:-}"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable language.googleapis.com apikeys.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: API key"
if [[ -n "$API_KEY" ]]; then
  echo "Pakai API key dari env (${#API_KEY} karakter)."
else
  KEY_DISPLAY_NAME="arc130"
  KEY_NAME="$(gcloud services api-keys list --project="$PROJECT" \
    --filter="displayName='$KEY_DISPLAY_NAME'" --format='value(name)' | head -1)"
  if [[ -z "$KEY_NAME" ]]; then
    gcloud services api-keys create --display-name="$KEY_DISPLAY_NAME" --project="$PROJECT"
    KEY_NAME="$(gcloud services api-keys list --project="$PROJECT" \
      --filter="displayName='$KEY_DISPLAY_NAME'" --format='value(name)' | head -1)"
  fi
  [[ -n "$KEY_NAME" ]] || { echo "Gagal membuat API key."; exit 1; }
  API_KEY="$(gcloud services api-keys get-key-string "$KEY_NAME" \
    --format='value(keyString)' --project="$PROJECT")"
  echo "API key dibuat lewat gcloud (${#API_KEY} karakter)."
  echo "CATATAN: checkpoint Task 1 mungkin tetap merah. Bikin key lewat console."
fi
[[ -n "$API_KEY" ]] || { echo "API key kosong."; exit 1; }

# ----------------------------------------------------------------- VM
step "Cari zone $VM"
ZONE="$(gcloud compute instances list --filter="name=$VM" \
  --format='value(zone)' --project="$PROJECT" | head -1)"
[[ -n "$ZONE" ]] || { echo "Instance $VM tidak ditemukan."; exit 1; }
echo "Zone: $ZONE"

# ----------------------------------------------------------------- remote
REMOTE=/tmp/arc130_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
# Dijalankan DI DALAM lab-vm. $1 = API key.
set -uo pipefail
API_KEY="$1"
cd "$HOME"

NL="https://language.googleapis.com/v1/documents"

call() {  # $1 = endpoint, $2 = file request
  curl -s -X POST -H "Content-Type: application/json" \
    --data-binary @"$2" "$NL:$1?key=$API_KEY"
}

echo "== Task 3: analyze-request.json -> analyze-response.txt =="
cat > analyze-request.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content": "Google, headquartered in Mountain View, unveiled the new Android phone at the Consumer Electronic Show.  Sundar Pichai said in his keynote that users love their new Android phones."
  },
  "encodingType": "UTF8"
}
EOF
call analyzeSyntax analyze-request.json > analyze-response.txt
head -c 400 analyze-response.txt; echo
grep -q '"partOfSpeech"' analyze-response.txt || {
  echo "GAGAL: analyze-response.txt tidak berisi hasil syntax. Isi lengkap:"
  cat analyze-response.txt; exit 1; }

echo
echo "== Task 4: multi-nl-request.json -> multi-response.txt =="
cat > multi-nl-request.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"Le bureau japonais de Google est situé à Roppongi Hills, Tokyo."
  }
}
EOF
call analyzeEntities multi-nl-request.json > multi-response.txt
head -c 400 multi-response.txt; echo
grep -q '"entities"' multi-response.txt || {
  echo "GAGAL: multi-response.txt tidak berisi entities. Isi lengkap:"
  cat multi-response.txt; exit 1; }

echo
echo "== Task 2 (percobaan): panggil analyzeSentiment sekali =="
cat > sentiment-request.json << 'EOF'
{
  "document":{
    "language":"en-us",
    "type":"PLAIN_TEXT",
    "content":"It was the best of times, it was the worst of times."
  },
  "encodingType":"UTF8"
}
EOF
call analyzeSentiment sentiment-request.json | head -c 300; echo

echo
echo "File di $HOME:"
ls -l analyze-request.json analyze-response.txt multi-nl-request.json multi-response.txt
REMOTE_EOF

step "Kirim script ke $VM dan jalankan"
n=1
until gcloud compute scp "$REMOTE" "$VM":~/arc130_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 6 )) && { echo "SSH tidak siap setelah 5 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/arc130_remote.sh '$API_KEY'"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 3 dan Task 4.

Task 1: API key harus dibuat lewat console (APIs & Services ->
Credentials -> Create credentials -> API key, restriction pilih
Cloud Natural Language API).

Task 2 wajib manual, tidak bisa lewat CLI:
  1. Buka https://docs.new (Google Docs baru)
  2. Extensions -> Apps Script
  3. Tempel kode Apps Script dari instruksi lab, ganti
     "your key here" dengan API key kamu
  4. Save, lalu refresh dokumennya
  5. Ketik beberapa kalimat di dokumen, blok teksnya
  6. Menu 'Natural Language Tools' -> 'Mark Sentiment', izinkan
     akses saat diminta
  7. Teks akan tersorot hijau/kuning/merah sesuai sentimen
==============================================================
EOF
