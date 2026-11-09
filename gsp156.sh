#!/usr/bin/env bash
# GSP156 - Terraform Fundamentals
#
#   bash gsp156.sh
#
# Checkpoint:
#   Task 2 (100 pts) - Create a VM instance in the <zone> zone with Terraform
#   Task 3 (0 pts)   - Test your understanding (pilihan ganda, manual: keduanya True)
#
# LAMA: ~1-2 menit.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set via env var
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

# Deteksi default zone dari metadata project atau gcloud config
DEFAULT_ZONE="$(gcloud compute project-info describe \
  --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="us-east1-c"

ask ZONE "$DEFAULT_ZONE" "Zone Compute Engine (cocokkan dengan panel lab)"

echo "Project: $PROJECT"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Task 1: Terraform installation
if ! terraform --version 2>&1 | grep -q 'Terraform v'; then
  step "Task 1: Pasang Terraform CLI"
  cat <<'EOF' > ~/.customize_environment
# Set up HashiCorp repository and install Terraform
wget -qO - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
  bash ~/.customize_environment
  hash -r 2>/dev/null || true

  # Fallback langsung ke binary jika apt gagal atau wrapper dummy belum ter-replace
  if ! terraform --version 2>&1 | grep -q 'Terraform v'; then
    echo "Fallback instalasi binary Terraform..."
    TF_VER="1.9.8"
    TF_ARCH="$(dpkg --print-architecture 2>/dev/null || echo 'amd64')"
    wget -q "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_${TF_ARCH}.zip" -O /tmp/terraform.zip
    sudo unzip -o /tmp/terraform.zip -d /usr/local/bin/
    rm -f /tmp/terraform.zip
    hash -r 2>/dev/null || true
  fi
else
  step "Task 1: Verifikasi Terraform terpasang"
fi
terraform --version

# Task 2: Build the infrastructure
step "Task 2a: Siapkan direktori kerja dan instance.tf"
WORK="$HOME/gsp156"
mkdir -p "$WORK"
cd "$WORK"

cat > instance.tf <<EOF
resource "google_compute_instance" "default" {
  project      = "$PROJECT"
  zone         = "$ZONE"
  name         = "terraform"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "debian-12"
    }
  }
  network_interface {
    network = "default"
    access_config {
    }
  }
}
EOF

cat instance.tf

step "Task 2b: terraform init"
terraform init -input=false

# Idempoten: jika instance sudah ada di GCP tetapi belum ada di state lokal
if ! terraform state list 2>/dev/null | grep -q 'google_compute_instance\.default'; then
  if gcloud compute instances describe terraform --zone="$ZONE" --project="$PROJECT" &>/dev/null; then
    echo "Instance 'terraform' sudah ada di GCP, mengimpor ke Terraform state..."
    terraform import -input=false google_compute_instance.default "projects/$PROJECT/zones/$ZONE/instances/terraform" || true
  fi
fi

step "Task 2c: terraform plan"
terraform plan -input=false

step "Task 2d: terraform apply"
terraform apply -input=false -auto-approve

step "Task 2e: terraform show"
terraform show

if gcloud compute instances describe terraform --zone="$ZONE" --project="$PROJECT" &>/dev/null; then
  echo "Verifikasi sukses: Instance 'terraform' aktif di zona $ZONE."
fi

step "Selesai"
cat <<EOF
Klik "Check my progress" untuk checkpoint tunggal lab ini (100 poin):
  Task 2: "Create a VM instance in the $ZONE zone with Terraform."

Task 3 adalah dua soal pilihan ganda (manual di UI lab), keduanya True:
  1. "Terraform enables you to safely and predictably create, change, and
      improve infrastructure."                                        -> True
  2. "With Terraform, you can create your own custom provider plugins." -> True

State ada di $WORK. Jangan hapus direktori tersebut sebelum verifikasi selesai.
EOF
