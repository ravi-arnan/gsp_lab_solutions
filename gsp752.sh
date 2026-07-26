#!/usr/bin/env bash
# GSP752 - Manage Terraform State
#
#   bash gsp752.sh
#
# Task 1: Work with backends (local → gcs → refresh → cleanup).
# Task 2: Import a Terraform configuration (Docker container).
#
# LAMA: ~15-20 menit dari 60 menit jatah lab.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

REGION="${REGION:-us-west1}"

echo "Project: $PROJECT_ID"
echo "Region:  $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ================================================================= Install Terraform
step "Install Terraform"
if terraform --version 2>/dev/null | grep -q "Terraform v"; then
  echo "Terraform sudah terinstal: $(terraform --version | head -1)"
else
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install -y terraform
  echo "Terraform terinstal: $(terraform --version | head -1)"
fi

# ================================================================= Task 1: Work with backends
step "Task 1a: Buat main.tf — bucket + local backend"

cd "$HOME"
rm -rf terraform-task1
mkdir -p terraform-task1
cd terraform-task1

cat > main.tf << EOF
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
  name        = "$PROJECT_ID"
  location    = "US"
  uniform_bucket_level_access = true
}
EOF

step "Task 1b: terraform init + apply (local backend)"

terraform init -input=false
terraform apply -auto-approve

echo ">>> State file lokal:"
ls -la terraform/state/

step "Task 1c: Ganti ke Cloud Storage (gcs) backend"

cat > main.tf << EOF
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
  name        = "$PROJECT_ID"
  location    = "US"
  uniform_bucket_level_access = true
}
EOF

step "Task 1d: terraform init -migrate-state (local → gcs)"

echo "yes" | terraform init -migrate-state

echo ">>> State sudah di-migrate ke GCS. Cek di console:"
echo "    Cloud Storage > Buckets > $PROJECT_ID > terraform/state/"

step "Task 1e: Tambah label via gcloud, lalu terraform refresh"

gsutil label ch -l "key:value" "gs://$PROJECT_ID"

terraform refresh

echo ">>> State setelah refresh (cek label):"
terraform show | grep -A5 "labels"

step ">>> Klik Check my progress — Work with backends"

echo ">>> Klik 'Check my progress' untuk Task 1, lalu tekan Enter..."
read -r

step "Task 1f: Clean up — revert ke local backend + destroy"

cat > main.tf << EOF
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
  name        = "$PROJECT_ID"
  location    = "US"
  uniform_bucket_level_access = true
  force_destroy = true
}
EOF

echo "yes" | terraform init -migrate-state

terraform apply -auto-approve

terraform destroy -auto-approve

cd "$HOME"
rm -rf terraform-task1

echo ">>> Task 1 selesai."

# ================================================================= Task 2: Import a Terraform configuration
step "Task 2a: Create Docker container"

docker rm -f hashicorp-learn 2>/dev/null || true
docker run --name hashicorp-learn --detach --publish 8080:80 nginx:latest

echo ">>> Container running:"
docker ps --filter "name=hashicorp-learn"

step "Task 2b: Clone learn-terraform-import"

cd "$HOME"
rm -rf learn-terraform-import
git clone https://github.com/hashicorp/learn-terraform-import
cd learn-terraform-import

step "Task 2c: Update provider version"

sed -i 's/version = "~> 3.0.2"/version = ">= 3.5"/' terraform.tf

step "Task 2d: Fix main.tf — comment out host"

sed -i 's/^  host    = "npipe:\/\/\/\/.\/\/pipe\/\/docker_engine"/#   host    = "npipe:\/\/\/\/.\/\/pipe\/\/docker_engine"/' main.tf

step "Task 2e: terraform init"

terraform init -upgrade -input=false

step "Task 2f: Buat empty docker_container resource + import"

cat > docker.tf << 'EOF'
resource "docker_container" "web" {}
EOF

terraform import docker_container.web "$(docker inspect -f '{{.ID}}' hashicorp-learn)"

echo ">>> State setelah import:"
terraform show

step "Task 2g: Generate configuration dari state"

terraform show -no-color > docker.tf

echo ">>> docker.tf sekarang berisi full state output."

step "Task 2h: Clean up docker.tf — sisakan hanya required attributes"

cat > docker.tf << 'EOF'
resource "docker_container" "web" {
    image = "nginx:latest"
    name  = "hashicorp-learn"
    ports {
        external = 8080
        internal = 80
        ip       = "0.0.0.0"
        protocol = "tcp"
    }
}
EOF

terraform plan

step "Task 2i: terraform apply — sinkronkan state"

terraform apply -auto-approve

step "Task 2j: Buat docker_image resource"

cat >> docker.tf << 'EOF'

resource "docker_image" "nginx" {
  name         = "nginx:latest"
}
EOF

terraform apply -auto-approve

step "Task 2k: Update container — pakai image reference"

sed -i 's/image = "nginx:latest"/image = docker_image.nginx.image_id/' docker.tf

terraform apply -auto-approve

step "Task 2l: Ganti external port 8080 → 8081"

sed -i 's/external = 8080/external = 8081/' docker.tf

terraform apply -auto-approve

echo ">>> Container ID baru (terganti):"
docker ps --filter "name=hashicorp-learn"

step ">>> Klik Check my progress — Import a Terraform configuration"

echo ">>> Klik 'Check my progress' untuk Task 2, lalu tekan Enter..."
read -r

step "Task 2m: Destroy all resources"

terraform destroy -auto-approve

echo ">>> Container setelah destroy:"
docker ps --filter "name=hashicorp-learn"

cd "$HOME"
rm -rf learn-terraform-import

echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Work with backends"
echo "  Task 2 - Import a Terraform configuration"
echo "=============================================================="
