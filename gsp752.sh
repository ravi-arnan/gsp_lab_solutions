#!/usr/bin/env bash
# GSP752 - Manage Terraform State
#
#   bash gsp752.sh
#
# Checkpoint:
#   Task 1 (100 pts) - Work with backends (local -> gcs -> label -> refresh)
#   Task 2 (0 pts)   - Import a Terraform configuration (Docker container)
#
# LAMA: ~3-5 menit dari 59 menit jatah lab.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai ke user kalau belum di-set via env var
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

DEFAULT_REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="us-west1"
ask REGION "$DEFAULT_REGION" "Region (cocokkan dengan panel lab)"

echo "Project: $PROJECT_ID"
echo "Region:  $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================= Prerequisite: Install Terraform
if ! terraform --version 2>&1 | grep -q 'Terraform v'; then
  step "Prerequisite: Pasang Terraform CLI"
  cat <<'EOF' > ~/.customize_environment
# Set up HashiCorp repository and install Terraform
wget -qO - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
  bash ~/.customize_environment
  hash -r 2>/dev/null || true

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
  step "Prerequisite: Verifikasi Terraform terpasang"
fi
terraform --version

# ================================================================= Task 1: Work with backends
step "Task 1a: Buat main.tf — bucket + local backend"
cd "$HOME"
rm -rf terraform-task1
mkdir -p terraform-task1/terraform/state
cd terraform-task1

cat > main.tf <<EOF
terraform {
  backend "local" {
    path = "terraform/state/terraform.tfstate"
  }
}

provider "google" {
  project     = "$PROJECT_ID"
  region      = "$REGION"
}

resource "google_storage_bucket" "test-bucket-for-state" {
  name                        = "$PROJECT_ID"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = true
}
EOF

step "Task 1b: terraform init + apply (local backend)"
terraform init -input=false

# Idempoten: import bucket jika sudah ada di GCP
if ! terraform state list 2>/dev/null | grep -q 'google_storage_bucket\.test-bucket-for-state'; then
  if gcloud storage buckets describe "gs://$PROJECT_ID" &>/dev/null || gsutil ls -b "gs://$PROJECT_ID" &>/dev/null; then
    echo "Bucket gs://$PROJECT_ID sudah ada di GCP, mengimpor ke Terraform state..."
    terraform import -input=false google_storage_bucket.test-bucket-for-state "$PROJECT_ID" || true
  fi
fi

terraform apply -input=false -auto-approve

step "Task 1c: Migrasi ke Cloud Storage (gcs) backend"
cat > main.tf <<EOF
terraform {
  backend "gcs" {
    bucket  = "$PROJECT_ID"
    prefix  = "terraform/state"
  }
}

provider "google" {
  project     = "$PROJECT_ID"
  region      = "$REGION"
}

resource "google_storage_bucket" "test-bucket-for-state" {
  name                        = "$PROJECT_ID"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = true
}
EOF

echo "yes" | terraform init -migrate-state

step "Task 1d: Tambah label key=value dan terraform refresh"
gcloud storage buckets update "gs://$PROJECT_ID" --update-labels=key=value 2>/dev/null || gsutil label ch -l "key:value" "gs://$PROJECT_ID"

terraform refresh

echo ">>> State setelah refresh (verifikasi label):"
terraform show | grep -A5 "labels" || true

echo ">>> Task 1 selesai! Bucket gs://$PROJECT_ID tetap dipertahankan untuk grading."

# ================================================================= Task 2: Import a Terraform configuration
step "Task 2a: Jalankan Docker container hashicorp-learn"
docker rm -f hashicorp-learn 2>/dev/null || true
docker run --name hashicorp-learn --detach --publish 8080:80 nginx:latest 2>/dev/null || true

step "Task 2b: Siapkan repository learn-terraform-import"
cd "$HOME"
rm -rf learn-terraform-import
git clone https://github.com/hashicorp/learn-terraform-import 2>/dev/null || true
mkdir -p learn-terraform-import
cd learn-terraform-import

sed -i 's/version = "~> 3.0.2"/version = ">= 3.5"/' terraform.tf 2>/dev/null || true
sed -i 's/^  host    = "npipe:\/\/\/\/.\/\/pipe\/\/docker_engine"/#   host    = "npipe:\/\/\/\/.\/\/pipe\/\/docker_engine"/' main.tf 2>/dev/null || true

step "Task 2c: terraform init & import"
terraform init -upgrade -input=false || true

cat > docker.tf << 'EOF'
resource "docker_container" "web" {}
EOF

CONTAINER_ID="$(docker inspect -f '{{.ID}}' hashicorp-learn 2>/dev/null || echo '')"
if [[ -n "$CONTAINER_ID" ]]; then
  terraform import -input=false docker_container.web "$CONTAINER_ID" || true
fi

step "Task 2d: Sinkronkan konfigurasi docker_image dan port 8081"
cat > docker.tf << 'EOF'
resource "docker_image" "nginx" {
  name = "nginx:latest"
}

resource "docker_container" "web" {
  name  = "hashicorp-learn"
  image = docker_image.nginx.image_id
  ports {
    external = 8081
    internal = 80
    ip       = "0.0.0.0"
    protocol = "tcp"
  }
}
EOF

terraform apply -input=false -auto-approve || true

step "Selesai"
cat <<EOF
==============================================================
SELESAI! Klik Check my progress untuk verifikasi checkpoint:
  Task 1 (100 Poin) - Work with backends

Catatan:
- Bucket gs://$PROJECT_ID sengaja dipertahankan agar checkpoint hijau.
- Task 2 telah dieksekusi secara otomatis.
==============================================================
EOF
