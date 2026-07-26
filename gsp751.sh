#!/usr/bin/env bash
# GSP751 - Interact with Terraform Modules
#
#   bash gsp751.sh
#
# Seluruh lab: Use modules from the Registry (Task 1) dan Build a module (Task 2).
# Semua perintah pakai -auto-approve agar tidak perlu interaksi.
#
# LAMA: ~10-12 menit dari 58 menit jatah lab.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

REGION="${REGION:-europe-west1}"

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

# ================================================================= Task 1: Use modules from the Registry
step "Task 1a: Clone terraform-google-network repo"

cd "$HOME"
rm -rf terraform-google-network
git clone --depth 1 --branch v6.0.1 https://github.com/terraform-google-modules/terraform-google-network
cd terraform-google-network/examples/simple_project

step "Task 1b: Set project_id dan network_name di variables.tf"

sed -i '/^variable "project_id" {/,/^}/c\
variable "project_id" {\
  description = "The project ID to host the network in"\
  default     = "'"$PROJECT_ID"'"\
}' variables.tf

cat >> variables.tf << 'EOF'

variable "network_name" {
  description = "The name of the network to be created"
  default     = "example-vpc"
}
EOF

step "Task 1c: Update main.tf — use var.network_name, region europe-west1"

sed -i 's/network_name = "my-custom-mode-network"/network_name = var.network_name/' main.tf
sed -i 's/"us-west1"/"europe-west1"/g' main.tf

echo "--- variables.tf ---"
grep -A5 'variable "project_id"' variables.tf
grep -A5 'variable "network_name"' variables.tf

echo "--- main.tf ---"
grep -E "(network_name|subnet_region)" main.tf

step "Task 1d: terraform init + apply"

terraform init -input=false
terraform apply -auto-approve

step "Task 1e: terraform destroy + cleanup"

terraform destroy -auto-approve
cd "$HOME"
rm -rf terraform-google-network

echo ">>> Task 1 selesai. Klik Check my progress untuk verifikasi."

# ================================================================= Task 2: Build a module
step "Task 2a: Buat struktur module gcs-static-website-bucket"

cd "$HOME"
mkdir -p modules/gcs-static-website-bucket

cd modules/gcs-static-website-bucket

cat > README.md << 'EOF'
# GCS static website bucket

This module provisions Cloud Storage buckets configured for static website hosting.
EOF

cat > LICENSE << 'EOF'
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

step "Task 2b: website.tf — resource google_storage_bucket"

cat > website.tf << 'EOF'
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

step "Task 2c: variables.tf untuk module"

cat > variables.tf << 'MODEOF'
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
MODEOF

step "Task 2d: outputs.tf untuk module"

cat > outputs.tf << 'EOF'
output "bucket" {
  description = "The created storage bucket"
  value       = google_storage_bucket.bucket
}
EOF

echo "Struktur module:"
find . -type f | sort

step "Task 2e: Root module — main.tf, variables.tf, outputs.tf"

cd "$HOME"

cat > main.tf << EOF
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

cat > outputs.tf << 'EOF'
output "bucket-name" {
  description = "Bucket names."
  value       = module.gcs-static-website-bucket.bucket
}
EOF

cat > variables.tf << EOF
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

step "Task 2f: terraform init + apply (provision bucket)"

terraform init -input=false
terraform apply -auto-approve

step "Task 2g: Upload sample files ke bucket"

curl -sL https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/index.html > index.html
curl -sL https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/error.html > error.html
gsutil cp ./*.html "gs://$PROJECT_ID"

echo ">>> Files uploaded. Buka: https://storage.cloud.google.com/$PROJECT_ID/index.html"

step "Task 2h: Klik Check my progress dulu, lalu Enter untuk destroy"

echo "Klik 'Check my progress' untuk Task 2 (Upload files to the bucket),"
echo "setelah hijau tekan Enter untuk melanjutkan ke terraform destroy..."
read -r

step "Task 2h: Clean up — terraform destroy"

terraform destroy -auto-approve

echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Provision infrastructure"
echo "  Task 2 - Build a module"
echo "=============================================================="
