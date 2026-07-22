#!/usr/bin/env bash
# GSP412 - Troubleshooting and Solving Data Join Pitfalls
# Jalankan di Cloud Shell: bash gsp412.sh
#
# Yang di-cover: Task 1, 4, 5, 6 (semua Check my progress).
# Task 2 (pin project), Task 3 (baca schema), dan semua soal pilihan ganda manual.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"

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

# ---------------------------------------------------------------- Task 4
q "Task 4: how many products and SKUs?" "
SELECT DISTINCT
  productSKU,
  v2ProductName
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
"

q "Task 4: distinct SKUs" "
SELECT DISTINCT
  productSKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
"

q "Task 4: products with multiple SKUs" "
SELECT
  v2ProductName,
  COUNT(DISTINCT productSKU) AS SKU_count,
  STRING_AGG(DISTINCT productSKU LIMIT 5) AS SKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
WHERE productSKU IS NOT NULL
GROUP BY v2ProductName
HAVING SKU_count > 1
ORDER BY SKU_count DESC
"

q "Task 4: SKUs with multiple product names" "
SELECT
  productSKU,
  COUNT(DISTINCT v2ProductName) AS product_count,
  STRING_AGG(DISTINCT v2ProductName LIMIT 5) AS product_name
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
WHERE v2ProductName IS NOT NULL
GROUP BY productSKU
HAVING product_count > 1
ORDER BY product_count DESC
"

# ---------------------------------------------------------------- Task 5
q "Task 5: product names for SKU GGOEGPJC019099" "
SELECT DISTINCT
  v2ProductName,
  productSKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
WHERE productSKU = 'GGOEGPJC019099'
"

q "Task 5: inventory for SKU GGOEGPJC019099" "
SELECT
  SKU,
  name,
  stockLevel
FROM \`data-to-insights.ecommerce.products\`
WHERE SKU = 'GGOEGPJC019099'
"

q "Task 5: join website + inventory (triple count demo)" "
SELECT DISTINCT
  website.v2ProductName,
  website.productSKU,
  inventory.stockLevel
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
WHERE productSKU = 'GGOEGPJC019099'
"

q "Task 5: SUM triple counting = 462" "
WITH inventory_per_sku AS (
  SELECT DISTINCT
    website.v2ProductName,
    website.productSKU,
    inventory.stockLevel
  FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
  JOIN \`data-to-insights.ecommerce.products\` AS inventory
    ON website.productSKU = inventory.SKU
  WHERE productSKU = 'GGOEGPJC019099'
)
SELECT
  productSKU,
  SUM(stockLevel) AS total_inventory
FROM inventory_per_sku
GROUP BY productSKU
"

# ---------------------------------------------------------------- Task 6
q "Task 6: ARRAY_AGG names for SKU GGOEGAAX0098" "
SELECT
  productSKU,
  ARRAY_AGG(DISTINCT v2ProductName) AS push_all_names_into_array
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
WHERE productSKU = 'GGOEGAAX0098'
GROUP BY productSKU
"

q "Task 6: INNER JOIN -> 1090 SKUs" "
SELECT DISTINCT
  website.productSKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
"

q "Task 6: LEFT JOIN -> 1909 SKUs" "
SELECT DISTINCT
  website.productSKU AS website_SKU,
  inventory.SKU AS inventory_SKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
LEFT JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
"

q "Task 6: NULL from LEFT JOIN -> 819 missing" "
SELECT DISTINCT
  website.productSKU AS website_SKU,
  inventory.SKU AS inventory_SKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
LEFT JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
WHERE inventory.SKU IS NULL
"

q "Task 6: RIGHT JOIN -> 2 missing from website" "
SELECT DISTINCT
  website.productSKU AS website_SKU,
  inventory.SKU AS inventory_SKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
RIGHT JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
WHERE website.productSKU IS NULL
"

q "Task 6: FULL JOIN -> 821 total missing" "
SELECT DISTINCT
  website.productSKU AS website_SKU,
  inventory.SKU AS inventory_SKU
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
FULL JOIN \`data-to-insights.ecommerce.products\` AS inventory
  ON website.productSKU = inventory.SKU
WHERE website.productSKU IS NULL OR inventory.SKU IS NULL
"

# ---------------------------------------------------------------- CROSS JOIN demo
q "Task 6: buat tabel site_wide_promotion" "
CREATE OR REPLACE TABLE ecommerce.site_wide_promotion AS
SELECT .05 AS discount
"

q "Task 6: CROSS JOIN clearance (1 discount) -> 82" "
SELECT DISTINCT
  productSKU,
  v2ProductCategory,
  discount
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
CROSS JOIN ecommerce.site_wide_promotion
WHERE v2ProductCategory LIKE '%Clearance%'
"

q "Task 6: INSERT 2 discount lagi" "
INSERT INTO ecommerce.site_wide_promotion (discount)
VALUES (.04),
       (.03)
"

q "Task 6: SELECT discount (harus 3 baris)" "
SELECT discount FROM ecommerce.site_wide_promotion
"

q "Task 6: CROSS JOIN clearance (3 discounts) -> 246" "
SELECT DISTINCT
  productSKU,
  v2ProductCategory,
  discount
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
CROSS JOIN ecommerce.site_wide_promotion
WHERE v2ProductCategory LIKE '%Clearance%'
"

q "Task 6: CROSS JOIN 1 produk (GGOEGOLC013299) -> 3 baris" "
SELECT DISTINCT
  productSKU,
  v2ProductCategory,
  discount
FROM \`data-to-insights.ecommerce.all_sessions_raw\` AS website
CROSS JOIN ecommerce.site_wide_promotion
WHERE v2ProductCategory LIKE '%Clearance%'
AND productSKU = 'GGOEGOLC013299'
"

q "Task 6: confirm SKU GGOEGATJ060517 tidak ada di inventory" "
SELECT * FROM \`data-to-insights.ecommerce.products\`
WHERE SKU = 'GGOEGATJ060517'
"

echo
echo "Selesai. Sisa yang manual: Task 2 (pin project), Task 3 (baca schema), semua soal pilihan ganda."
