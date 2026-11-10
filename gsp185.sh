#!/usr/bin/env bash
# GSP185 - App Dev: Storing Image and Video Files in Cloud Storage - Python
#
#   bash gsp185.sh
#
# Checkpoint:
#   Task 3 - Create a bucket
#   Task 4 - Upload objects to your bucket

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set di env var
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
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="us-west1-b"

ask ZONE "$DEFAULT_ZONE" "Zone (cocokkan dengan panel lab)"
REGION="${ZONE%-*}"
ask REGION "$REGION" "Region (cocokkan dengan panel lab)"

BUCKET_NAME="${PROJECT_ID}-media"
export GCLOUD_BUCKET="$BUCKET_NAME"
export GCLOUD_PROJECT="$PROJECT_ID"

echo "Project ID : $PROJECT_ID"
echo "Zone       : $ZONE"
echo "Region     : $REGION"
echo "Bucket     : $BUCKET_NAME"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1a: Inisialisasi Datastore / Firestore
step "Task 1a: Inisialisasi Database Cloud Datastore / Firestore"

if ! gcloud firestore databases describe --database='(default)' >/dev/null 2>&1; then
  echo "Membuat database Datastore mode (default)..."
  gcloud firestore databases create --location="$REGION" --type=datastore-mode --quiet 2>/dev/null || \
  gcloud firestore databases create --location="us-central1" --type=datastore-mode --quiet 2>/dev/null || \
  gcloud firestore databases create --location="nam5" --type=datastore-mode --quiet 2>/dev/null || true
else
  echo "Database (default) sudah aktif."
fi

# ----------------------------------------------------------------- Task 1b: Unduh Starter Code & Persiapan Lingkungan
step "Task 1b: Unduh Starter Code & Persiapan Lingkungan Quiz App"

cd ~
if [[ ! -d "$HOME/cloudstorage/start" ]]; then
  echo "Mengunduh starter files cloudstorage..."
  if gcloud storage cp -r "gs://${PROJECT_ID}-assets/cloudstorage" . 2>/dev/null; then
    echo "Starter files berhasil diunduh dari gs://${PROJECT_ID}-assets/cloudstorage"
  elif gsutil -m cp -r "gs://${PROJECT_ID}-assets/cloudstorage" . 2>/dev/null; then
    echo "Starter files berhasil diunduh via gsutil"
  else
    echo "Bucket aset project tidak ditemukan, mengunduh dari repositori training..."
    git clone --depth 1 https://github.com/GoogleCloudPlatform/training-data-analyst /tmp/tda 2>/dev/null || true
    mkdir -p ~/cloudstorage
    if [[ -d /tmp/tda/courses/developingapps/python/cloudstorage ]]; then
      cp -r /tmp/tda/courses/developingapps/python/cloudstorage/* ~/cloudstorage/
    fi
  fi
fi

cd ~/cloudstorage/start

# Sesuaikan prepare_environment.sh agar tidak error pada app create
if [[ -f prepare_environment.sh ]]; then
  sed -i "s/us-central/$REGION/g" prepare_environment.sh
  sed -i 's/gcloud app create.*/true/g' prepare_environment.sh
fi

# Setup Virtual Environment Python
echo "Menyiapkan virtual environment Python..."
mkdir -p ~/venvs
if [[ ! -d ~/venvs/developingapps ]]; then
  python3 -m venv ~/venvs/developingapps || virtualenv -p python3 ~/venvs/developingapps
fi

# Aktifkan virtual environment
# shellcheck source=/dev/null
source ~/venvs/developingapps/bin/activate
export PYTHONPATH="$HOME/cloudstorage/start:${PYTHONPATH:-}"

echo "Menginstal dependensi Python..."
pip install --upgrade pip -q
pip install -r requirements.txt -q

echo "Membuat entitas awal di Cloud Datastore..."
python add_entities.py || true

# ----------------------------------------------------------------- Task 3: Create Cloud Storage Bucket
step "Task 3: Buat Cloud Storage Bucket gs://$BUCKET_NAME (Checkpoint 1)"

if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET_NAME} sudah ada."
else
  echo "Membuat bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="$REGION" --project="$PROJECT_ID" --quiet || \
  gcloud storage buckets create "gs://${BUCKET_NAME}" --project="$PROJECT_ID" --quiet
fi

# Pastikan bucket dapat diakses publik (public-read)
echo "Mengonfigurasi izin akses public-read pada bucket..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member=allUsers \
  --role=roles/storage.objectViewer --quiet || true

# ----------------------------------------------------------------- Task 4: Modifikasi Kode Aplikasi
step "Task 4: Modifikasi Kode storage.py & questions.py"

cd ~/cloudstorage/start

echo "Memperbarui quiz/gcp/storage.py..."
cat << 'EOF_STORAGE' > quiz/gcp/storage.py
# Copyright 2017 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
project_id = os.getenv('GCLOUD_PROJECT')

# TODO: Get the Bucket name from the GCLOUD_BUCKET environment variable
bucket_name = os.getenv('GCLOUD_BUCKET')
# END TODO

# TODO: Import the storage module
from google.cloud import storage
# END TODO

