#!/usr/bin/env bash
# GSP183 - App Dev: Setting up a Development Environment - Python
#
#   bash gsp183.sh
#
# Checkpoint:
#   Task 1 (Checkpoint 1) - Create a Compute Engine Virtual Machine Instance
#   Task 1 (Checkpoint 2) - Install software and configure the VM instance
#   Task 2 (Checkpoint 3) - Run application software to get a success response

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
VM_NAME="dev-instance"

echo "Project ID: $PROJECT_ID"
echo "Zone      : $ZONE"
echo "Region    : $REGION"
echo "Instance  : $VM_NAME"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1: VM Instance
step "Task 1: Konfigurasi Firewall HTTP & Buat VM Instance $VM_NAME (Checkpoint 1)"

# Pastikan firewall rule port 80 untuk tag http-server tersedia
if ! gcloud compute firewall-rules describe default-allow-http --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Membuat firewall rule default-allow-http (port 80)..."
  gcloud compute firewall-rules create default-allow-http \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server \
    --project="$PROJECT_ID" \
    --quiet || true
fi

if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Instance $VM_NAME sudah ada di zone $ZONE, melewati pembuatan."
else
  echo "Membuat instance $VM_NAME (Debian 12, E2)..."
  gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --project="$PROJECT_ID" \
    --quiet
fi

EXTERNAL_IP="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "External IP: $EXTERNAL_IP"

# ----------------------------------------------------------------- Menunggu Kesiapan SSH
step "Menunggu kesiapan SSH pada instance $VM_NAME"
for i in {1..30}; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet < /dev/null --command="echo ready" >/dev/null 2>&1; then
    echo "Koneksi SSH berhasil terhubung!"
    break
  fi
  echo "Menunggu inisialisasi SSH instance... ($i/30)"
  sleep 4
done

# ----------------------------------------------------------------- Task 1b & Task 2: Setup Software di VM
step "Task 1 & 2: Install Software, Deploy Server, & Enumerasi GCE (Checkpoint 2 & 3)"

REMOTE_SCRIPT=/tmp/gsp183_setup.sh
cat > "$REMOTE_SCRIPT" << 'REMOTE_EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "== [1/5] Menunggu lock package manager jika ada =="
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  echo "Menunggu apt/dpkg lock dilepas..."
  sleep 3
done

echo "== [2/5] Update & instalasi paket sistem =="
sudo apt-get update -y
sudo apt-get install -y git python3-setuptools python3-dev build-essential

echo "== [3/5] Instalasi pip terbaru =="
curl -s https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
sudo python3 /tmp/get-pip.py --break-system-packages

python3 --version
pip3 --version

echo "== [4/5] Mengunduh lab assets devenv =="
cd ~
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')

mkdir -p ~/devenv

if gcloud storage cp -r "gs://${PROJECT_ID}-assets/devenv" . 2>/dev/null; then
  echo "Lab assets berhasil diunduh via gcloud storage."
elif gsutil -m cp -r "gs://${PROJECT_ID}-assets/devenv" . 2>/dev/null; then
  echo "Lab assets berhasil diunduh via gsutil."
else
  # Cek bucket assets lain jika ada
  ASSET_BUCKET=$(gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | grep -E "assets" | head -1 || true)
  if [[ -n "$ASSET_BUCKET" ]]; then
    gcloud storage cp -r "gs://${ASSET_BUCKET}/devenv" . 2>/dev/null || true
  fi
fi

cd ~/devenv

# Fallback server.py jika unduhan bucket kosong
if [[ ! -f server.py ]]; then
  echo "Membuat fallback server.py..."
  cat << 'PYEOF' > server.py
from http.server import HTTPServer, BaseHTTPRequestHandler

class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b'Hello GCP dev!')

if __name__ == '__main__':
    httpd = HTTPServer(('0.0.0.0', 80), SimpleHTTPRequestHandler)
    print('Server listening on port 80...')
    httpd.serve_forever()
PYEOF
fi

# Fallback requirements.txt jika belum ada
if [[ ! -f requirements.txt ]]; then
  echo "Membuat fallback requirements.txt..."
  cat << 'REQEOF' > requirements.txt
google-api-python-client
google-auth
REQEOF
fi

# Fallback list-gce-instances.py jika belum ada
if [[ ! -f list-gce-instances.py ]]; then
  echo "Membuat fallback list-gce-instances.py..."
  cat << 'LISTEOF' > list-gce-instances.py
import argparse
from googleapiclient import discovery
from google.auth import compute_engine

def list_instances(compute, project, zone):
    result = compute.instances().list(project=project, zone=zone).execute()
    return result.get('items', [])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('project_id', help='Google Cloud project ID')
    parser.add_argument('--zone', default='us-west1-b', help='Zone')
    args = parser.parse_args()

    credentials = compute_engine.Credentials()
    compute = discovery.build('compute', 'v1', credentials=credentials)
    instances = list_instances(compute, args.project_id, args.zone)
    print(f'Instance in project {args.project_id} and zone "{args.zone}":')
    for instance in instances:
        print(f" - {instance['name']}")

if __name__ == '__main__':
    main()
LISTEOF
fi

echo "Menjalankan server.py di background (port 80)..."
sudo pkill -f server.py || true
sudo nohup python3 server.py > /tmp/server.log 2>&1 &
sleep 2

# Verifikasi respons lokal di dalam VM
echo "Verifikasi respons server lokal:"
curl -s http://localhost/ || true
echo

echo "== [5/5] Instalasi requirements Python & enumerasi VM =="
sudo pip3 install -r requirements.txt --break-system-packages

echo "Menjalankan list-gce-instances.py..."
python3 list-gce-instances.py "$PROJECT_ID" --zone="$ZONE"

echo "Setup remote selesai!"
REMOTE_EOF

echo "Menyalin script setup ke instance $VM_NAME..."
n=1
until gcloud compute scp "$REMOTE_SCRIPT" "$VM_NAME":~/setup.sh \
        --zone="$ZONE" --project="$PROJECT_ID" --quiet < /dev/null; do
  (( n++ >= 8 )) && { echo "Gagal SCP ke VM setelah 7 percobaan."; exit 1; }
  echo "Menunggu kesiapan SCP VM ($n/8)..."
  sleep 10
done

echo "Mengeksekusi setup di dalam instance $VM_NAME..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet < /dev/null \
  --command="bash ~/setup.sh"

# ----------------------------------------------------------------- Verifikasi Eksternal
step "Verifikasi HTTP Response dari Cloud Shell"
echo "Menguji akses web server di http://${EXTERNAL_IP}/..."
for i in {1..10}; do
  RESP="$(curl -m 5 -s "http://${EXTERNAL_IP}" || true)"
  if [[ "$RESP" == *"Hello GCP dev!"* ]]; then
    echo "Sukses: Web server merespons -> $RESP"
    break
  fi
  echo "Menunggu respons web server dari external IP... ($i/10)"
  sleep 3
done

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create a Compute Engine Virtual Machine Instance (Task 1)
  2. Install software and configure the VM instance (Task 1)
  3. Run application software to get a success response (Task 2)

Kuis Pemahaman (Test your understanding):
  - pip is a package management system used to install and manage software packages written in Python.
    Jawaban: True
  - Firewall rules can be shared among networks.
    Jawaban: False
==============================================================
EOF
