#!/usr/bin/env bash
# ARC114 - Analyze Speech and Language with Google APIs: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc114.sh
#   API_KEY=<key-dari-console> bash arc114.sh
#
# Checkpoint:
#   Task 1 - Create an API key
#   Task 2 - Entity analysis   : nl_request.json     -> nl_response.json
#   Task 3 - Speech analysis   : speech_request.json -> speech_response.json
#   Task 4 - Sentiment analysis: sentiment_analysis.py dilengkapi + dijalankan
#
# Task 2-4 dinilai dari file DI DALAM VM 'lab-vm', bukan di Cloud Shell. Script
# ini menyiapkan API key di Cloud Shell, lalu mengirim satu script remote lewat
# scp dan menjalankannya via SSH di lab-vm.
#
# PENTING: di lab sejenis (arc132, gsp038, arc130) checkpoint "Create an API key"
# TIDAK hijau oleh key buatan gcloud. Bikin key lewat console dulu: APIs &
# Services -> Credentials -> + Create credentials -> API key. Kalau form minta
# "Select API restrictions", pilih Cloud Natural Language API dan Cloud Speech-to-Text
# API (atau "Don't restrict key"); Application restrictions biarkan None. Oper
# keynya lewat env API_KEY. Kalau API_KEY kosong, script bikin key sendiri —
# cukup untuk memanggil API (Task 2-4), tapi Task 1 kemungkinan tetap merah.
#
# LAMA: ~3 menit, paling lama menunggu SSH siap.
#
# STATUS 2026-08-09: maks 75/100. Task 1-3 hijau. Checkpoint Task 4 dianggap
# RUSAK — dua instance berbeda, dua belas hipotesis, semua gugur, padahal
# analisisnya selalu sukses ("Overall Sentiment: score of 0.2 with magnitude of
# 4.6"). Baca docs/arc114.md sebelum membuang waktu mengulang percobaan yang
# sama.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-lab-vm}"
API_KEY="${API_KEY:-}"
KEY_DISPLAY_NAME="arc114"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  apikeys.googleapis.com \
  language.googleapis.com \
  speech.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: API key"
if [[ -n "$API_KEY" ]]; then
  echo "Pakai API key dari env (${#API_KEY} karakter)."
else
  KEY_NAME=$(gcloud services api-keys list \
    --filter="displayName=$KEY_DISPLAY_NAME" \
    --format="value(name)" --project="$PROJECT" | head -1)

  if [[ -z "$KEY_NAME" ]]; then
    # Restriction TIDAK menolong checkpoint Task 1 (diuji 2026-08-21: key CLI
    # ber-restriction tetap merah, key console hijau). Tetap dipasang karena
    # tidak merugikan; key ini gunanya untuk memanggil API di Task 2-4.
    gcloud services api-keys create --display-name="$KEY_DISPLAY_NAME" \
      --api-target=service=language.googleapis.com \
      --api-target=service=speech.googleapis.com \
      --project="$PROJECT"
    KEY_NAME=$(gcloud services api-keys list \
      --filter="displayName=$KEY_DISPLAY_NAME" \
      --format="value(name)" --project="$PROJECT" | head -1)
  fi
  [[ -n "$KEY_NAME" ]] || { echo "Gagal membuat API key."; exit 1; }

  API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" \
    --format="value(keyString)" --project="$PROJECT")
  echo "API key dibuat lewat gcloud (${#API_KEY} karakter)."
  echo "CATATAN: checkpoint Task 1 mungkin tetap merah. Bikin key lewat console."
fi
[[ -n "$API_KEY" ]] || { echo "API key kosong."; exit 1; }

# ----------------------------------------------------------------- VM
step "Cari zone $VM"
ZONE=$(gcloud compute instances list --filter="name=$VM" \
  --format="value(zone)" --project="$PROJECT" | head -1)
[[ -n "$ZONE" ]] || { echo "Instance $VM tidak ditemukan."; exit 1; }
echo "Zone: $ZONE"

# ----------------------------------------------------------------- remote
REMOTE=/tmp/arc114_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
# Dijalankan DI DALAM lab-vm. $1 = API key.
set -uo pipefail
API_KEY="$1"
cd "$HOME"

# Lab menyiapkan virtualenv berisi google-cloud-language. Namanya beda-beda:
# 'env' di arc114, 'venv' di arc132. Pakai yang mana pun yang ada.
for _venv in env venv .venv; do
  if [[ -f "$_venv/bin/activate" ]]; then
    source "$_venv/bin/activate"
    echo "virtualenv aktif: $HOME/$_venv"
    break
  fi
done

echo "== Task 2: entity analysis =="
cat > nl_request.json << 'EOF'
{
  "document":{
    "type":"PLAIN_TEXT",
    "content":"With approximately 8.2 million people residing in Boston, the capital city of Massachusetts is one of the largest in the United States."
  },
  "encodingType":"UTF8"
}
EOF

curl -s -X POST -H "Content-Type: application/json" \
  --data-binary @nl_request.json \
  "https://language.googleapis.com/v1/documents:analyzeEntities?key=$API_KEY" \
  -o nl_response.json
head -c 500 nl_response.json; echo

if ! grep -q '"entities"' nl_response.json; then
  echo "GAGAL: nl_response.json tidak berisi entities. Isi lengkap:"
  cat nl_response.json
  exit 1
