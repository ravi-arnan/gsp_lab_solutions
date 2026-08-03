#!/usr/bin/env bash
# GSP1050 - Spanner - Defining Schemas and Understanding Query Plans
#
#   bash gsp1050.sh
#
# Checkpoint:
#   Task 1 - Load Data into Portfolio, Category, and Product Tables
#   Task 2 - Load Data into Campaigns Table
#   Task 4 - Add column to Category table
#   Task 5 - Add secondary index to Category table
#
# Instance banking-ops-instance, database banking-ops-db, dan keempat tabelnya
# sudah dibuat lab. Task 6 cuma membaca query plan di Console, tidak di-score —
# script tetap menjalankan ketiga query-nya supaya hasilnya kelihatan.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

INSTANCE="banking-ops-instance"
DATABASE="banking-ops-db"

# Client library Spanner mencoba mengirim metrik internal ke Cloud Monitoring dan
# selalu ditolak 400. Tidak berpengaruh ke hasil, cuma membanjiri output.
export SPANNER_DISABLE_BUILTIN_METRICS=true

echo "Project : $PROJECT"
echo "Spanner : $INSTANCE / $DATABASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Insert ulang bikin ALREADY_EXISTS — bukan error fatal, cuma tanda sudah pernah jalan.
sql() { gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" --sql="$1"; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Isi tabel Portfolio, Category, Product"
sql "INSERT INTO Portfolio (PortfolioId, Name, ShortName, PortfolioInfo)
VALUES
  (1, 'Banking', 'Bnkg', 'All Banking Business'),
  (2, 'Asset Growth', 'AsstGrwth', 'All Asset Focused Products'),
  (3, 'Insurance', 'Ins', 'All Insurance Focused Products')" || echo "  (Portfolio sudah terisi, lanjut)"

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

# ----------------------------------------------------------------- Task 2
step "Task 2: Siapkan snippets.py lalu isi tabel Campaigns"
mkdir -p ~/python-helper
cd ~/python-helper
wget -q -N https://storage.googleapis.com/cloud-training/OCBL373/requirements.txt
wget -q -N https://storage.googleapis.com/cloud-training/OCBL373/snippets.py

# Cloud Shell pakai Python yang dikelola sistem; pip menolak install global tanpa
# flag ini di rilis yang lebih baru (PEP 668).
pip install -q -r requirements.txt 2>/dev/null ||
  pip install -q --break-system-packages -r requirements.txt
pip install -q setuptools 2>/dev/null || pip install -q --break-system-packages setuptools

# Lab menulis 'python'; Cloud Shell hanya punya python3.
snippet() { python3 snippets.py "$INSTANCE" --database-id "$DATABASE" "$1"; }

snippet insert_data || echo "  (Campaigns sudah terisi, lanjut)"

# ----------------------------------------------------------------- Task 3
step "Task 3: Query tabel Campaigns"
snippet query_data

# ----------------------------------------------------------------- Task 4
step "Task 4: Tambah kolom MarketingBudget ke Category"
snippet add_column || echo "  (kolom sudah ada, lanjut)"
snippet update_data
snippet query_data_with_new_column

# ----------------------------------------------------------------- Task 5
step "Task 5: Tambah secondary index"
snippet add_index || echo "  (CategoryByCategoryName sudah ada, lanjut)"
snippet read_data_with_index
snippet add_storing_index || echo "  (CategoryByCategoryName2 sudah ada, lanjut)"
snippet read_data_with_storing_index

# ----------------------------------------------------------------- Task 6
step "Task 6: Query plan (tidak di-score, plan visualnya cuma ada di Console)"
sql "SELECT Name, ShortName, CategoryName
FROM Portfolio
INNER JOIN Category
ON Portfolio.PortfolioId = Category.PortfolioId"

sql "SELECT pr.ProductId, COUNT(*) AS ProductCount
FROM Product AS pr
WHERE pr.ProductId < 100
GROUP BY pr.ProductId"

sql "SELECT c.CategoryName, pr.ProductName
FROM Category AS c, Product AS pr
WHERE c.PortfolioId = pr.PortfolioId
  AND c.CategoryId = pr.CategoryId"

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1 - Load Data into Portfolio, Category, and Product Tables"
echo "  Task 2 - Load Data into Campaigns Table"
echo "  Task 4 - Add column to Category table"
echo "  Task 5 - Add secondary index to Category table"
echo
echo "Task 6 tidak punya checkpoint. Kalau mau melihat plan-nya, buka Spanner Studio"
echo "di Console, jalankan ketiga query di atas, lalu klik tab Explanation."
