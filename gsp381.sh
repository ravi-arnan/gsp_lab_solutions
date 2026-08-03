#!/usr/bin/env bash
# GSP381 - Create and Manage Cloud Spanner Instances: Challenge Lab
#
#   bash gsp381.sh
#
# Checkpoint:
#   Task 1 - Create an instance          (banking-ops-instance, us-east1, 1 node)
#   Task 2 - Create a database           (banking-ops-db)
#   Task 3+4 - Create and Load Tables    (Portfolio, Category, Product, Customer)
#   Task 5 - Load Customer table         (500 baris dari CSV publik)
#   Task 6 - Add Column                  (Category.MarketingBudget INT64)

set -euo pipefail

REGION="${REGION:-us-east1}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

INSTANCE="banking-ops-instance"
DATABASE="banking-ops-db"
CSV_URL="https://storage.googleapis.com/spls/gsp381/Customer_List_500.csv"

export SPANNER_DISABLE_BUILTIN_METRICS=true

echo "Project : $PROJECT"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }
sql() { gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" --sql="$1"; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Instance $INSTANCE"
# Provisioning lab baru saja mengaktifkan banyak API; enable lagi sering kena
# 429 "Mutate requests per minute" di serviceusage. Cek dulu, dan kalaupun
# gagal jangan hentikan script — Spanner API praktis selalu sudah aktif.
if gcloud services list --enabled --project="$PROJECT" \
     --filter='config.name:spanner.googleapis.com' --format='value(config.name)' | grep -q spanner; then
  echo "Spanner API sudah aktif."
else
  gcloud services enable spanner.googleapis.com --project="$PROJECT" ||
    echo "  (enable gagal, lanjut — cek manual kalau task berikutnya error)"
fi
if gcloud spanner instances describe "$INSTANCE" --project="$PROJECT" &>/dev/null; then
  echo "Instance sudah ada, lewati."
else
  gcloud spanner instances create "$INSTANCE" \
    --config="regional-$REGION" --description="Banking Ops Instance" \
    --nodes=1 --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: Database $DATABASE"
if gcloud spanner databases describe "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" &>/dev/null; then
  echo "Database sudah ada, lewati."
else
  gcloud spanner databases create "$DATABASE" --instance="$INSTANCE" --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat empat tabel"
# --ddl bisa diberikan berkali-kali; semuanya masuk dalam satu operasi DDL.
gcloud spanner databases ddl update "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" \
  --ddl='CREATE TABLE Portfolio (
    PortfolioId INT64 NOT NULL,
    Name STRING(MAX),
    ShortName STRING(MAX),
    PortfolioInfo STRING(MAX),
  ) PRIMARY KEY (PortfolioId)' \
  --ddl='CREATE TABLE Category (
    CategoryId INT64 NOT NULL,
    PortfolioId INT64 NOT NULL,
    CategoryName STRING(MAX),
    PortfolioInfo STRING(MAX),
  ) PRIMARY KEY (CategoryId)' \
  --ddl='CREATE TABLE Product (
    ProductId INT64 NOT NULL,
    CategoryId INT64 NOT NULL,
    PortfolioId INT64 NOT NULL,
    ProductName STRING(MAX),
    ProductAssetCode STRING(25),
    ProductClass STRING(25),
  ) PRIMARY KEY (ProductId)' \
  --ddl='CREATE TABLE Customer (
    CustomerId STRING(36) NOT NULL,
    Name STRING(MAX) NOT NULL,
    Location STRING(MAX) NOT NULL,
  ) PRIMARY KEY (CustomerId)' \
  || echo "  (tabel sudah ada, lanjut)"

# ----------------------------------------------------------------- Task 4
step "Task 4: Isi Portfolio, Category, Product"
sql "INSERT INTO Portfolio (PortfolioId, Name, ShortName, PortfolioInfo)
VALUES
  (1, 'Banking', 'Bnkg', 'All Banking Business'),
  (2, 'Asset Growth', 'AsstGrwth', 'All Asset Focused Products'),
  (3, 'Insurance', 'Insurance', 'All Insurance Focused Products')" || echo "  (Portfolio sudah terisi, lanjut)"

sql "INSERT INTO Category (CategoryId, PortfolioId, CategoryName)
VALUES
  (1, 1, 'Cash'),
  (2, 2, 'Investments - Short Return'),
  (3, 2, 'Annuities'),
  (4, 3, 'Life Insurance')" || echo "  (Category sudah terisi, lanjut)"

sql "INSERT INTO Product (ProductId, CategoryId, PortfolioId, ProductName, ProductAssetCode, ProductClass)
VALUES
  (1, 1, 1, 'Checking Account', 'ChkAcct', 'Banking LOB'),
  (2, 2, 2, 'Mutual Fund Consumer Goods', 'MFundCG', 'Investment LOB'),
  (3, 3, 2, 'Annuity Early Retirement', 'AnnuFixed', 'Investment LOB'),
  (4, 4, 3, 'Term Life Insurance', 'TermLife', 'Insurance LOB'),
  (5, 1, 1, 'Savings Account', 'SavAcct', 'Banking LOB'),
  (6, 1, 1, 'Personal Loan', 'PersLn', 'Banking LOB'),
  (7, 1, 1, 'Auto Loan', 'AutLn', 'Banking LOB'),
  (8, 4, 3, 'Permanent Life Insurance', 'PermLife', 'Insurance LOB'),
  (9, 2, 2, 'US Savings Bonds', 'USSavBond', 'Investment LOB')" || echo "  (Product sudah terisi, lanjut)"

# ----------------------------------------------------------------- Task 5
step "Task 5: Isi Customer dari CSV (500 baris)"
# Dataflow butuh 12-16 menit untuk 500 baris — tidak sepadan. Batch mutation
# client library selesai dalam hitungan detik (500 baris x 3 kolom = 1500
# mutation, jauh di bawah batas 20.000 per commit).
python3 -c 'import google.cloud.spanner' 2>/dev/null ||
  pip3 install -q google-cloud-spanner 2>/dev/null ||
  pip3 install -q --break-system-packages google-cloud-spanner

curl -sf -o Customer_List_500.csv "$CSV_URL"

python3 - <<'PY'
import csv, sys
from google.cloud import spanner

client = spanner.Client()
database = client.instance("banking-ops-instance").database("banking-ops-db")

with open("Customer_List_500.csv") as f:
    rows = [tuple(r) for r in csv.reader(f) if r]

# insert_or_update, bukan insert: script boleh diulang tanpa kena ALREADY_EXISTS.
with database.batch() as batch:
    batch.insert_or_update(
        table="Customer",
        columns=("CustomerId", "Name", "Location"),
        values=rows,
    )
print(f"{len(rows)} baris Customer dimuat.")
PY

sql 'SELECT COUNT(*) FROM Customer'

# ----------------------------------------------------------------- Task 6
step "Task 6: Tambah kolom Category.MarketingBudget"
gcloud spanner databases ddl update "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" \
  --ddl='ALTER TABLE Category ADD COLUMN MarketingBudget INT64' \
  || echo "  (kolom sudah ada, lanjut)"

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Create an instance"
echo "  Task 2 - Create a database"
echo "  Task 3+4 - Create and Load Tables"
echo "  Task 5 - Load Customer table"
echo "  Task 6 - Add Column"
