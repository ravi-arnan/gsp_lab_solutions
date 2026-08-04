#!/usr/bin/env bash
# GSP345 - Build Infrastructure with Terraform on Google Cloud: Challenge Lab
#
#   bash gsp345.sh
#
# Semua task: import existing instances, remote backend, modify, destroy,
#             registry module (VPC), firewall.
#
# LAMA: ~20-25 menit dari 90 menit jatah lab.

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

# Auto-detect zone dari instance yang sudah ada
ask ZONE "" "Zone (cocokkan dengan panel lab)"
if [[ -z "$ZONE" ]]; then
  ZONE=$(gcloud compute instances list --filter="name=tf-instance-1" --format="value(zone)" --limit=1 2>/dev/null)
  ZONE="${ZONE:-europe-west1-d}"
fi

# Region ikut zone: subnet VPC di Task 6 harus se-region dengan instance,
# kalau tidak apply-nya gagal.
REGION="${REGION:-${ZONE%-*}}"

# === Sesuaikan suffix berikut dengan angka di halaman lab-mu ===
BUCKET_SUFFIX="${BUCKET_SUFFIX:-616380}"
VPC_SUFFIX="${VPC_SUFFIX:-951548}"
INSTANCE3_SUFFIX="${INSTANCE3_SUFFIX:-961673}"

BUCKET_NAME="tf-bucket-${BUCKET_SUFFIX}"
VPC_NAME="tf-vpc-${VPC_SUFFIX}"
INSTANCE3_NAME="tf-instance-${INSTANCE3_SUFFIX}"

echo "Project:        $PROJECT_ID"
echo "Region:         $REGION"
echo "Zone:           $ZONE"
echo "Bucket:         $BUCKET_NAME"
echo "VPC:            $VPC_NAME"
echo "Instance 3:     $INSTANCE3_NAME"

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

# ================================================================= Task 1: Create the configuration files
step "Task 1: Buat struktur direktori dan file"

cd "$HOME"
rm -rf terraform-challenge
mkdir -p terraform-challenge/modules/instances
mkdir -p terraform-challenge/modules/storage
cd terraform-challenge

cat > variables.tf << EOF
variable "region" {
  description = "Region"
  default     = "$REGION"
}

variable "zone" {
  description = "Zone"
  default     = "$ZONE"
}

variable "project_id" {
  description = "Project ID"
  default     = "$PROJECT_ID"
}
EOF

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
EOF

cat > modules/instances/variables.tf << EOF
variable "region" {
  description = "Region"
}

variable "zone" {
  description = "Zone"
}

variable "project_id" {
  description = "Project ID"
}
EOF

cat > modules/instances/outputs.tf << EOF
output "instance1_self_link" {
  value = google_compute_instance.tf-instance-1.self_link
}

output "instance2_self_link" {
  value = google_compute_instance.tf-instance-2.self_link
}
EOF

cat > modules/storage/variables.tf << EOF
variable "project_id" {
  description = "Project ID"
}

variable "bucket_name" {
  description = "Bucket name"
}
EOF

cat > modules/storage/outputs.tf << EOF
output "bucket_name" {
  value = google_storage_bucket.state-bucket.name
}

output "bucket_url" {
  value = google_storage_bucket.state-bucket.url
}
EOF

