#!/usr/bin/env bash
# GSP751 - Interact with Terraform Modules
#
#   bash gsp751.sh
#
# Checkpoint:
#   Task 1 (50 pts) - Provision infrastructure (VPC from Terraform Registry module)
#   Task 2 (50 pts) - Build a module (GCS static website bucket module + upload files)
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
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="us-central1"
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

# ================================================================= Task 1: Use modules from the Registry
step "Task 1a: Clone repository terraform-google-network"
cd "$HOME"
rm -rf terraform-google-network
git clone https://github.com/terraform-google-modules/terraform-google-network
mkdir -p "$HOME/terraform-google-network/examples/simple_project"
cd "$HOME/terraform-google-network"
git checkout tags/v6.0.1 -b v6.0.1 2>/dev/null || git checkout v6.0.1 2>/dev/null || true

step "Task 1b: Konfigurasi variables.tf dan main.tf"
cd "$HOME/terraform-google-network/examples/simple_project"

cat > variables.tf <<EOF
variable "project_id" {
  description = "The project ID to host the network in"
  default     = "$PROJECT_ID"
}

variable "network_name" {
  description = "The name of the network to be created"
  default     = "example-vpc"
}
EOF

cat > main.tf <<EOF
module "test-vpc-module" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 6.0"
  project_id   = var.project_id
  network_name = var.network_name
  mtu          = 1460

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = "$REGION"
    },
    {
      subnet_name           = "subnet-02"
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = "$REGION"
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
    },
    {
      subnet_name               = "subnet-03"
      subnet_ip                 = "10.10.30.0/24"
      subnet_region             = "$REGION"
      subnet_flow_logs          = "true"
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
      subnet_flow_logs_sampling = 0.7
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      subnet_flow_logs_filter   = "false"
    }
  ]
}
EOF

cat > outputs.tf <<'EOF'
output "network_name" {
  value       = module.test-vpc-module.network_name
  description = "The name of the VPC being created"
}

output "network_self_link" {
  value       = module.test-vpc-module.network_self_link
  description = "The URI of the VPC being created"
}

output "project_id" {
  value       = module.test-vpc-module.project_id
  description = "VPC project id"
}

output "subnets_names" {
  value       = module.test-vpc-module.subnets_names
  description = "The names of the subnets being created"
}

output "subnets_ips" {
  value       = module.test-vpc-module.subnets_ips
  description = "The IP and cidrs of the subnets being created"
}

output "subnets_regions" {
  value       = module.test-vpc-module.subnets_regions
  description = "The region where subnets will be created"
}

output "subnets_private_access" {
  value       = module.test-vpc-module.subnets_private_access
  description = "Whether the subnets will have access to Google API's without a public IP"
}

output "subnets_flow_logs" {
  value       = module.test-vpc-module.subnets_flow_logs
  description = "Whether the subnets will have VPC flow logs enabled"
}

output "subnets_secondary_ranges" {
  value       = module.test-vpc-module.subnets_secondary_ranges
  description = "The secondary ranges associated with these subnets"
}

output "route_names" {
  value       = module.test-vpc-module.route_names
  description = "The routes associated with this VPC"
}
EOF

step "Task 1c: terraform init & apply (Provision infrastructure)"
terraform init -input=false
terraform apply -input=false -auto-approve

step "Task 1d: Clean up Task 1 (destroy & delete folder)"
terraform destroy -input=false -auto-approve
cd "$HOME"
rm -rf terraform-google-network

echo ">>> Task 1 selesai."

# ================================================================= Task 2: Build a module
step "Task 2a: Siapkan modul gcs-static-website-bucket"
cd "$HOME"
mkdir -p "$HOME/modules/gcs-static-website-bucket"
cd "$HOME/modules/gcs-static-website-bucket"

cat > README.md <<'EOF'
# GCS static website bucket

This module provisions Cloud Storage buckets configured for static website hosting.
EOF

cat > LICENSE <<'EOF'
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOF

cat > website.tf <<'EOF'
resource "google_storage_bucket" "bucket" {
  name               = var.name
  project            = var.project_id
  location           = var.location
  storage_class      = var.storage_class
  labels             = var.labels
  force_destroy      = var.force_destroy
  uniform_bucket_level_access = true

  versioning {
    enabled = var.versioning
  }

  dynamic "retention_policy" {
    for_each = var.retention_policy == null ? [] : [var.retention_policy]
    content {
      is_locked        = var.retention_policy.is_locked
      retention_period = var.retention_policy.retention_period
    }
  }

  dynamic "encryption" {
    for_each = var.encryption == null ? [] : [var.encryption]
    content {
      default_kms_key_name = var.encryption.default_kms_key_name
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lookup(lifecycle_rule.value.action, "storage_class", null)
      }
      condition {
        age                   = lookup(lifecycle_rule.value.condition, "age", null)
        created_before        = lookup(lifecycle_rule.value.condition, "created_before", null)
        with_state            = lookup(lifecycle_rule.value.condition, "with_state", null)
        matches_storage_class = lookup(lifecycle_rule.value.condition, "matches_storage_class", null)
        num_newer_versions    = lookup(lifecycle_rule.value.condition, "num_newer_versions", null)
      }
    }
  }
}
EOF