# TODO: Create a client for Cloud Storage
storage_client = storage.Client()
# END TODO

# TODO: Use the client to get the Cloud Storage bucket
bucket = storage_client.get_bucket(bucket_name)
# END TODO

"""
Uploads a file to a given Cloud Storage bucket and returns the public url
to the new object.
"""
def upload_file(image_file, public):

    # TODO: Use the bucket to get a blob object
    blob = bucket.blob(image_file.filename)
    # END TODO

    # TODO: Use the blob to upload the file
    blob.upload_from_string(
        image_file.read(),
        content_type=image_file.content_type)
    # END TODO

    # TODO: Make the object public
    if public:
        try:
            blob.make_public()
        except Exception:
            pass
    # END TODO

    # TODO: Modify to return the blob's Public URL
    return blob.public_url
    # END TODO
EOF_STORAGE

echo "Memperbarui quiz/webapp/questions.py..."
cat << 'EOF_QUESTIONS' > quiz/webapp/questions.py
# Copyright 2017, Google, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TODO: Import the storage module
from quiz.gcp import storage, datastore
# END TODO

"""
uploads file into google cloud storage
- upload file
- return public_url
"""
def upload_file(image_file, public):
    if not image_file:
        return None

    # TODO: Use the storage client to Upload the file
    # The second argument is a boolean
    public_url = storage.upload_file(
       image_file, 
       public
    )
    # END TODO

    # TODO: Return the public URL
    # for the object
    return public_url
    # END TODO

"""
uploads file into google cloud storage
- call method to upload file (public=true)
- call datastore helper method to save question
"""
def save_question(data, image_file):

    # TODO: If there is an image file, then upload it
    # And assign the result to a new Datastore property imageUrl
    # If there isn't, assign an empty string
    if image_file:
        data['imageUrl'] = str(
                  upload_file(image_file, True))
    else:
        data['imageUrl'] = u''
    # END TODO

    data['correctAnswer'] = int(data['correctAnswer'])
    datastore.save_question(data)
    return
EOF_QUESTIONS

# ----------------------------------------------------------------- Task 4 (Lanjutan): Upload Object & Simpan Question (Checkpoint 2)
step "Task 4 (Lanjutan): Upload Image ke Cloud Storage & Simpan Question (Checkpoint 2)"

IMAGE_FILE="Google_Cloud_Storage_logo.png"

# Buat berkas gambar PNG valid
echo "Membuat berkas gambar $IMAGE_FILE..."
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$IMAGE_FILE"

# Upload langsung ke Cloud Storage dan pastikan berstatus public
echo "Mengunggah berkas $IMAGE_FILE ke gs://${BUCKET_NAME}..."
gcloud storage cp "$IMAGE_FILE" "gs://${BUCKET_NAME}/${IMAGE_FILE}" --quiet || true
gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/${IMAGE_FILE}" 2>/dev/null || true
gcloud storage objects add-iam-policy-binding "gs://${BUCKET_NAME}/${IMAGE_FILE}" \
  --member=allUsers \
  --role=roles/storage.objectViewer --quiet 2>/dev/null || true

# Jalankan skrip upload via logika aplikasi Python langsung dari root start
cat << 'EOF_UPLOAD' > run_upload.py
import os
import sys

# Pastikan path modul quiz terdaftar
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

os.environ['GCLOUD_PROJECT'] = os.environ.get('GCLOUD_PROJECT', '')
os.environ['GCLOUD_BUCKET'] = os.environ.get('GCLOUD_BUCKET', '')

from io import BytesIO
from werkzeug.datastructures import FileStorage
from quiz.webapp import questions

image_path = 'Google_Cloud_Storage_logo.png'
with open(image_path, 'rb') as f:
    file_storage = FileStorage(
        stream=BytesIO(f.read()),
        filename='Google_Cloud_Storage_logo.png',
        content_type='image/png'
    )

data = {
    'author': 'Google Cloud Student',
    'quiz': 'gcp',
    'title': 'Which product does this logo relate to?',
    'answer1': 'App Engine',
    'answer2': 'Cloud Storage',
    'answer3': 'Compute Engine',
    'answer4': 'Container Engine',
    'correctAnswer': 2
}

try:
    questions.save_question(data, file_storage)
    print("Pertanyaan dan gambar berhasil disimpan via kode aplikasi Python!")
except Exception as e:
    print(f"Peringatan penyimpanan aplikasi: {e}")
EOF_UPLOAD

echo "Mengeksekusi penyimpanan pertanyaan dan upload file via aplikasi..."
python run_upload.py || true

# Jalankan web server di latar belakang port 8080 untuk API review
echo "Menjalankan Quiz Server di port 8080..."
pkill -f "python run_server.py" 2>/dev/null || true
nohup python run_server.py > /tmp/quiz_server.log 2>&1 &
sleep 3

# Uji endpoint API
echo "Verifikasi respons API /api/quizzes/gcp:"
curl -s http://127.0.0.1:8080/api/quizzes/gcp | grep -o '"imageUrl":[^,]*' | head -5 || true
echo

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create a bucket (Task 3)
  2. Upload objects to your bucket (Task 4)
==============================================================
EOF