cat > modules/storage/storage.tf << EOF
resource "google_storage_bucket" "state-bucket" {
  name          = var.bucket_name
  project       = var.project_id
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF

echo ">>> Struktur direktori:"
find . -type f | sort

step ">>> Task 1: terraform init"

terraform init -input=false

echo ">>> Task 1 selesai. Klik Check my progress jika perlu."

# ================================================================= Task 2: Import infrastructure
step "Task 2: Import existing instances"

# Discover existing instance details
get_instance_attr() {
  local name=$1 attr=$2
  gcloud compute instances describe "$name" --zone="$ZONE" --format="value($attr)" 2>/dev/null || \
    gcloud compute instances describe "$name" --zone=europe-west1-c --format="value($attr)"
}

echo ">>> Mendapatkan detail instance tf-instance-1..."
INST1_MACHINE=$(get_instance_attr tf-instance-1 "machineType.basename()")
INST1_BOOT_DISK=$(get_instance_attr tf-instance-1 "disks[].source.basename()" | cut -d';' -f1)
INST1_IMAGE=$(gcloud compute disks describe "$INST1_BOOT_DISK" --zone="$ZONE" --format="value(sourceImage)" 2>/dev/null || \
              gcloud compute disks describe "$INST1_BOOT_DISK" --zone=europe-west1-c --format="value(sourceImage)")
INST1_NETWORK=$(get_instance_attr tf-instance-1 "networkInterfaces[].network.basename()" | cut -d';' -f1)
INST1_SUBNET=$(get_instance_attr tf-instance-1 "networkInterfaces[].subnetwork.basename()" | cut -d';' -f1)

echo ">>> Mendapatkan detail instance tf-instance-2..."
INST2_MACHINE=$(get_instance_attr tf-instance-2 "machineType.basename()")
INST2_BOOT_DISK=$(get_instance_attr tf-instance-2 "disks[].source.basename()" | cut -d';' -f1)
INST2_IMAGE=$(gcloud compute disks describe "$INST2_BOOT_DISK" --zone="$ZONE" --format="value(sourceImage)" 2>/dev/null || \
              gcloud compute disks describe "$INST2_BOOT_DISK" --zone=europe-west1-c --format="value(sourceImage)")
INST2_NETWORK=$(get_instance_attr tf-instance-2 "networkInterfaces[].network.basename()" | cut -d';' -f1)
INST2_SUBNET=$(get_instance_attr tf-instance-2 "networkInterfaces[].subnetwork.basename()" | cut -d';' -f1)

echo "  tf-instance-1: machine=$INST1_MACHINE, boot_disk=$INST1_BOOT_DISK, image=$INST1_IMAGE, network=$INST1_NETWORK, subnet=$INST1_SUBNET"
echo "  tf-instance-2: machine=$INST2_MACHINE, boot_disk=$INST2_BOOT_DISK, image=$INST2_IMAGE, network=$INST2_NETWORK, subnet=$INST2_SUBNET"

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
EOF

cat > modules/instances/instances.tf << EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "$INST1_MACHINE"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST1_IMAGE"
    }
  }

  network_interface {
    network = "$INST1_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "$INST2_MACHINE"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST2_IMAGE"
    }
  }

  network_interface {
    network = "$INST2_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}
EOF

cat > modules/storage/storage.tf << EOF
resource "google_storage_bucket" "state-bucket" {
  name          = var.bucket_name
  project       = var.project_id
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF

terraform init -input=false

# Import existing instances
echo ">>> Importing tf-instance-1..."
terraform import module.instances.google_compute_instance.tf-instance-1 \
  "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-1" || true

echo ">>> Importing tf-instance-2..."
terraform import module.instances.google_compute_instance.tf-instance-2 \
  "projects/$PROJECT_ID/zones/$ZONE/instances/tf-instance-2" || true

terraform apply -auto-approve

echo ">>> Task 2 selesai. Klik Check my progress."

# ================================================================= Task 3: Configure a remote backend
step "Task 3: Configure a remote backend"

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  bucket_name = "$BUCKET_NAME"
}
EOF

terraform init -input=false

# Hapus bucket lama dari run sebelumnya agar terraform bisa create
gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null || true

terraform apply -auto-approve

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
  backend "gcs" {
    bucket  = "$BUCKET_NAME"
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  bucket_name = "$BUCKET_NAME"
}
EOF

echo "yes" | terraform init -migrate-state

echo ">>> Task 3 selesai. Klik Check my progress."

# ================================================================= Task 4: Modify and update infrastructure
step "Task 4: Modify and update infrastructure"

cat > modules/instances/instances.tf << EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST1_IMAGE"
    }
  }

  network_interface {
    network = "$INST1_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST2_IMAGE"
    }
  }

  network_interface {
    network = "$INST2_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}

resource "google_compute_instance" "tf-instance-3" {
  name         = "$INSTANCE3_NAME"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST1_IMAGE"
    }
  }

  network_interface {
    network = "$INST1_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}
EOF

terraform init -input=false

# Import instance3 jika sudah ada dari run sebelumnya
terraform import module.instances.google_compute_instance.tf-instance-3 \
  "projects/$PROJECT_ID/zones/$ZONE/instances/$INSTANCE3_NAME" 2>/dev/null || true

terraform apply -auto-approve

echo ">>> Task 4 selesai. Klik Check my progress."

# ================================================================= Task 5: Destroy resources
step "Task 5: Destroy tf-instance-3"

# Task 5 menghapus instance yang baru dibuat Task 4, jadi checkpoint Task 4
# harus hijau dulu. Jeda hanya kalau interaktif (bukan curl | bash).
if [[ -t 0 ]]; then
  read -r -p "Pastikan checkpoint Task 4 sudah hijau, lalu tekan Enter..." _
fi

cat > modules/instances/instances.tf << EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST1_IMAGE"
    }
  }

  network_interface {
    network = "$INST1_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST2_IMAGE"
    }
  }

  network_interface {
    network = "$INST2_NETWORK"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}