cat > variables.tf <<'EOF'
variable "name" {
  description = "The name of the bucket."
  type        = string
}

variable "project_id" {
  description = "The ID of the project to create the bucket in."
  type        = string
}

variable "location" {
  description = "The location of the bucket."
  type        = string
}

variable "storage_class" {
  description = "The Storage Class of the new bucket."
  type        = string
  default     = null
}

variable "labels" {
  description = "A set of key/value label pairs to assign to the bucket."
  type        = map(string)
  default     = null
}

variable "bucket_policy_only" {
  description = "Enables Bucket Policy Only access to a bucket."
  type        = bool
  default     = true
}

variable "versioning" {
  description = "While set to true, versioning is fully enabled for this bucket."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "When deleting a bucket, this boolean option will delete all contained objects. If false, Terraform will fail to delete buckets which contain objects."
  type        = bool
  default     = true
}

variable "iam_members" {
  description = "The list of IAM members to grant permissions on the bucket."
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

variable "retention_policy" {
  description = "Configuration of the bucket's data retention policy for how long objects in the bucket should be retained."
  type = object({
    is_locked        = bool
    retention_period = number
  })
  default = null
}

variable "encryption" {
  description = "A Cloud KMS key that will be used to encrypt objects inserted into this bucket"
  type = object({
    default_kms_key_name = string
  })
  default = null
}

variable "lifecycle_rules" {
  description = "The bucket's Lifecycle Rules configuration."
  type = list(object({
    action    = any
    condition = any
  }))
  default = []
}
EOF

cat > outputs.tf <<'EOF'
output "bucket" {
  description = "The created storage bucket"
  value       = google_storage_bucket.bucket
}
EOF

step "Task 2b: Siapkan root module di $HOME"
cd "$HOME"

cat > main.tf <<EOF
module "gcs-static-website-bucket" {
  source = "./modules/gcs-static-website-bucket"

  name       = var.name
  project_id = var.project_id
  location   = "$REGION"

  lifecycle_rules = [{
    action = {
      type = "Delete"
    }
    condition = {
      age        = 365
      with_state = "ANY"
    }
  }]
}
EOF

cat > outputs.tf <<'EOF'
output "bucket-name" {
  description = "Bucket names."
  value       = "module.gcs-static-website-bucket.bucket"
}
EOF

cat > variables.tf <<EOF
variable "project_id" {
  description = "The ID of the project in which to provision resources."
  type        = string
  default     = "$PROJECT_ID"
}

variable "name" {
  description = "Name of the buckets to create."
  type        = string
  default     = "$PROJECT_ID"
}
EOF

step "Task 2c: terraform init & apply (Provision bucket)"
terraform init -input=false

# Idempoten: jika bucket sudah ada di GCP tetapi belum ada di state terraform
if ! terraform state list 2>/dev/null | grep -q 'module\.gcs-static-website-bucket\.google_storage_bucket\.bucket'; then
  if gcloud storage buckets describe "gs://$PROJECT_ID" &>/dev/null || gsutil ls -b "gs://$PROJECT_ID" &>/dev/null; then
    echo "Bucket gs://$PROJECT_ID sudah ada di GCP, mengimpor ke Terraform state..."
    terraform import -input=false module.gcs-static-website-bucket.google_storage_bucket.bucket "$PROJECT_ID" || true
  fi
fi

terraform apply -input=false -auto-approve

step "Task 2d: Unggah sample HTML ke bucket"
curl -sL https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/index.html -o index.html || true
curl -sL https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/error.html -o error.html || true

[[ ! -s index.html ]] && echo "<html><body><h1>Nothing to see here</h1></body></html>" > index.html
[[ ! -s error.html ]] && echo "<html><body><h1>Error</h1></body></html>" > error.html

gcloud storage cp index.html error.html "gs://$PROJECT_ID" 2>/dev/null || gsutil cp index.html error.html "gs://$PROJECT_ID"

step "Selesai"
cat <<EOF
==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Task 1 - Provision infrastructure
  2. Task 2 - Build a module

Bucket gs://$PROJECT_ID tetap aktif dengan index.html dan error.html
agar verifikasi Task 2 lolos 100%. Jangan destroy sebelum hijau!
==============================================================
EOF
