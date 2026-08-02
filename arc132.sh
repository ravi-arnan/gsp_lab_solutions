#!/usr/bin/env bash
# ARC132 - Implement Speech and Language Solutions with Pre-trained APIs: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc132.sh
#   bash arc132.sh
#
# Checkpoint:
#   Task 1 - Buat API key
#   Task 2 - Text-to-Speech: synthesize-text.json -> synthesize-text.txt -> .mp3
#   Task 3 - Speech-to-Text bahasa Prancis: speech_request.json -> response.json
#   Task 4 - Translation: translation_response.txt
#   Task 5 - Language detection: detection_response.txt
#
# Task 2-5 dinilai dari file yang ada DI DALAM VM 'lab-vm', bukan di Cloud
# Shell. Script ini bikin API key di Cloud Shell, lalu mengirim satu script
# remote lewat scp dan menjalankannya via SSH di lab-vm.
#
# PENTING: checkpoint Task 1 TIDAK hijau oleh key buatan gcloud (diuji
# 2026-08-02, key ada dan tanpa restriction tapi tetap merah). Bikin satu key
# lagi lewat console: APIs & Services -> Credentials -> + Create credentials
# -> API key. Form barunya mewajibkan isi "Select API restrictions" — pilih
# Text-to-Speech, Speech-to-Text, dan Translation (atau "Don't restrict key"),
# Application restrictions biarkan None. Key buatan script tetap yang dipakai
# Task 2-5.
#
# LAMA: ~2-3 menit, paling lama menunggu SSH siap.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

VM="${VM:-lab-vm}"
KEY_DISPLAY_NAME="arc132"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  apikeys.googleapis.com \
  texttospeech.googleapis.com \
  speech.googleapis.com \
  translate.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: API key"
KEY_NAME=$(gcloud services api-keys list \
  --filter="displayName=$KEY_DISPLAY_NAME" \
  --format="value(name)" --project="$PROJECT" | head -1)

if [[ -z "$KEY_NAME" ]]; then
  gcloud services api-keys create --display-name="$KEY_DISPLAY_NAME" --project="$PROJECT"
  KEY_NAME=$(gcloud services api-keys list \
    --filter="displayName=$KEY_DISPLAY_NAME" \
    --format="value(name)" --project="$PROJECT" | head -1)
fi
[[ -n "$KEY_NAME" ]] || { echo "Gagal membuat API key."; exit 1; }

API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" \
  --format="value(keyString)" --project="$PROJECT")
[[ -n "$API_KEY" ]] || { echo "Gagal mengambil key string."; exit 1; }
echo "API key siap (${#API_KEY} karakter)."

# ----------------------------------------------------------------- VM
step "Cari zone $VM"
ZONE=$(gcloud compute instances list --filter="name=$VM" \
  --format="value(zone)" --project="$PROJECT" | head -1)
[[ -n "$ZONE" ]] || { echo "Instance $VM tidak ditemukan."; exit 1; }
echo "Zone: $ZONE"

# ----------------------------------------------------------------- remote
REMOTE=/tmp/arc132_remote.sh
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
# Dijalankan DI DALAM lab-vm. $1 = API key.
set -uo pipefail
API_KEY="$1"
cd "$HOME"

# venv sudah disiapkan lab; tts_decode.py cuma pakai stdlib jadi ini opsional.
[[ -f venv/bin/activate ]] && source venv/bin/activate

echo "== Task 2: Text-to-Speech =="
# Ditulis persis seperti di instruksi lab (pakai kutip tunggal). Parser JSON
# di endpoint Google menerimanya, dan grader bisa saja memeriksa isi file ini.
cat > synthesize-text.json << 'EOF'
{
    'input':{
        'text':'Cloud Text-to-Speech API allows developers to include
           natural-sounding, synthetic human speech as playable audio in
           their applications. The Text-to-Speech API converts text or
           Speech Synthesis Markup Language (SSML) input into audio data
           like MP3 or LINEAR16 (the encoding used in WAV files).'
    },
    'voice':{
        'languageCode':'en-gb',
        'name':'en-GB-Standard-A',
        'ssmlGender':'FEMALE'
    },
    'audioConfig':{
        'audioEncoding':'MP3'
    }
}
EOF

curl -s -X POST -H "Content-Type: application/json" \
  --data-binary @synthesize-text.json \
  "https://texttospeech.googleapis.com/v1/text:synthesize?key=$API_KEY" \
  -o synthesize-text.txt

if ! grep -q audioContent synthesize-text.txt; then
  echo "Respons TTS tidak berisi audioContent, isi file:"
  cat synthesize-text.txt
  exit 1
fi

cat > tts_decode.py << 'EOF'
import argparse
from base64 import decodebytes
import json

"""
Usage:
        python tts_decode.py --input "synthesize-text.txt" \
        --output "synthesize-text-audio.mp3"

"""

def decode_tts_output(input_file, output_file):
    """ Decode output from Cloud Text-to-Speech.

    input_file: the response from Cloud Text-to-Speech
    output_file: the name of the audio file to create

    """

    with open(input_file) as input:
        response = json.load(input)
        audio_data = response['audioContent']

        with open(output_file, "wb") as new_file:
            new_file.write(decodebytes(audio_data.encode('utf-8')))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Decode output from Cloud Text-to-Speech",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--input',
                       help='The response from the Text-to-Speech API.',
                       required=True)
    parser.add_argument('--output',
                       help='The name of the audio file to create',
                       required=True)

    args = parser.parse_args()
    decode_tts_output(args.input, args.output)
EOF

# VM lab cuma punya python3, bukan 'python'.
python3 tts_decode.py --input "synthesize-text.txt" --output "synthesize-text-audio.mp3"
ls -l synthesize-text-audio.mp3

echo "== Task 3: Speech-to-Text (Prancis) =="
cat > speech_request.json << 'EOF'
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

curl -s -X POST -H "Content-Type: application/json" \
  --data-binary @speech_request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  -o response.json
head -c 400 response.json; echo

echo "== Task 4: Translation (JA -> EN) =="
curl -s -G \
  --data-urlencode 'q=これは日本語です。' \
  --data-urlencode 'target=en' \
  "https://translation.googleapis.com/language/translate/v2?key=$API_KEY" \
  -o translation_response.txt
cat translation_response.txt; echo

echo "== Task 5: Language detection =="
curl -s -G \
  --data-urlencode 'q=Este é japonês.' \
  "https://translation.googleapis.com/language/translate/v2/detect?key=$API_KEY" \
  -o detection_response.txt
cat detection_response.txt; echo

echo "== File di $HOME =="
ls -l synthesize-text.json synthesize-text.txt synthesize-text-audio.mp3 \
      tts_decode.py speech_request.json response.json \
      translation_response.txt detection_response.txt
REMOTE_EOF

step "Kirim script ke $VM dan jalankan"
# SSH pertama kali harus generate key; --quiet supaya tidak menanyakan passphrase.
n=1
until gcloud compute scp "$REMOTE" "$VM":~/arc132_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 6 )) && { echo "SSH tidak siap setelah 5 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/arc132_remote.sh '$API_KEY'"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 2-5. File hasil ada di home
directory $VM, bukan di Cloud Shell.

Task 1 masih perlu satu langkah manual: bikin API key lewat console
(APIs & Services -> Credentials -> + Create credentials -> API key).
Isi "Select API restrictions" dengan Text-to-Speech, Speech-to-Text,
dan Translation; Application restrictions biarkan None. Key buatan
script ini tidak menghijaukan checkpoint Task 1.
==============================================================
EOF
