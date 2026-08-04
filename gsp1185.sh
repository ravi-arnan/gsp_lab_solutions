#!/usr/bin/env bash
# GSP1185 - Securing Container Builds
#
#   REGION=<region> bash gsp1185.sh
#
# Checkpoint:
#   1. Create a standard maven repository
#   2. Create a remote repository
#   3. Create a virtual repository
#
# Ketiganya cuma pembuatan repo Artifact Registry. Bagian pom.xml, `mvn deploy`,
# dan `mvn compile` di Task 2-4 TIDAK dinilai checkpoint mana pun, jadi tidak
# diotomasi — lihat catatan di akhir kalau mau mengerjakannya untuk belajar.
#
# LAMA: ~1 menit dari 10 menit jatah lab.

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

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"

STD_REPO="container-dev-java-repo"
REMOTE_REPO="maven-central-cache"
VIRTUAL_REPO="virtual-maven-repo"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Project: $PROJECT_ID"
echo "Region : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

repo_exists() {
  gcloud artifacts repositories describe "$1" \
    --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1
}

# ----------------------------------------------------------------- API
step "Enable Artifact Registry API"
gcloud services enable artifactregistry.googleapis.com --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 1
step "Task 1: Standard repository '$STD_REPO' (checkpoint 1)"
if repo_exists "$STD_REPO"; then
  echo "Sudah ada, dilewat."
else
  gcloud artifacts repositories create "$STD_REPO" \
    --project="$PROJECT_ID" \
    --repository-format=maven \
    --location="$REGION" \
    --description="Java package repository for Container Dev Workshop"
fi
gcloud artifacts repositories describe "$STD_REPO" --location="$REGION" --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 3
step "Task 3: Remote repository '$REMOTE_REPO' (checkpoint 2)"
if repo_exists "$REMOTE_REPO"; then
  echo "Sudah ada, dilewat."
else
  gcloud artifacts repositories create "$REMOTE_REPO" \
    --project="$PROJECT_ID" \
    --repository-format=maven \
    --location="$REGION" \
    --description="Remote repository for Maven Central caching" \
    --mode=remote-repository \
    --remote-repo-config-desc="Maven Central" \
    --remote-mvn-repo=MAVEN-CENTRAL
fi
gcloud artifacts repositories describe "$REMOTE_REPO" --location="$REGION" --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 4
step "Task 4: Virtual repository '$VIRTUAL_REPO' (checkpoint 3)"

# Upstream: repo privat diprioritaskan (100) di atas cache Maven Central (80).
cat > /tmp/gsp1185-policy.json << EOF
[
  {
    "id": "private",
    "repository": "projects/${PROJECT_ID}/locations/${REGION}/repositories/${STD_REPO}",
    "priority": 100
  },
  {
    "id": "central",
    "repository": "projects/${PROJECT_ID}/locations/${REGION}/repositories/${REMOTE_REPO}",
    "priority": 80
  }
]
EOF

if repo_exists "$VIRTUAL_REPO"; then
  echo "Sudah ada, dilewat."
else
  gcloud artifacts repositories create "$VIRTUAL_REPO" \
    --project="$PROJECT_ID" \
    --repository-format=maven \
    --mode=virtual-repository \
    --location="$REGION" \
    --description="Virtual Maven Repo" \
    --upstream-policy-file=/tmp/gsp1185-policy.json
fi
gcloud artifacts repositories describe "$VIRTUAL_REPO" --location="$REGION" --project="$PROJECT_ID"

# ----------------------------------------------------------------- setelan mvn
step "Setelan Maven untuk '$VIRTUAL_REPO' (untuk pom.xml, tidak dinilai)"
gcloud artifacts print-settings mvn \
  --repository="$VIRTUAL_REPO" \
  --location="$REGION" \
  --project="$PROJECT_ID"

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 3 checkpoint:
  1. Create a standard maven repository
  2. Create a remote repository
  3. Create a virtual repository

Sisa lab (pom.xml, mvn deploy, mvn compile) tidak punya checkpoint.
Kalau mau mengerjakannya untuk belajar:

  git clone https://github.com/GoogleCloudPlatform/java-docs-samples
  cd java-docs-samples/container-registry/container-analysis
  # tempel blok XML di atas ke pom.xml, tepat sebelum </project>
  mkdir -p .mvn && cat > .mvn/extensions.xml << 'XML'
  <extensions xmlns="http://maven.apache.org/EXTENSIONS/1.0.0">
    <extension>
      <groupId>com.google.cloud.artifactregistry</groupId>
      <artifactId>artifactregistry-maven-wagon</artifactId>
      <version>2.2.0</version>
    </extension>
  </extensions>
  XML
  mvn deploy -DskipTests     # unggah hello-world ke $STD_REPO
  rm -rf ~/.m2/repository && mvn compile   # tarik dependency lewat virtual repo
--------------------------------------------------------------
EOF
