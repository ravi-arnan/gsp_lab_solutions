#!/usr/bin/env bash
# ARC114 - Analyze Speech and Language with Google APIs: Challenge Lab
#
#   bash arc114.sh
#
# Checkpoint:
#   Task 1 (25 pts) - Create an API key
#   Task 2 (25 pts) - Entity analysis: nl_request.json -> nl_response.json
#   Task 3 (25 pts) - Speech analysis: speech_request.json -> speech_response.json
#   Task 4 (25 pts) - Sentiment analysis: sentiment_analysis.py + reviews/bladerunner-pos.txt
#
# Semua file dinilai ada DI DALAM VM 'lab-vm', bukan di Cloud Shell.
# Script ini membuat API key di Cloud Shell, lalu mengirim script remote
# via scp dan menjalankannya via SSH di lab-vm.
#
# Penting: API key buatan gcloud TIDAK menghijaukan checkpoint Task 1.
# Bikin key lewat console dulu (APIs & Services -> Credentials -> + Create
# credentials -> API key), lalu: API_KEY=<key> bash arc114.sh
#
# LAMA: ~3 menit.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set."; exit 1; }

VM="${VM:-lab-vm}"
API_KEY="${API_KEY:-}"
KEY_DISPLAY_NAME="arc114"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ── Enable APIs ──
step "Enable APIs"
gcloud services enable \
  apikeys.googleapis.com \
  language.googleapis.com \
  speech.googleapis.com \
  --project="$PROJECT" -q 2>/dev/null || true

# ── Task 1: API key ──
step "Task 1: API key"
if [[ -n "$API_KEY" ]]; then
  echo "Pakai API key dari env (${#API_KEY} karakter)."
else
  KEY_NAME=$(gcloud services api-keys list \
    --filter="displayName=$KEY_DISPLAY_NAME" \
    --format="value(name)" --project="$PROJECT" --limit=1)

  if [[ -z "$KEY_NAME" ]]; then
    gcloud services api-keys create --display-name="$KEY_DISPLAY_NAME" \
      --api-target=service=language.googleapis.com \
      --api-target=service=speech.googleapis.com \
      --project="$PROJECT" --quiet
    KEY_NAME=$(gcloud services api-keys list \
      --filter="displayName=$KEY_DISPLAY_NAME" \
      --format="value(name)" --project="$PROJECT" --limit=1)
  fi
  [[ -n "$KEY_NAME" ]] || { echo "Gagal membuat API key."; exit 1; }

  API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" \
    --format="value(keyString)" --project="$PROJECT")
  echo "API key dibuat lewat gcloud (${#API_KEY} karakter)."
  echo "CATATAN: checkpoint Task 1 mungkin tetap merah. Bikin key lewat console."
fi
[[ -n "$API_KEY" ]] || { echo "API key kosong."; exit 1; }

# ── Cari VM zone ──
step "Cari zone $VM"
ZONE=$(gcloud compute instances list --filter="name=$VM" \
  --format="value(zone)" --project="$PROJECT" --limit=1)
[[ -n "$ZONE" ]] || { echo "Instance $VM tidak ditemukan."; exit 1; }
echo "Zone: $ZONE"

# ── Script remote (dijalankan di dalam lab-vm) ──
step "Siapkan script remote"
REMOTE=/tmp/arc114_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
set -uo pipefail
API_KEY="$1"
cd "$HOME"

echo ">> Installing dependencies..."
sudo apt-get update -y -q
sudo apt-get install -y -q python3-pip
# PEP 668: butuh --break-system-packages untuk install system-wide
sudo python3 get-pip.py --break-system-packages -q 2>/dev/null || true
sudo python3 -m pip install --break-system-packages -q \
  google-cloud-language 2>/dev/null || \
  python3 -m pip install --user -q google-cloud-language 2>/dev/null || true

echo
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

if ! grep -q '"entities"' nl_response.json; then
  echo "GAGAL: nl_response.json tidak berisi entities."
  cat nl_response.json
  exit 1
fi
echo "nl_response.json OK ($(wc -c < nl_response.json) bytes)"

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

if ! grep -q '"transcript"' speech_response.json; then
  echo "GAGAL: speech_response.json tidak berisi transcript."
  cat speech_response.json
  exit 1
fi
echo "speech_response.json OK ($(wc -c < speech_response.json) bytes)"

echo
echo "== Task 4: sentiment analysis =="

# Tulis ulang sentiment_analysis.py (full replacement, lebih robust dari patching)
cat > sentiment_analysis.py << 'PYEOF'
"""Demonstrates how to make a simple call to the Natural Language API."""

import argparse

from google.cloud import language_v1


def print_result(annotations):
    score = annotations.document_sentiment.score
    magnitude = annotations.document_sentiment.magnitude

    for index, sentence in enumerate(annotations.sentences):
        sentence_sentiment = sentence.sentiment.score
        print(f"Sentence {index} has a sentiment score of {sentence_sentiment}")

    print(f"Overall Sentiment: score of {score} with magnitude of {magnitude}")
    return 0


def analyze(movie_review_filename):
    """Run a sentiment analysis request on text within a passed filename."""
    client = language_v1.LanguageServiceClient()

    with open(movie_review_filename, "r") as review_file:
        content = review_file.read()

    document = language_v1.Document(
        content=content, type_=language_v1.Document.Type.PLAIN_TEXT
    )
    annotations = client.analyze_sentiment(request={"document": document})

    print_result(annotations)


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
PYEOF

echo "unduh sample review..."
gcloud storage cp gs://cloud-samples-tests/natural-language/sentiment-samples.tgz . \
  || gsutil cp gs://cloud-samples-tests/natural-language/sentiment-samples.tgz .
gunzip -f sentiment-samples.tgz
tar -xf sentiment-samples.tar

echo "jalankan analisis pada bladerunner-pos.txt..."
python3 sentiment_analysis.py reviews/bladerunner-pos.txt

echo
echo "== File hasil =="
ls -l nl_request.json nl_response.json \
      speech_request.json speech_response.json sentiment_analysis.py
REMOTE_EOF

# ── Kirim & jalankan di VM ──
step "Kirim script ke $VM dan jalankan"
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
  Task 1 - Create an API key
  Task 2 - Make an entity analysis request
  Task 3 - Create a speech analysis request
  Task 4 - Analyze sentiment with the Natural Language API

File hasil ada di home directory $VM (bukan Cloud Shell).

Task 1: kalau belum hijau, bikin key lewat console:
  APIs & Services -> Credentials -> + Create credentials -> API key
  Application restrictions: None
  API restrictions: Cloud Natural Language API + Cloud Speech-to-Text API
  Lalu: API_KEY=<key> bash arc114.sh
==============================================================
EOF
