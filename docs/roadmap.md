# Urutan pengerjaan 51 skill badge yang tersisa

Disusun 2026-08-22. Dasar pengurutan dua hal, keduanya bisa dicek dari repo:

1. **Berapa lab badge itu yang scriptnya sudah ada di sini.** Badge yang tinggal
   satu-dua lab jauh lebih murah daripada badge nol.
2. **Checkpoint-nya membaca apa.** Lab yang dinilai dari jejak API/resource bisa
   diotomasi; lab yang dinilai dari artefak UI (Looker IDE, Apps Script editor,
   Connected Sheets, Vertex AI Studio) tidak. Buktinya `gsp1154.sh`: jalan
   tuntas, semua API call sukses, **0/5**.

> **Pemetaan badge → lab di bawah adalah petunjuk, bukan fakta.** Syllabus resmi
> butuh login dan tidak bisa dienumerasi dari luar; sebagian nama badge juga
> sudah berganti (Dataplex → Knowledge Catalog, Vertex AI → Agent Platform).
> **Langkah pertama tiap badge: buka syllabus-nya, cocokkan kode GSP dengan
> `ls *.sh`.** Baru putuskan menulis script atau tidak.

---

## Tier 1 — repo sudah memegang sebagian besar labnya (kerjakan duluan)

Urutan di dalam tier ini dari yang paling sedikit sisa pekerjaannya.

| # | Badge | Yang sudah ada | Sisa |
|---|-------|----------------|------|
| 1 | Enrich Metadata and Discovery of Lakehouse Data | `gsp1143` `gsp1144` `gsp1145` `arc117` | kemungkinan besar sudah lengkap — tinggal jalankan dan verifikasi |
| 2 | Monitor and Manage Google Cloud Resources | `gsp089` `gsp092` `gsp1108` `arc115` | verifikasi; irisan besar dengan #3 |
| 3 | Monitor and Log with Google Cloud Observability | `gsp089` `gsp1026` `gsp1108` `gsp364` `arc115` | kerjakan berbarengan dengan #2, labnya banyak yang sama |
| 4 | Secure Lakehouse Data | `gsp1143` `gsp1145` `gsp1157` `gsp1158` `gsp514` | **`gsp1158` mentok 60/100 lewat script** — sisanya selesaikan manual |
| 5 | Implement DevOps Workflows in Google Cloud | `gsp053` `gsp1077` `gsp330` | satu lab (kemungkinan GSP121) |
| 6 | Configure Service Accounts and IAM Roles for Google Cloud | `gsp190` `gsp647` `gsp526` | satu lab service-account fundamentals |
| 7 | Mitigate Threats and Vulnerabilities with Security Command Center | `gsp1124` `gsp1164` | dua lab + challenge |
| 8 | Kickstarting Application Development with Gemini Code Assist | `gsp527` (challenge) | lab pengantarnya; Code Assist banyak UI, cek dulu |
| 9 | Set Up an App Dev Environment on Google Cloud | `gsp073` `gsp081` `gsp089` | IAM qwik start + challenge |
| 10 | Build Event-Driven Applications with Eventarc | `gsp095` `gsp1089` | dua lab Eventarc + challenge |

## Tier 2 — nol script, tapi murni CLI/SQL (paling produktif setelah Tier 1)

Semua di tier ini dinilai dari resource atau baris tabel, bukan tampilan. Pola
`gsp523` (deteksi dataset bawaan lab, jangan tanya) langsung terpakai untuk
kelompok BigQuery.

