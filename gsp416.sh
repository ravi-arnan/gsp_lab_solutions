#!/usr/bin/env bash
# GSP416 - Working with JSON, Arrays, and Structs in BigQuery
# Jalankan di Cloud Shell: bash gsp416.sh
#
# Yang di-cover: Task 1, 2, 3, 4, 6, 7, 8, 9 (semua Check my progress).
# Task 5 cuma baca schema di UI, dan semua soal pilihan ganda tetap harus diklik manual.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"   # public dataset (data-to-insights, bigquery-public-data) ada di US, harus sama
BUCKET="gs://spls/gsp416/data-insights-course/labs/optimizing-for-performance"

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
echo ">> Task 1: dataset fruit_store"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d fruit_store

# ---------------------------------------------------------------- Task 2
q "Task 2: array literal" "
SELECT ['raspberry','blackberry','strawberry','cherry'] AS fruit_array
"

# Sengaja dilewat: SELECT [... , 1234567] -> error 'no common supertype'.
# Itu memang demo error di lab, bukan sesuatu yang perlu sukses.

q "Task 2: tabel fruit_store" "
SELECT person, fruit_array, total_cost
FROM \`data-to-insights.advanced.fruit_store\`
"

echo ">> Task 2: load fruit_details (schema autodetect)"
bq --project_id="$PROJECT" --location="$LOCATION" load \
   --source_format=NEWLINE_DELIMITED_JSON --autodetect --replace \
   fruit_store.fruit_details "$BUCKET/shopping_cart.json"
bq --project_id="$PROJECT" show --schema --format=prettyjson fruit_store.fruit_details

# ---------------------------------------------------------------- Task 3
q "Task 3: sebelum ARRAY_AGG (harusnya 100 baris)" "
SELECT fullVisitorId, date, v2ProductName, pageTitle
FROM \`data-to-insights.ecommerce.all_sessions\`
WHERE visitId = 1501570398
ORDER BY date
"

q "Task 3: ARRAY_AGG (harusnya 2 baris)" "
SELECT
  fullVisitorId,
  date,
  ARRAY_AGG(v2ProductName) AS products_viewed,
  ARRAY_AGG(pageTitle) AS pages_viewed
FROM \`data-to-insights.ecommerce.all_sessions\`
WHERE visitId = 1501570398
GROUP BY fullVisitorId, date
ORDER BY date
"

q "Task 3: ARRAY_LENGTH" "
SELECT
  fullVisitorId,
  date,
  ARRAY_AGG(v2ProductName) AS products_viewed,
  ARRAY_LENGTH(ARRAY_AGG(v2ProductName)) AS num_products_viewed,
  ARRAY_AGG(pageTitle) AS pages_viewed,
  ARRAY_LENGTH(ARRAY_AGG(pageTitle)) AS num_pages_viewed
FROM \`data-to-insights.ecommerce.all_sessions\`
WHERE visitId = 1501570398
GROUP BY fullVisitorId, date
ORDER BY date
"

q "Task 3: DISTINCT (ini yang di-cek progress)" "
SELECT
  fullVisitorId,
  date,
  ARRAY_AGG(DISTINCT v2ProductName) AS products_viewed,
  ARRAY_LENGTH(ARRAY_AGG(DISTINCT v2ProductName)) AS distinct_products_viewed,
  ARRAY_AGG(DISTINCT pageTitle) AS pages_viewed,
  ARRAY_LENGTH(ARRAY_AGG(DISTINCT pageTitle)) AS distinct_pages_viewed
FROM \`data-to-insights.ecommerce.all_sessions\`
WHERE visitId = 1501570398
GROUP BY fullVisitorId, date
ORDER BY date
"

# ---------------------------------------------------------------- Task 4
q "Task 4: UNNEST(hits) (ini yang di-cek progress)" "
SELECT DISTINCT
  visitId,
  h.page.pageTitle
FROM \`bigquery-public-data.google_analytics_sample.ga_sessions_20170801\`,
UNNEST(hits) AS h
WHERE visitId = 1501570398
LIMIT 10
"

# ---------------------------------------------------------------- Task 5 / 6
q "Task 6: STRUCT + array literal" "
SELECT STRUCT('Rudisha' AS name, [23.4, 26.3, 26.4, 26.1] AS splits) AS runner
"

echo ">> Task 6: dataset racing + tabel race_results"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d racing

SCHEMA="$(mktemp --suffix=.json)"
trap 'rm -f "$SCHEMA"' EXIT
cat > "$SCHEMA" <<'EOF'
[
  { "name": "race", "type": "STRING", "mode": "NULLABLE" },
  { "name": "participants", "type": "RECORD", "mode": "REPEATED",
    "fields": [
      { "name": "name",   "type": "STRING", "mode": "NULLABLE" },
      { "name": "splits", "type": "FLOAT",  "mode": "REPEATED" }
    ]
  }
]
EOF

bq --project_id="$PROJECT" --location="$LOCATION" load \
   --source_format=NEWLINE_DELIMITED_JSON --replace \
   racing.race_results "$BUCKET/race_results.json" "$SCHEMA"
bq --project_id="$PROJECT" show --schema --format=prettyjson racing.race_results

q "Task 6: isi race_results (1 baris)" "
SELECT * FROM racing.race_results
"

q "Task 6: correlated cross join" "
SELECT race, participants.name
FROM racing.race_results AS r, r.participants
"

# ---------------------------------------------------------------- Task 7
q "Task 7: COUNT racer (harusnya 8)" "
SELECT COUNT(p.name) AS racer_count
FROM racing.race_results AS r, UNNEST(r.participants) AS p
"

# ---------------------------------------------------------------- Task 8
q "Task 8: total waktu racer huruf R (Rudisha 102.2, Rotich 103.6)" "
SELECT
  p.name,
  SUM(split_times) AS total_race_time
FROM racing.race_results AS r,
  UNNEST(r.participants) AS p,
  UNNEST(p.splits) AS split_times
WHERE p.name LIKE 'R%'
GROUP BY p.name
ORDER BY total_race_time ASC
"

# ---------------------------------------------------------------- Task 9
q "Task 9: siapa lap 23.2 (harusnya Kipketer)" "
SELECT
  p.name,
  split_time
FROM racing.race_results AS r,
  UNNEST(r.participants) AS p,
  UNNEST(p.splits) AS split_time
WHERE split_time = 23.2
"

echo
echo "Selesai. Sisa yang manual: semua soal pilihan ganda + Task 5 (star bigquery-public-data & baca schema)."
