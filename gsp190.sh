#!/usr/bin/env bash
# GSP190 - IAM Custom Roles
#
#   curl -sL https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp190.sh | bash
#
# Checkpoint:
#   Task 4 - Create a custom role using a YAML file   (role editor)
#   Task 4 - Create a custom role using flags         (role viewer)
#   Task 6 - Update a custom role using a YAML file   (editor + storage.buckets.*)
#   Task 6 - Update a custom role using flags         (viewer + storage.buckets.*)
#   Task 7 - Disabling a custom role                  (viewer stage DISABLED)
#   Task 9 - Undeleting a custom role                 (viewer di-undelete)
#
# Task 1, 2, 3, 5, dan 8 tidak punya checkpoint. Semua checkpoint bisa diklik
# sekaligus di akhir: undelete mengembalikan role dalam keadaan DISABLED, jadi
# checkpoint Task 7 tetap hijau setelah Task 9 dijalankan.

set -euo pipefail

step() { echo; echo "=== $* ==="; }

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
echo "PROJECT = $PROJECT"

gcloud config set compute/region us-east1 >/dev/null 2>&1
gcloud config set accessibility/screen_reader false >/dev/null 2>&1

RES="//cloudresourcemanager.googleapis.com/projects/$PROJECT"

# Role yang sudah dihapus tetap terbaca oleh describe dengan deleted: True.
role_exists()  { gcloud iam roles describe "$1" --project="$PROJECT" >/dev/null 2>&1; }
role_deleted() { [[ "$(gcloud iam roles describe "$1" --project="$PROJECT" --format='value(deleted)' 2>/dev/null)" == "True" ]]; }

# ------------------------------------------------------------- Task 1, 2, 3
# Ketiganya cuma baca. Output dipotong supaya tidak membanjiri terminal.
step "Task 1 - permission yang bisa dipakai di project (10 pertama)"
gcloud iam list-testable-permissions "$RES" --limit=10

step "Task 2 - metadata role (roles/iam.roleViewer)"
gcloud iam roles describe roles/iam.roleViewer

step "Task 3 - role yang grantable di project (10 pertama)"
gcloud iam list-grantable-roles "$RES" --limit=10

# ------------------------------------------------------------------- Task 4
step "Task 4a - buat custom role 'editor' lewat file YAML"
cat > role-definition.yaml <<'EOF'
title: "Role Editor"
description: "Edit access for App Versions"
stage: "ALPHA"
includedPermissions:
- appengine.versions.create
- appengine.versions.delete
EOF

if role_exists editor; then
  echo "role editor sudah ada, create dilewati"
else
  gcloud iam roles create editor --project="$PROJECT" --file role-definition.yaml -q
fi

step "Task 4b - buat custom role 'viewer' lewat flag"
if role_exists viewer; then
  echo "role viewer sudah ada, create dilewati"
  # Sisa run sebelumnya bisa meninggalkan viewer dalam keadaan terhapus.
  role_deleted viewer && gcloud iam roles undelete viewer --project="$PROJECT" -q || true
else
  gcloud iam roles create viewer --project="$PROJECT" \
    --title "Role Viewer" --description "Custom role description." \
    --permissions compute.instances.get,compute.instances.list --stage ALPHA -q
fi

# ------------------------------------------------------------------- Task 5
step "Task 5 - daftar custom role di project"
gcloud iam roles list --project="$PROJECT"

# ------------------------------------------------------------------- Task 6
step "Task 6a - update 'editor' lewat file YAML"
# etag harus ikut supaya update ditolak kalau role berubah di tengah jalan.
ETAG="$(gcloud iam roles describe editor --project="$PROJECT" --format='value(etag)')"
cat > new-role-definition.yaml <<EOF
description: Edit access for App Versions
etag: $ETAG
includedPermissions:
- appengine.versions.create
- appengine.versions.delete
- storage.buckets.get
- storage.buckets.list
name: projects/$PROJECT/roles/editor
stage: ALPHA
title: Role Editor
EOF
gcloud iam roles update editor --project="$PROJECT" --file new-role-definition.yaml -q

step "Task 6b - update 'viewer' lewat flag"
gcloud iam roles update viewer --project="$PROJECT" \
  --add-permissions storage.buckets.get,storage.buckets.list -q

# ------------------------------------------------------------------- Task 7
step "Task 7 - nonaktifkan role 'viewer'"
gcloud iam roles update viewer --project="$PROJECT" --stage DISABLED -q

# ---------------------------------------------------------------- Task 8, 9
step "Task 8 - hapus role 'viewer'"
if role_deleted viewer; then
  echo "role viewer sudah terhapus, delete dilewati"
else
  gcloud iam roles delete viewer --project="$PROJECT" -q
fi

step "Task 9 - pulihkan role 'viewer'"
gcloud iam roles undelete viewer --project="$PROJECT" -q

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi keenam checkpoint:
  - Create a custom role using a YAML file   (Task 4)
  - Create a custom role using flags         (Task 4)
  - Update a custom role using a YAML file   (Task 6)
  - Update a custom role using flags         (Task 6)
  - Disabling a custom role                  (Task 7)
  - Undeleting a custom role                 (Task 9)
EOF
