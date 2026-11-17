#!/usr/bin/env bash
# GSP186 - App Dev: Adding User Authentication to your Application - Python
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp186.sh
#   bash gsp186.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Configure the case study application
#   Task 3 (50 pts) - Configure Identity Platform Authentication

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

DEFAULT_ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="us-east4-c"

ask ZONE "$DEFAULT_ZONE" "Zone (cocokkan dengan panel lab)"
REGION="${ZONE%-*}"
ask REGION "$REGION" "Region (cocokkan dengan panel lab)"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

echo "Project ID     : $PROJECT_ID ($PROJECT_NUMBER)"
echo "Zone           : $ZONE"
echo "Region         : $REGION"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- API
step "Pastikan API yang dibutuhkan aktif"
gcloud services enable \
  identitytoolkit.googleapis.com \
  apikeys.googleapis.com \
  appengine.googleapis.com \
  firestore.googleapis.com \
  datastore.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 1
step "Task 1: Persiapan Aplikasi Quiz & Cloud Datastore (checkpoint 1)"

# 1. Inisialisasi Database Cloud Datastore / Firestore mode
if ! gcloud firestore databases describe --database='(default)' >/dev/null 2>&1; then
  echo "Membuat database Datastore mode (default)..."
  gcloud firestore databases create --location="$REGION" --type=datastore-mode --quiet 2>/dev/null || \
  gcloud firestore databases create --location="us-central1" --type=datastore-mode --quiet 2>/dev/null || \
  gcloud firestore databases create --location="nam5" --type=datastore-mode --quiet 2>/dev/null || true
else
  echo "Database (default) sudah aktif."
fi
gcloud app create --region="$REGION" --quiet 2>/dev/null || true

# 2. Buat bucket gs://$PROJECT_ID-media jika belum ada
BUCKET_NAME="${PROJECT_ID}-media"
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Membuat bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="$REGION" --project="$PROJECT_ID" 2>/dev/null || \
  gcloud storage buckets create "gs://${BUCKET_NAME}" --project="$PROJECT_ID" 2>/dev/null || true
fi