EOF

terraform init -input=false
terraform apply -auto-approve

echo ">>> Task 5 selesai. Klik Check my progress."

# ================================================================= Task 6: Use a module from the Registry
step "Task 6: Use module from Registry (VPC)"

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
  backend "gcs" {
    bucket  = "$BUCKET_NAME"
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  bucket_name = "$BUCKET_NAME"
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "10.0.0"

  network_name            = "$VPC_NAME"
  project_id              = var.project_id
  routing_mode            = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name   = "subnet-02"
      subnet_ip     = "10.10.20.0/24"
      subnet_region = var.region
    }
  ]
}
EOF

rm -f .terraform.lock.hcl
terraform init -input=false -upgrade
terraform apply -auto-approve

# Update instances to connect to VPC subnets
cat > modules/instances/instances.tf << EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST1_IMAGE"
    }
  }

  network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-01"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "$INST2_IMAGE"
    }
  }

  network_interface {
    network    = "$VPC_NAME"
    subnetwork = "subnet-02"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
  EOT
}
EOF

rm -f .terraform.lock.hcl
terraform init -input=false -upgrade
terraform apply -auto-approve

echo ">>> Task 6 selesai. Klik Check my progress."

# ================================================================= Task 7: Configure a firewall
step "Task 7: Configure firewall"

cat > main.tf << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0, < 7.0"
    }
  }
  backend "gcs" {
    bucket  = "$BUCKET_NAME"
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source     = "./modules/instances"
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  bucket_name = "$BUCKET_NAME"
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "10.0.0"

  network_name            = "$VPC_NAME"
  project_id              = var.project_id
  routing_mode            = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name   = "subnet-02"
      subnet_ip     = "10.10.20.0/24"
      subnet_region = var.region
    }
  ]
}

resource "google_compute_firewall" "tf-firewall" {
  name    = "tf-firewall"
  network = module.vpc.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}
EOF

rm -f .terraform.lock.hcl
terraform init -input=false -upgrade
terraform apply -auto-approve

echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk setiap task:"
echo "  Task 1 - Create the configuration files"
echo "  Task 2 - Import infrastructure"
echo "  Task 3 - Configure a remote backend"
echo "  Task 4 - Modify and update infrastructure"
echo "  Task 5 - Destroy resources"
echo "  Task 6 - Use a module from the Registry"
echo "  Task 7 - Configure a firewall"
echo "=============================================================="