fi

echo
echo "== Task 3: speech analysis =="
cat > speech_request.json << 'EOF'
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "en-US"
  },
  "audio": {
      "uri":"gs://cloud-samples-tests/speech/brooklyn.flac"
  }
}
EOF

curl -s -X POST -H "Content-Type: application/json" \
  --data-binary @speech_request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  -o speech_response.json
cat speech_response.json; echo

if ! grep -q '"transcript"' speech_response.json; then
  echo "GAGAL: speech_response.json tidak berisi transcript."
  exit 1
fi

echo
echo "== Task 4: sentiment analysis =="
PY=$(find "$HOME" -maxdepth 3 -name sentiment_analysis.py 2>/dev/null | head -1)
PY="${PY:-$HOME/sentiment_analysis.py}"
echo "File: $PY"

python3 - "$PY" << 'PYEOF'
import os
import re
import sys

path = sys.argv[1]
src = open(path).read() if os.path.exists(path) else ""
# Ikuti nama modul yang sudah dipakai file lab (language_v1 atau language).
mod = "language_v1" if "language_v1" in src else "language"

body = '''def analyze(movie_review_filename):
    """Run a sentiment analysis request on text within a passed filename."""
    client = MOD.LanguageServiceClient()

    with open(movie_review_filename, "r") as review_file:
        # Instantiates a plain text document.
        content = review_file.read()

    document = MOD.Document(content=content, type_=MOD.Document.Type.PLAIN_TEXT)
    annotations = client.analyze_sentiment(request={"document": document})

    # Print the results of for all sentences found in the document.
    print_result(annotations)
'''.replace("MOD", mod)

full = '''"""Demonstrates how to make a simple call to the Natural Language API."""

import argparse

from google.cloud import MOD


def print_result(annotations):
    score = annotations.document_sentiment.score
    magnitude = annotations.document_sentiment.magnitude

    for index, sentence in enumerate(annotations.sentences):
        sentence_sentiment = sentence.sentiment.score
        print(f"Sentence {index} has a sentiment score of {sentence_sentiment}")

    print(f"Overall Sentiment: score of {score} with magnitude of {magnitude}")
    return 0


BODY

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "movie_review_filename",
        help="The filename of the movie review you'd like to analyze.",
    )
    args = parser.parse_args()

    analyze(args.movie_review_filename)
'''.replace("MOD", mod).replace("BODY", body)

# Ganti hanya fungsi analyze() kalau filenya ada, supaya sisa file lab utuh.
m = re.search(r"^def analyze\(movie_review_filename\):.*?(?=^\S|\Z)", src, re.S | re.M)
if m:
    out = src[: m.start()] + body + "\n" + src[m.end() :]
else:
    print("Signature analyze() tidak ketemu, tulis ulang file penuh.")
    out = full

open(path, "w").write(out)
print(f"sentiment_analysis.py siap (modul: {mod}).")
PYEOF

# Library-nya ada di virtualenv lab; pasang kalau memang belum ada.
if ! python3 -c "from google.cloud import language_v1" 2>/dev/null; then
  echo "google-cloud-language belum ada, pasang..."
  python3 -m pip install --quiet google-cloud-language || \
    python3 -m pip install --quiet --user google-cloud-language
  python3 -c "from google.cloud import language_v1" 2>/dev/null || {
    echo "GAGAL: google-cloud-language tetap tidak bisa diimpor."
    echo "Cek virtualenv di \$HOME: $(ls -d "$HOME"/*/bin/activate 2>/dev/null)"
    exit 1
  }
fi

cd "$(dirname "$PY")"
echo "-- unduh sample review --"
gcloud storage cp gs://cloud-samples-tests/natural-language/sentiment-samples.tgz . \
  || gsutil cp gs://cloud-samples-tests/natural-language/sentiment-samples.tgz .
gunzip -f -c sentiment-samples.tgz | tar -xf -

echo "-- jalankan analisis --"
python3 sentiment_analysis.py reviews/bladerunner-pos.txt || {
  echo "GAGAL: sentiment_analysis.py error, Task 4 tidak akan hijau."
  exit 1
}

echo
echo "== File hasil =="
ls -l "$HOME"/nl_request.json "$HOME"/nl_response.json \
      "$HOME"/speech_request.json "$HOME"/speech_response.json "$PY"
REMOTE_EOF

step "Kirim script ke $VM dan jalankan"
# SSH pertama kali harus generate key; --quiet supaya tidak menanyakan passphrase.
n=1
until gcloud compute scp "$REMOTE" "$VM":~/arc114_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 6 )) && { echo "SSH tidak siap setelah 5 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/arc114_remote.sh '$API_KEY'"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk:
  Task 2 - Make an entity analysis request
  Task 3 - Create a speech analysis request
  Task 4 - Analyze sentiment with the Natural Language API

File hasil ada di home directory $VM, bukan di Cloud Shell.

Task 1 (Create an API key) kemungkinan butuh key buatan console:
APIs & Services -> Credentials -> + Create credentials -> API key.
Kalau diminta API restrictions, pilih Cloud Natural Language API dan
Cloud Speech-to-Text API; Application restrictions biarkan None.
Ulangi script dengan API_KEY=<key> kalau mau semua pakai key itu.
==============================================================
EOF
