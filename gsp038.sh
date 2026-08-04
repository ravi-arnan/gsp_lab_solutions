#!/usr/bin/env bash
# GSP038 - Entity and Sentiment Analysis with the Natural Language API
#
#   API_KEY=<key dari console> bash gsp038.sh
#
# Checkpoint:
#   Task 1 - Create an API Key            (manual, lewat console)
#   Task 2 - Make an Entity Analysis Request  (request.json di VM)
#   Task 3 - Check the Entity Analysis response (result.json di VM)
#   Task 4-7 - Tanpa checkpoint, tetap dijalankan sebagai bukti
#
# Task 2 dan 3 dinilai dari file DI DALAM VM 'linux-instance', bukan di Cloud
# Shell. Script ini mengirim satu script remote lewat scp lalu menjalankannya
# via SSH, persis pola arc132.
#
# Task 1: bikin key lewat console (APIs & Services -> Credentials -> Create
# credentials -> API key, restriction: Cloud Natural Language API), lalu
# oper ke script lewat env API_KEY. Kalau API_KEY kosong script bikin key
# sendiri pakai gcloud — cukup untuk memanggil API, tapi di lab sejenis
# (arc132) key buatan gcloud TIDAK menghijaukan checkpoint Task 1.
#
# LAMA: ~2 menit, paling lama menunggu SSH siap.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-linux-instance}"
API_KEY="${API_KEY:-}"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  language.googleapis.com \
  apikeys.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: API key"
if [[ -n "$API_KEY" ]]; then
  echo "Pakai API key dari env (${#API_KEY} karakter)."
else
  KEY_DISPLAY_NAME="gsp038"
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
REMOTE=/tmp/gsp038_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
# Dijalankan DI DALAM linux-instance. $1 = API key.
set -uo pipefail
API_KEY="$1"
cd "$HOME"

NL="https://language.googleapis.com/v1/documents"

call() {  # $1 = endpoint, $2 = file request
  curl -s -X POST -H "Content-Type: application/json" \
    --data-binary @"$2" "$NL:$1?key=$API_KEY"
}

echo "== Task 2: request.json (entity analysis) =="
cat > request.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"Joanne Rowling, who writes under the pen names J. K. Rowling and Robert Galbraith, is a British novelist and screenwriter who wrote the Harry Potter fantasy series."
  },
  "encodingType":"UTF8"
}
EOF
cat request.json

echo
echo "== Task 3: panggil analyzeEntities -> result.json =="
call analyzeEntities request.json > result.json
head -c 600 result.json; echo
if ! grep -q '"Joanne Rowling"' result.json; then
  echo "GAGAL: result.json tidak berisi entity yang diharapkan. Isi lengkap:"
  cat result.json
  exit 1
fi

# Task 4-7 tidak punya checkpoint. Pakai file terpisah supaya request.json
# tetap berisi permintaan entity analysis yang dinilai di Task 2.
echo
echo "== Task 4: analyzeSentiment =="
cat > request-extra.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"Harry Potter is the best book. I think everyone should read it."
  },
  "encodingType": "UTF8"
}
EOF
call analyzeSentiment request-extra.json

echo
echo "== Task 5: analyzeEntitySentiment =="
cat > request-extra.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"I liked the sushi but the service was terrible."
  },
  "encodingType": "UTF8"
}
EOF
call analyzeEntitySentiment request-extra.json

echo
echo "== Task 6: analyzeSyntax =="
cat > request-extra.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content": "Joanne Rowling is a British novelist, screenwriter and film producer."
  },
  "encodingType": "UTF8"
}
EOF
call analyzeSyntax request-extra.json | head -c 800; echo

echo
echo "== Task 7: analyzeEntities bahasa Jepang =="
cat > request-extra.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"日本のグーグルのオフィスは、東京の六本木ヒルズにあります"
  }
}
EOF
call analyzeEntities request-extra.json | head -c 800; echo

echo
echo "File di $HOME:"
ls -l request.json result.json
REMOTE_EOF

step "Kirim script ke $VM dan jalankan"
n=1
until gcloud compute scp "$REMOTE" "$VM":~/gsp038_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 6 )) && { echo "SSH tidak siap setelah 5 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/gsp038_remote.sh '$API_KEY'"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 2 dan Task 3. File request.json
dan result.json ada di home directory $VM, bukan di Cloud Shell.

Task 1 (Create an API Key) dihitung dari key yang dibuat lewat
console: APIs & Services -> Credentials -> Create credentials ->
API key, restriction pilih Cloud Natural Language API.

request.json sengaja dibiarkan berisi permintaan entity analysis
(Task 2), Task 4-7 memakai file terpisah request-extra.json.
==============================================================
EOF
