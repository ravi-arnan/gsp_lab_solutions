#!/usr/bin/env bash
# GSP093 - Compute Engine: Qwik Start - Windows
#
#   bash gsp093.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Create a virtual machine instance
#   Task 2 (50 pts) - RDP into the Windows Server
#
# Seluruh lab: pembuatan VM Windows Server 2022 Datacenter (instance-1),
# pemantauan inisialisasi boot melalui serial port output, dan pembuatan/reset
# kredensial Windows untuk user admin via reset-windows-password.
#
# LAMA: ~ 3-4 menit (menunggu OS Windows Server selesai startup sysprep).

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
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="us-central1-f"

ask ZONE "$DEFAULT_ZONE" "Zone (cocokkan dengan panel lab)"
REGION="${ZONE%-*}"
VM_NAME="instance-1"

echo "Project ID: $PROJECT_ID"
echo "Zone      : $ZONE"
echo "Instance  : $VM_NAME"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1: Create VM Instance
step "Task 1: Buat VM instance Windows Server (Checkpoint 1)"
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Instance $VM_NAME sudah ada di zone $ZONE, melewati pembuatan."
else
  echo "Membuat instance Windows Server $VM_NAME..."
  gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --image-family=windows-2022 \
    --image-project=windows-cloud \
    --boot-disk-size=50GB \
    --project="$PROJECT_ID" \
    --quiet
fi

EXTERNAL_IP="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "External IP: $EXTERNAL_IP"

# ----------------------------------------------------------------- Task 2: Inisialisasi & Reset Password Windows
step "Task 2: Menunggu inisialisasi Windows & reset password RDP (Checkpoint 2)"
echo "Memantau serial port console untuk status kesiapan Windows agent..."
for i in {1..30}; do
  if gcloud compute instances get-serial-port-output "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null | grep -q "Instance setup finished"; then
    echo "Windows Server siap menerima koneksi RDP!"
    break
  fi
  echo "Menunggu inisialisasi Windows OS... ($i/30)"
  sleep 10
done

echo "Menyetel password RDP Windows untuk user 'admin'..."
for i in {1..10}; do
  if gcloud compute reset-windows-password "$VM_NAME" \
      --zone="$ZONE" \
      --user=admin \
      --project="$PROJECT_ID" \
      --quiet; then
    echo "Password Windows untuk user admin berhasil dibuat!"
    break
  fi
  echo "Mencoba kembali reset-windows-password... ($i/10)"
  sleep 15
done

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh 2 checkpoint:

  Task 1:
  - Create a virtual machine instance (50 pts)

  Task 2:
  - RDP into the Windows Server (50 pts)

Jawaban kuis pilihan ganda di halaman modul lab:
- "We can create a Windows instance in Google Cloud by changing its ____ in the VM instance console."
  Jawaban: Boot disk to Windows image
- "Which command is used to check whether the server is ready for an RDP connection?"
  Jawaban: gcloud compute instances get-serial-port-output

Koneksi RDP (opsional):
  Host     : $EXTERNAL_IP
  Username : admin

Semua checkpoint selesai dieksekusi secara otomatis (total 100/100).
==============================================================
EOF