| # | Badge | Kenapa cocok |
|---|-------|--------------|
| 11 | Create ML Models with BigQuery ML | SQL murni, `bq query` saja |
| 12 | Perform Predictive Data Analysis in BigQuery | idem |
| 13 | Engineer Data for Predictive Modeling with BigQuery ML | idem |
| 14 | Derive Insights from BigQuery Data | idem, repo sudah kuat di BigQuery |
| 15 | Streaming Analytics into BigQuery | `gsp903` dan `arc110` mungkin masuk hitungan |
| 16 | Create and Manage Bigtable Instances | `cbt`/`gcloud bigtable`, deterministik |
| 17 | Create and Manage Cloud SQL for PostgreSQL Instances | `gcloud sql`; pengalaman `gsp351` terpakai |
| 18 | Deploy Kubernetes Applications on Google Cloud | `kubectl`; repo punya 4 lab GKE yang sudah jalan |
| 19 | Implementing Cloud Load Balancing for Compute Engine | `gcloud compute` murni |
| 20 | Build Global and Regional Load Balancing Solutions | idem, banyak lab yang sama dengan #19 |
| 21 | Set Up a Google Cloud Network | `gcloud compute networks`; `gsp647` sudah ada |
| 22 | Develop Your Google Cloud Network | `gsp089` `gsp053` sudah ada |
| 23 | Build a Secure Google Cloud Network | firewall/VPC, semua CLI |
| 24 | Implement Cloud Security Fundamentals on Google Cloud | IAM + VPC + logging |
| 25 | Create a Secure Data Lake on Cloud Storage | `gsp073` `gsp074` `gsp297` `arc111` kemungkinan masuk |
| 26 | Implement Sensitive Data Protection on Google Cloud | beda badge dari `gsp1281`/`gsp1282`, tapi API-nya sama |
| 27 | Analyze Images with the Cloud Vision API | Vision API dari CLI/Python, pola `gsp329` terpakai |
| 28 | Prepare Data for ML APIs on Google Cloud | idem |
| 29 | Cloud Architecture: Design, Implement, and Manage | GCE/LB/autoscaling, semua CLI |
| 30 | Build Google Cloud Infrastructure for AWS Professionals | dasar GCE/VPC, labnya banyak tapi mudah |
| 31 | Automate Data Capture at Scale with Document AI | Document AI API + Python |
| 32 | Develop Serverless Apps with Firebase | sebagian console; cek per lab |
| 33 | Deploy and Manage Apigee X | provisioning Apigee 30-40 menit, lambat tapi bisa CLI |
| 34 | Develop and Secure APIs with Apigee X | idem, kerjakan setelah #33 |
| 35 | Protect Cloud Traffic with Chrome Enterprise Premium Security | console-berat, prioritas terakhir di tier ini |

## Tier 3 — notebook / sebagian UI, script cuma menutup sebagian

Kerjakan manual sambil pakai script untuk bagian setup (enable API, buat bucket,
upload data). Jangan berharap 100% dari script saja.

| # | Badge |
|---|-------|
| 36 | Build Real World AI Applications with Gemini and Imagen |
| 37 | Inspect Rich Documents with Gemini Multimodality and Multimodal RAG |
| 38 | Analyze and Reason on Multimodal Data with Gemini |
| 39 | Develop Gen AI Apps with Gemini and Streamlit |
| 40 | Enhance Gemini Model Capabilities |
| 41 | Google DeepMind: Train A Small Language Model |
| 42 | Build a Smart Cloud Application with Vibe Coding and MCP |

## Tier 4 — kerjakan manual, jangan tulis script

Checkpoint-nya membaca artefak UI. Menulis script di sini membuang waktu lab —
persis kasus `gsp1154`.

| # | Badge | Kenapa |
|---|-------|--------|
| 43 | Explore Generative AI in Agent Platform | Vertex/Agent Studio, terbukti 0/5 di `gsp1154` |
| 44 | Prompt Design in Agent Platform | idem |
| 45 | Build LookML Objects in Looker | Looker IDE |
| 46 | Manage Data Models in Looker | Looker IDE |
| 47 | Prepare Data for Looker Dashboards and Reports | Looker IDE |
| 48 | Analyze BigQuery Data in Connected Sheets | Google Sheets |
| 49 | Integrate BigQuery Data and Google Workspace using Apps Script | Apps Script editor |
| 50 | Implement Cloud Collaboration and Productivity Workflows | Workspace admin UI |

## Terhalang

| # | Badge | Masalah |
|---|-------|---------|
| 51 | Analyze Speech and Language with Google APIs | Challenge-nya **ARC114**, checkpoint Task 4 rusak — maks 75/100 setelah 15 hipotesis dan 4 instance. Detail di [arc114.md](arc114.md). Coba lagi hanya kalau lab-nya di-update. |

---

## Cara mengerjakan satu badge

1. Buka syllabus badge, salin daftar labnya.
2. `ls *.sh` — tandai yang sudah ada. Jalankan itu dulu, gratis.
3. Untuk lab yang belum ada: **tempel teks task-nya**, jangan hanya judulnya.
   Script dari judul saja menghasilkan tebakan yang kelihatan benar tapi nol poin.
4. Lab dengan langkah "undo" (hapus, cabut akses, promote) dipisah ke fase kedua
   — lihat pola di [AGENTS.md](../AGENTS.md) dan `gsp328`.
5. Setelah 100/100: tandai ✅ di [coverage.md](coverage.md), catat temuan lintas-lab
   di [HANDOFF.md](../HANDOFF.md).