# 3. Unduh starter files
cd ~
if [[ ! -d "$HOME/firebase/start" ]]; then
  echo "Mengunduh starter repository files..."
  if gcloud storage cp -r "gs://${PROJECT_ID}-assets/firebase" . 2>/dev/null; then
    echo "Starter files berhasil diunduh dari Cloud Storage project."
  elif gsutil -m cp -r "gs://${PROJECT_ID}-assets/firebase" . 2>/dev/null; then
    echo "Starter files berhasil diunduh via gsutil."
  else
    echo "Mengunduh starter files dari repositori training..."
    git clone --depth 1 https://github.com/GoogleCloudPlatform/training-data-analyst /tmp/tda 2>/dev/null || true
    mkdir -p ~/firebase
    if [[ -d /tmp/tda/courses/developingapps/v1.3/python/firebase ]]; then
      cp -r /tmp/tda/courses/developingapps/v1.3/python/firebase/* ~/firebase/
    elif [[ -d /tmp/tda/courses/developingapps/python/firebase ]]; then
      cp -r /tmp/tda/courses/developingapps/python/firebase/* ~/firebase/
    fi
  fi
fi

cd ~/firebase/start

# 4. Setup virtual environment Python
echo "Menyiapkan virtual environment Python..."
mkdir -p ~/venvs
if [[ ! -d ~/venvs/developingapps ]]; then
  python3 -m venv ~/venvs/developingapps 2>/dev/null || virtualenv -p python3 ~/venvs/developingapps 2>/dev/null || true
fi

if [[ -f ~/venvs/developingapps/bin/activate ]]; then
  # shellcheck source=/dev/null
  source ~/venvs/developingapps/bin/activate
  pip install --upgrade pip 2>/dev/null || true
  pip install -r requirements.txt 2>/dev/null || pip install google-cloud-datastore flask 2>/dev/null || true
fi

# 5. Export environment variables & Isi entities Datastore
export GCLOUD_PROJECT="$PROJECT_ID"
export GCLOUD_BUCKET="$BUCKET_NAME"

echo "Membuat entitas pertanyaan di Cloud Datastore..."
python add_entities.py 2>/dev/null || python3 add_entities.py 2>/dev/null || true

# ----------------------------------------------------------------- Task 3
step "Task 3: Konfigurasi Identity Platform Authentication (checkpoint 2)"

TOKEN="$(gcloud auth print-access-token)"

echo "Menginisialisasi Identity Platform..."
INIT_RESP=$(curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v2/projects/${PROJECT_ID}/identityPlatform:initializeAuth" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{}' 2>&1 || true)
echo "  Respon initializeAuth: $INIT_RESP"

echo "Mengaktifkan Email / Password Provider..."
PROVIDER_RESP=$(curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=signIn.email" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "signIn": {
      "email": {
        "enabled": true,
        "passwordRequired": true
      }
    }
  }' 2>&1 || true)
echo "  Respon email provider: $(echo "$PROVIDER_RESP" | head -n 5)"

echo "Mendaftarkan Authorized Domains (localhost, cloudshell.dev, firebaseapp.com)..."
curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=authorizedDomains" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "authorizedDomains": [
      "localhost",
      "cloudshell.dev",
      "'"${PROJECT_ID}"'.firebaseapp.com",
      "'"${PROJECT_ID}"'.web.app"
    ]
  }' >/dev/null 2>&1 || true

# Mengambil atau membuat API Key Browser
echo "Mengambil Browser Web API Key..."
API_KEY=""
KEY_NAME=$(curl -s -X GET \
  "https://apikeys.googleapis.com/v2/projects/${PROJECT_NUMBER}/locations/global/keys" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" 2>/dev/null | jq -r '.keys[0].name // empty' 2>/dev/null || true)

if [[ -n "$KEY_NAME" ]]; then
  API_KEY=$(curl -s -X GET \
    "https://apikeys.googleapis.com/v2/${KEY_NAME}/keyString" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" 2>/dev/null | jq -r '.keyString // empty' 2>/dev/null || true)
fi

if [[ -z "$API_KEY" ]]; then
  API_KEY_NAME=$(gcloud services api-keys list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | head -n 1 || true)
  if [[ -n "$API_KEY_NAME" ]]; then
    API_KEY=$(gcloud services api-keys get-key-string "$API_KEY_NAME" --project="$PROJECT_ID" --format="value(keyString)" 2>/dev/null || true)
  fi
fi

echo "  API Key: ${API_KEY:-tidak ditemukan otomatis}"

# Mendaftarkan user via API Key jika ada
if [[ -n "$API_KEY" ]]; then
  echo "Mendaftarkan user1@example.com via Identity Toolkit API..."
  SIGNUP_RESP=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "email": "user1@example.com",
      "password": "abc123!",
      "returnSecureToken": true
    }' 2>&1 || true)
  echo "  Respon signUp user1: $(echo "$SIGNUP_RESP" | jq -r '.email // .error.message // empty' 2>/dev/null || echo "$SIGNUP_RESP")"
fi

# Mendaftarkan user via Python firebase-admin (metode andal menggunakan ADC)
echo "Mendaftarkan user user1@example.com via Python firebase-admin..."
python3 -c "
import subprocess, sys

try:
    import firebase_admin
    from firebase_admin import auth
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'firebase-admin', '--quiet'])
    import firebase_admin
    from firebase_admin import auth

try:
    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={'projectId': '${PROJECT_ID}'})
    try:
        user = auth.create_user(email='user1@example.com', password='abc123!')
        print('  User user1@example.com berhasil dibuat UID:', user.uid)
    except Exception as e:
        if 'EMAIL_EXISTS' in str(e):
            print('  User user1@example.com sudah ada.')
        else:
            print('  Info pembuatan user1:', e)

    try:
        user2 = auth.create_user(email='user2@example.com', password='abcd1234$')
        print('  User user2@example.com berhasil dibuat UID:', user2.uid)
    except Exception as e:
        if 'EMAIL_EXISTS' in str(e):
            print('  User user2@example.com sudah ada.')
        else:
            print('  Info pembuatan user2:', e)
except Exception as err:
    print('  Firebase admin error:', err)
" || true

# ----------------------------------------------------------------- Task 4 (Integrasi Client)
step "Task 4: Integrasi Client-side index.html dengan Identity Platform"

CLIENT_INDEX="$HOME/firebase/start/quiz/webapp/static/client/index.html"
if [[ -f "$CLIENT_INDEX" && -n "$API_KEY" ]]; then
  python3 -c "
with open('$CLIENT_INDEX', 'r') as f:
    content = f.read()

if 'firebase.initializeApp' not in content:
    idx = content.find('<script')
    if idx != -1:
        snippet = '''    <script src=\"https://www.gstatic.com/firebasejs/7.14.0/firebase-app.js\"></script>\n    <script src=\"https://www.gstatic.com/firebasejs/7.14.0/firebase-auth.js\"></script>\n    <script>\n      var uiConfig = {{\n        apiKey: \"$API_KEY\",\n        authDomain: \"$PROJECT_ID.firebaseapp.com\"\n      }};\n      firebase.initializeApp(uiConfig);\n    </script>\n\n'''
        content = content[:idx] + snippet + content[idx:]
        with open('$CLIENT_INDEX', 'w') as f:
            f.write(content)
        print('Markup Identity Platform berhasil disuntikkan ke index.html')
" || true
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk kedua checkpoint:

  [Task 1] Configure the case study application
  [Task 3] Configure Identity Platform Authentication

Untuk menjalankan web server Quiz secara lokal di Cloud Shell:
  cd ~/firebase/start
  source ~/venvs/developingapps/bin/activate
  python run_server.py
==============================================================
EOF
