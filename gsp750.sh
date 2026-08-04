#!/usr/bin/env bash
# GSP750 - Infrastructure as Code with Terraform
#
#   bash gsp750.sh
#
# Seluruh lab: Build, change, destroy infrastructure;
# create resource dependencies; provision infrastructure.
#
# Semua perintah pakai -auto-approve agar tidak perlu interaksi.
# Setelah selesai, klik Check my progress untuk semua task.
#
# LAMA: ~15 menit dari 58 menit jatah lab.

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
#   ask <NAMA_VAR> <default> <pertanyaan>
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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

ask REGION "us-west1" "Region (cocokkan dengan panel lab)"
ask ZONE "us-west1-b" "Zone (cocokkan dengan panel lab)"
TF_DIR="$HOME/tf-lab"

echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo "Zone:    $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

write_main_tf() {
  mkdir -p "$TF_DIR"
  cat > "$TF_DIR/main.tf"
  echo "main.tf ditulis di $TF_DIR/main.tf"
}

# ================================================================= Install Terraform
step "Install Terraform"
# Cloud Shell kadang punya stub terraform yang bukan binary asli.
# Deteksi: coba jalankan --version dan cari kata "Terraform v".
if terraform --version 2>/dev/null | grep -q "Terraform v"; then
  echo "Terraform sudah terinstal: $(terraform --version | head -1)"
else
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install -y terraform
  echo "Terraform terinstal: $(terraform --version | head -1)"
fi

mkdir -p "$TF_DIR"
cd "$TF_DIR"

# ================================================================= Task 1: Build infrastructure
step "Task 1: Build infrastructure - VPC network"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
EOM

terraform init -input=false
terraform apply -auto-approve
terraform show

# ================================================================= Task 2: Change infrastructure
step "Task 2a: Add compute instance"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}
EOM

terraform apply -auto-approve
echo ">>> Instance created."

step "Task 2b: Add tags"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}
EOM

terraform apply -auto-approve
echo ">>> Tags added."

step "Task 2c: Destructive change - change boot disk image"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}
EOM

terraform apply -auto-approve
echo ">>> Boot disk changed to cos-cloud."

step "Task 2d: Destroy all infrastructure"

terraform destroy -auto-approve
echo ">>> Infrastructure destroyed."

# ================================================================= Task 3: Create resource dependencies
step "Task 3a: Recreate network and instance"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}
EOM

terraform apply -auto-approve
echo ">>> Resources recreated."

step "Task 3b: Assign static IP"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
}
EOM

terraform plan -out static_ip
terraform apply "static_ip"
echo ">>> Static IP assigned."

step "Task 3c: Create bucket and instance with explicit dependency"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
}

resource "google_storage_bucket" "example_bucket" {
  name     = "$PROJECT_ID"
  location = "US"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_compute_instance" "another_instance" {
  depends_on = [google_storage_bucket.example_bucket]

  name         = "terraform-instance-2"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
    }
  }
}
EOM

terraform plan
terraform apply -auto-approve
echo ">>> Bucket and dependent instance created."

step "Task 3d: Remove bucket and second instance"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
}
EOM

terraform apply -auto-approve
echo ">>> Bucket and second instance removed."

# ================================================================= Task 4: Provision infrastructure
step "Task 4a: Add provisioner (local-exec)"

write_main_tf << EOM
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
  zone    = "$ZONE"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web", "dev"]

  provisioner "local-exec" {
    command = "echo \${self.name}:  \${self.network_interface[0].access_config[0].nat_ip} >> ip_address.txt"
  }

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
}
EOM

echo ">>> Provisioner ditambahkan. Taint instance agar provisioner jalan..."
terraform taint google_compute_instance.vm_instance
terraform apply -auto-approve

echo
echo "--- ip_address.txt ---"
cat "$TF_DIR/ip_address.txt" 2>/dev/null || echo "(belum ada, mungkin provisioner belum jalan)"
echo

echo "=============================================================="
echo "SELESAI! Semua task sudah dikerjakan."
echo "Klik Check my progress untuk verifikasi:"
echo "  - Create resources in Terraform"
echo "  - Change the infrastructure"
echo "  - Make destructive changes"
echo "  - Create resource dependencies"
echo "  - Create a bucket dependent instance"
echo "  - Provision infrastructure"
echo "=============================================================="
