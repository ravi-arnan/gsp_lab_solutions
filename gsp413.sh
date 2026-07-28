#!/usr/bin/env bash
# GSP413 - Creating a Data Warehouse Through Joins and Unions
#
#   bash gsp413.sh
#
# Checkpoint (keempat task di-score):
#   Task 1  Create a new dataset to store the tables
#   Task 2  Explore the product sentiment dataset
#   Task 3  Join datasets to find insights
#   Task 4  Append additional records
#
# Semua soal pilihan ganda tetap harus diklik manual, termasuk bagian
# Cloud Natural Language demo yang tidak punya checkpoint sama sekali.
# Lihat docs/gsp413.md untuk kunci jawabannya.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"   # data-to-insights ada di US, BigQuery menolak join lintas-location

[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
echo "Project: $PROJECT"

q() { # q "<judul>" "<sql>"
  echo
  echo "=============================================================="
  echo ">> $1"
  echo "=============================================================="
  bq --project_id="$PROJECT" --location="$LOCATION" query \
     --use_legacy_sql=false --format=pretty "$2"
}

# ---------------------------------------------------------------- Task 1
echo ">> Task 1: buat dataset ecommerce"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d ecommerce

# ---------------------------------------------------------------- Task 2
# Salinan tabel products ini satu-satunya perubahan state di Task 2, jadi
# inilah yang dicari checkpoint. Beberapa script komunitas melewatinya dan
# Task 2-nya tidak pernah hijau.
q "Task 2a: salin products ke dataset sendiri" "
CREATE OR REPLACE TABLE \`$PROJECT.ecommerce.products\` AS
SELECT * FROM \`data-to-insights.ecommerce.products\`
"

q "Task 2b: 5 produk sentimen tertinggi" "
SELECT SKU, name, sentimentScore, sentimentMagnitude
FROM \`data-to-insights.ecommerce.products\`
ORDER BY sentimentScore DESC
LIMIT 5
"

q "Task 2c: 5 produk sentimen terendah (NULL dibuang)" "
SELECT SKU, name, sentimentScore, sentimentMagnitude
FROM \`data-to-insights.ecommerce.products\`
WHERE sentimentScore IS NOT NULL
ORDER BY sentimentScore
LIMIT 5
"

# ---------------------------------------------------------------- Task 3
q "Task 3a: sales_by_sku_20170801 (harusnya 462 SKU)" "
CREATE OR REPLACE TABLE \`$PROJECT.ecommerce.sales_by_sku_20170801\` AS
SELECT
  productSKU,
  SUM(IFNULL(productQuantity,0)) AS total_ordered
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
WHERE date = '20170801'
GROUP BY productSKU
ORDER BY total_ordered DESC
"

q "Task 3b: join ke inventory untuk dapat nama produk" "
SELECT DISTINCT
  website.productSKU,
  website.total_ordered,
  inventory.name,
  inventory.stockLevel,
  inventory.restockingLeadTime,
  inventory.sentimentScore,
  inventory.sentimentMagnitude
FROM \`$PROJECT.ecommerce.sales_by_sku_20170801\` AS website
LEFT JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
ORDER BY total_ordered DESC
"

q "Task 3c: produk yang stoknya termakan >= 50%" "
SELECT DISTINCT
  website.productSKU,
  website.total_ordered,
  inventory.name,
  inventory.stockLevel,
  inventory.restockingLeadTime,
  inventory.sentimentScore,
  inventory.sentimentMagnitude,
  SAFE_DIVIDE(website.total_ordered, inventory.stockLevel) AS ratio
FROM \`$PROJECT.ecommerce.sales_by_sku_20170801\` AS website
LEFT JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
WHERE SAFE_DIVIDE(website.total_ordered, inventory.stockLevel) >= .50
ORDER BY total_ordered DESC
"

# ---------------------------------------------------------------- Task 4
q "Task 4a: tabel kosong sales_by_sku_20170802" "
CREATE OR REPLACE TABLE \`$PROJECT.ecommerce.sales_by_sku_20170802\`
(
  productSKU STRING,
  total_ordered INT64
)
"

q "Task 4b: insert satu baris" "
INSERT INTO \`$PROJECT.ecommerce.sales_by_sku_20170802\`
  (productSKU, total_ordered)
VALUES('GGOEGHPA002910', 101)
"

q "Task 4c: UNION ALL dua tabel harian" "
SELECT * FROM \`$PROJECT.ecommerce.sales_by_sku_20170801\`
UNION ALL
SELECT * FROM \`$PROJECT.ecommerce.sales_by_sku_20170802\`
"

# Wildcard wajib fully-qualified di sini. `ecommerce.sales_by_sku_2017*` hanya
# resolve kalau ada default dataset, dan `bq query` tidak punya itu.
q "Task 4d: wildcard sales_by_sku_2017*" "
SELECT * FROM \`$PROJECT.ecommerce.sales_by_sku_2017*\`
"

q "Task 4e: wildcard difilter _TABLE_SUFFIX = '0802'" "
SELECT * FROM \`$PROJECT.ecommerce.sales_by_sku_2017*\`
WHERE _TABLE_SUFFIX = '0802'
"

echo
echo "=============================================================="
echo ">> Selesai. Klik Check my progress untuk Task 1-4."
echo "   Soal pilihan ganda jawab manual, kunci ada di docs/gsp413.md."
echo "=============================================================="
