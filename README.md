# gsp_lab_solutions

Script otomatisasi untuk Google Cloud self-paced labs (Qwiklabs / Cloud Skills Boost), dijalankan dari Cloud Shell.

## Cara pakai

Jalankan langsung dari Cloud Shell:

```bash
curl -sL https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp416.sh | bash
```

Atau download dulu kalau mau baca isinya sebelum jalan (disarankan):

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp416.sh
less gsp416.sh
bash gsp416.sh
```

Kalau script baru saja diperbaiki dan kamu mengambilnya ulang di tengah lab, `raw.githubusercontent.com` masih menyajikan versi lama sekitar lima menit. **Query string `?v=$(date +%s)` tidak menolong** — cache-nya mengabaikan itu (terbukti 2026-08-03 di GSP381). Yang bekerja: ambil lewat commit SHA, karena URL-nya immutable.

```bash
git -C . log --oneline -1        # atau lihat SHA di GitHub
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/<SHA>/gsp416.sh
```

### Region, zone, dan nilai yang diacak per peserta

Script yang butuh region/zone (atau nilai lain yang berbeda tiap instance, seperti nama bucket di `arc111.sh` dan nama cluster di `gsp343.sh`) **akan bertanya sendiri** saat dijalankan dari terminal:

```
$ bash gsp081.sh
Region (cocokkan dengan panel lab) [asia-east1]: europe-west1
REGION = europe-west1
```

Tekan Enter saja kalau defaultnya sudah cocok. Tiga cara mengisinya, urutan prioritas dari atas:

| Cara | Kapan dipakai |
|------|---------------|
| `REGION=europe-west1 bash gsp081.sh` | env var menang, tidak ada pertanyaan — enak untuk mengulang script |
| Dijawab saat ditanya | jalan biasa dari terminal |
| Default di dalam script | dipakai otomatis kalau stdin bukan terminal |

Poin terakhir penting: `curl ... | bash` dan `nohup bash x.sh &` membuat stdin bukan terminal, jadi script **tidak akan menggantung menunggu jawaban** — dia langsung memakai default. Kalau region lab-mu berbeda dari default, isi lewat env var untuk dua pola itu.

### Script yang butuh fase atau parameter

Sebagian lab tidak bisa dijalankan sebagai one-liner. Download dulu, jangan di-pipe ke `bash`, karena `curl ... | bash -s <arg>` membuat script dan stdin berebut, dan biasanya filenya masih dibutuhkan untuk fase berikutnya.

`gsp1143.sh` contohnya. Task 4 menghapus semua yang dibuat Task 1 sampai 3, jadi harus dipisah dan **checkpoint task 1-3 wajib hijau dulu** sebelum fase delete:

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1143.sh
REGION=europe-west1 bash gsp1143.sh create   # Task 1-3
# klik Check my progress task 1, 2, 3 sampai hijau
REGION=europe-west1 bash gsp1143.sh delete   # Task 4
```

Region di lab ini diisi dinamis per instance, jadi cocokkan dengan halaman lab-mu. Default script `us-central1`.

## Daftar lab

| ID | Judul | Script | Runbook | Status | Terakhir diuji |
|----|-------|--------|---------|--------|----------------|
| GSP416 | Working with JSON, Arrays, and Structs in BigQuery | [gsp416.sh](gsp416.sh) | [docs/gsp416.md](docs/gsp416.md) | Terverifikasi, skor 100/100 | 2026-07-16 |
| GSP340 | Build a Data Warehouse with BigQuery: Challenge Lab | [gsp340.sh](gsp340.sh) | [docs/gsp340.md](docs/gsp340.md) | Terverifikasi, skor 40/40, satu varian task | 2026-07-16 |
| GSP1143 | Knowledge Catalog (Dataplex): Qwik Start - Console | [gsp1143.sh](gsp1143.sh) | [docs/gsp1143.md](docs/gsp1143.md) | Terverifikasi, skor 100/100 | 2026-07-17 |
| GSP1144 | Knowledge Catalog: Qwik Start - Command Line | [gsp1144.sh](gsp1144.sh) | [docs/gsp1144.md](docs/gsp1144.md) | Terverifikasi, skor 100/100, dua fase | 2026-08-06 |
| GSP1145 | Create and Add Aspects to Knowledge Catalog Assets | [gsp1145.sh](gsp1145.sh) | [docs/gsp1145.md](docs/gsp1145.md) | Terverifikasi, skor 100/100 (us-east1) | 2026-08-06 |
| GSP1157 | Implementing Security in Knowledge Catalog | [gsp1157.sh](gsp1157.sh) | [docs/gsp1157.md](docs/gsp1157.md) | Terverifikasi, skor 100/100, Task 3 dan 5 manual (dua user) | 2026-07-17 |
| GSP514 | Build a Data Mesh with Knowledge Catalog: Challenge Lab | [gsp514.sh](gsp514.sh) | [docs/gsp514.md](docs/gsp514.md) | Terverifikasi, Task 2b manual (UI) | 2026-07-17 |
| GSP750 | Infrastructure as Code with Terraform | [gsp750.sh](gsp750.sh) | [docs/gsp750.md](docs/gsp750.md) | Belum diuji | - |
| GSP751 | Interact with Terraform Modules | [gsp751.sh](gsp751.sh) | - | Belum diuji | - |
| GSP345 | Build Infrastructure with Terraform: Challenge Lab | [gsp345.sh](gsp345.sh) | - | Terverifikasi, semua checkpoint hijau (google provider dipin `< 7.0` di semua blok) | 2026-07-30 |
| GSP1183 | Gating Deployments with Binary Authorization | [gsp1183.sh](gsp1183.sh) | [docs/gsp1183.md](docs/gsp1183.md) | Terverifikasi di us-east1, 7/7 checkpoint hijau sekali jalan | 2026-07-17 |
| GSP1184 | Secure Builds with Cloud Build | [gsp1184.sh](gsp1184.sh) | - | Belum diuji | - |
| GSP1185 | Securing Container Builds | [gsp1185.sh](gsp1185.sh) | - | Belum diuji | - |
| GSP521 | Secure Software Delivery: Challenge Lab | [gsp521.sh](gsp521.sh) | - | Belum diuji | - |
| ARC125 | Use APIs to Work with Cloud Storage: Challenge Lab | [arc125.sh](arc125.sh) | - | Terverifikasi, semua checkpoint hijau, dua fase | 2026-07-30 |
| GSP294 | Introduction to APIs in Google Cloud | [gsp294.sh](gsp294.sh) | - | Belum diuji | - |
| GSP421 | APIs Explorer: Cloud Storage | [gsp421.sh](gsp421.sh) | [docs/gsp421.md](docs/gsp421.md) | Terverifikasi, skor 100/100 sekali jalan | 2026-08-21 |
| GSP038 | Entity and Sentiment Analysis with the Natural Language API | [gsp038.sh](gsp038.sh) | [docs/gsp038.md](docs/gsp038.md) | Terverifikasi, skor 100/100 sekali jalan; API key dibuat lewat console | 2026-08-04 |
| GSP074 | Cloud Storage: Qwik Start - CLI/SDK | [gsp074.sh](gsp074.sh) | [docs/gsp074.md](docs/gsp074.md) | Terverifikasi, skor 100/100 sekali jalan (us-east1) | 2026-08-21 |
| GSP073 | Cloud Storage: Qwik Start - Google Cloud Console | [gsp073.sh](gsp073.sh) | [docs/gsp073.md](docs/gsp073.md) | Terverifikasi, skor 100/100 sekali jalan (europe-west1) | 2026-08-21 |
| GSP522 | Discover and Protect Sensitive Data Across Your Ecosystem: Challenge Lab | [gsp522.sh](gsp522.sh) | - | Dikerjakan manual 100/100 (petunjuk Task 3 di script sudah dikoreksi ke SDK google-genai); script sendiri belum diuji | 2026-07-31 |
| GSP766 | Managing a GKE Multi-tenant Cluster with Namespaces | [gsp766.sh](gsp766.sh) | - | Terverifikasi, skor 100/100, Looker Studio manual (tidak di-score) | 2026-07-24 |
| GSP343 | Optimize Costs for GKE: Challenge Lab | [gsp343.sh](gsp343.sh) | - | Diuji, jalan tanpa error | 2026-07-24 |
| GSP767 | Exploring Cost-optimization for GKE Virtual Machines | [gsp767.sh](gsp767.sh) | - | Terverifikasi, skor 100/100 | 2026-07-24 |
| GSP414 | Creating Date-Partitioned Tables in BigQuery | [gsp414.sh](gsp414.sh) | - | Belum diuji | - |
| GSP1281 | Enabling Sensitive Data Protection Discovery for Cloud Storage | [gsp1281.sh](gsp1281.sh) | [docs/gsp1281.md](docs/gsp1281.md) | Belum diuji | - |
| GSP412 | Troubleshooting and Solving Data Join Pitfalls | [gsp412.sh](gsp412.sh) | - | Belum diuji | - |
| GSP081 | Cloud Run Functions: Qwik Start - Console | [gsp081.sh](gsp081.sh) | [docs/gsp081.md](docs/gsp081.md) | Terverifikasi, skor 100/100 | 2026-08-04 |
| GSP872 | API Gateway: Qwik Start | [gsp872.sh](gsp872.sh) | [docs/gsp872.md](docs/gsp872.md) | Terverifikasi, skor 100/100 | 2026-08-04 |
| GSP080 | Cloud Run Functions: Qwik Start - Command Line | [gsp080.sh](gsp080.sh) | - | Terverifikasi, skor 100/100 di dua region (us-west4 2026-07-31, us-east1 2026-08-21) | 2026-08-21 |
| GSP089 | Cloud Monitoring: Qwik Start | [gsp089.sh](gsp089.sh) | [docs/gsp089.md](docs/gsp089.md) | Terverifikasi, skor 100/100 sekali jalan | 2026-08-04 |
| GSP092 | Monitoring and Logging for Cloud Run Functions | [gsp092.sh](gsp092.sh) | [docs/gsp092.md](docs/gsp092.md) | Terverifikasi, skor 100/100; grader menuntut resource Cloud Functions v2, kebalikan GSP081 | 2026-08-04 |
| GSP1108 | Monitor an Apache Web Server using Ops Agent | [gsp1108.sh](gsp1108.sh) | [docs/gsp1108.md](docs/gsp1108.md) | Terverifikasi, skor 100/100 sekali jalan | 2026-08-04 |
| GSP736 | Debug Apps on Google Kubernetes Engine | [gsp736.sh](gsp736.sh) | [docs/gsp736.md](docs/gsp736.md) | Terverifikasi, skor 100/100; grader mencocokkan teks filter alerting policy (`resource.type` dulu) | 2026-08-04 |
| GSP1026 | Collect Metrics from Exporters using the Managed Service for Prometheus | [gsp1026.sh](gsp1026.sh) | - | Belum diuji | - |
| GSP053 | Managing Deployments Using Kubernetes Engine | [gsp053.sh](gsp053.sh) | - | Belum diuji | - |
| GSP1041 | Data Publishing on BigQuery using Authorized Views | [gsp1041.sh](gsp1041.sh) | [docs/gsp1041.md](docs/gsp1041.md) | Terverifikasi, skor 100/100; tiga project berbeda, wajib tiga fase (`partner`/`a`/`b`) | 2026-08-05 |
| GSP375 | Share Data using Google Data Cloud: Challenge Lab | [gsp375.sh](gsp375.sh) | [docs/gsp375.md](docs/gsp375.md) | Terverifikasi 100/100, tapi script maks 80/100 — visualisasi Looker Studio wajib manual | 2026-08-05 |
| GSP1043 | Consuming Customer Specific Datasets from Data Sharing Partners | [gsp1043.sh](gsp1043.sh) | [docs/gsp1043.md](docs/gsp1043.md) | Terverifikasi, skor 100/100; tiga project, empat fase (`partner`/`publisher`/`customer`/`insert`) | 2026-08-05 |
| GSP1042 | Analytics as a Service for Data Sharing Partners | [gsp1042.sh](gsp1042.sh) | [docs/gsp1042.md](docs/gsp1042.md) | Terverifikasi 100/100, tapi script maks 80/100 — dua dashboard Looker Studio wajib manual | 2026-08-05 |
| GSP510 | Manage Kubernetes in Google Cloud: Challenge Lab | [gsp510.sh](gsp510.sh) | [docs/gsp510.md](docs/gsp510.md) | Terverifikasi, skor 100/100 (dua perbaikan terakhir belum diuji ulang sekali jalan); nama diacak per instance | 2026-08-05 |
| GSP207 | Dataflow: Qwik Start - Python | [gsp207.sh](gsp207.sh) | [docs/gsp207.md](docs/gsp207.md) | Terverifikasi, skor 100/100 (asia-southeast1); jalannya lama, 10-15 menit | 2026-08-21 |
| GSP903 | Stream Processing with Cloud Pub/Sub and Dataflow: Qwik Start | [gsp903.sh](gsp903.sh) | [docs/gsp903.md](docs/gsp903.md) | Terverifikasi, skor 100/100 (us-central1), dua fase | 2026-08-21 |
| ARC110 | Create a Streaming Data Lake on Cloud Storage: Challenge Lab | [arc110.sh](arc110.sh) | - | Belum diuji; turunan gsp903.sh | - |
| GSP095 | Pub/Sub: Qwik Start - Command Line | [gsp095.sh](gsp095.sh) | - | Terverifikasi, skor 100/100 sekali jalan | 2026-08-21 |
| GSP1089 | Cloud Run Functions: Qwik Start | [gsp1089.sh](gsp1089.sh) | - | Terverifikasi, skor 100/100; min-instances dan concurrency wajib lewat `gcloud run services update` (CPU `1000m`) | 2026-07-31 |
| ARC104 | Build Serverless Applications with Cloud Run Functions: Challenge Lab | [arc104.sh](arc104.sh) | - | Terverifikasi, skor 100/100 sekali jalan | 2026-07-31 |
| GSP659 | Deploy Your Website on Cloud Run | [gsp659.sh](gsp659.sh) | [docs/gsp659.md](docs/gsp659.md) | Terverifikasi, skor 100/100 (us-west1), dua fase | 2026-08-21 |
| GSP156 | Terraform Fundamentals | [gsp156.sh](gsp156.sh) | [docs/gsp156.md](docs/gsp156.md) | Belum diuji | - |
| GSP413 | Creating a Data Warehouse Through Joins and Unions | [gsp413.sh](gsp413.sh) | [docs/gsp413.md](docs/gsp413.md) | Belum diuji | - |
| GSP1158 | Assessing Data Quality with Knowledge Catalog | [gsp1158.sh](gsp1158.sh) | [docs/gsp1158.md](docs/gsp1158.md) | Belum diuji, maks 60/100 (Task 2 & 5 wajib manual) | - |
| GSP1282 | Enabling Sensitive Data Protection Discovery for BigQuery | [gsp1282.sh](gsp1282.sh) | [docs/gsp1282.md](docs/gsp1282.md) | Manual 100/100; script 80/100 (Task 4 ditolak) — tag dataset kini lewat `bq update --add_tags`, belum diverifikasi | 2026-07-31 |
| GSP297 | Cloud Storage: Bucket Lock | [gsp297.sh](gsp297.sh) | [docs/gsp297.md](docs/gsp297.md) | Terverifikasi, skor 100/100, Task 6 (hapus bucket) sengaja manual | 2026-07-31 |
| GENAI129 | Deploy an Agent with ADK: Challenge Lab | [genai129.sh](genai129.sh) | [docs/genai129.md](docs/genai129.md) | Terverifikasi, skor 100/100, enam fase, Task 6 (chat di UI) manual | 2026-08-01 |
| GSP540 | Engineer AI Agents with ADK: Challenge Lab | [gsp540.sh](gsp540.sh) | [docs/gsp540.md](docs/gsp540.md) | Terverifikasi, skor 100/100 sekali jalan, Task 2 dan 5 (chat di Dev UI) manual | 2026-08-01 |
| GSP529 | Develop AI-Powered Prototypes in Google AI Studio: Challenge Lab | - | [docs/gsp529.md](docs/gsp529.md) | Tidak bisa di-script (100% UI AI Studio); runbook prompt terverifikasi 100/100, semua prompt jadi sekali jalan | 2026-08-02 |
| ARC120 | The Basics of Google Cloud Compute: Challenge Lab | [arc120.sh](arc120.sh) | - | Terverifikasi, skor 100/100 sekali jalan, tanpa SSH (NGINX lewat startup-script) | 2026-08-02 |
| ARC111 | Implement Cloud Storage and Data Protection Solutions: Challenge Lab | [arc111.sh](arc111.sh) | [docs/arc111.md](docs/arc111.md) | Terverifikasi 100/100 di dua varian: form-3 (2026-08-02) dan form-1 (2026-08-21); nama bucket diacak per instance, wajib diisi lewat `B1`/`B2`/`B3` plus `FORM` | 2026-08-21 |
| ARC100 | Store, Process, and Manage Data on Google Cloud: Challenge Lab | [arc100.sh](arc100.sh) | [docs/arc100.md](docs/arc100.md) | Terverifikasi, skor 100/100 (us-east1); nama topic diacak per instance, wajib diisi lewat `TOPIC` | 2026-08-21 |
| ARC109 | Deploy and Secure Serverless APIs with API Gateway: Challenge Lab | [arc109.sh](arc109.sh) | [docs/arc109.md](docs/arc109.md) | Terverifikasi, skor 100/100 sekali jalan | 2026-08-04 |
| ARC115 | Monitoring in Google Cloud: Challenge Lab | [arc115.sh](arc115.sh) | [docs/arc115.md](docs/arc115.md) | Terverifikasi, skor 100/100 sekali jalan | 2026-08-04 |
| ARC117 | Organize and Govern Data with Knowledge Catalog: Challenge Lab | [arc117.sh](arc117.sh) | [docs/arc117.md](docs/arc117.md) | Terverifikasi, skor 100/100; tempel aspect ke zone wajib lewat UI (zone tidak ada di `@dataplex`, sama seperti GSP514) | 2026-08-06 |
| ARC130 | Analyze Sentiment with Natural Language API: Challenge Lab | [arc130.sh](arc130.sh) | [docs/arc130.md](docs/arc130.md) | Terverifikasi, skor 100/100; Task 3-4 otomatis, Task 1-2 manual | 2026-08-04 |
| ARC132 | Implement Speech and Language Solutions with Pre-trained APIs: Challenge Lab | [arc132.sh](arc132.sh) | - | Terverifikasi, skor 100/100; Task 2-5 otomatis (scp + ssh ke `lab-vm`), Task 1 wajib bikin API key lewat console — key buatan gcloud tidak diterima grader | 2026-08-02 |
| ARC114 | Analyze Speech and Language with Google APIs: Challenge Lab | [arc114.sh](arc114.sh) | [docs/arc114.md](docs/arc114.md) | Maks 75/100 — Task 1-3 hijau; checkpoint Task 4 dianggap rusak (2 instance, 12 hipotesis gugur, analisisnya selalu sukses), lihat runbook sebelum mengulang | 2026-08-09 |
| ARC113 | Implement Event-Driven Messaging and Automation Workflows: Challenge Lab | [arc113.sh](arc113.sh) | [docs/arc113.md](docs/arc113.md) | Terverifikasi, skor 100/100 sekali jalan (varian schema + topic + Cloud Run function). Varian task lain (Scheduler, snapshot, Lite) belum ditulis | 2026-08-10 |
| GSP329 | Use Machine Learning APIs on Google Cloud: Challenge Lab | [gsp329.sh](gsp329.sh) | [docs/gsp329.md](docs/gsp329.md) | Terverifikasi, skor 100/100; semua task otomatis. Dua role dari instruksi lab tidak cukup — wajib `roles/serviceusage.serviceUsageConsumer` juga | 2026-08-10 |
| GSP364 | Monitor Environments with Managed Service for Prometheus: Challenge Lab | [gsp364.sh](gsp364.sh) | [docs/gsp364.md](docs/gsp364.md) | Terverifikasi, skor 100/100 sekali jalan; semua task otomatis, PodMonitoring ditambahkan sendiri (tidak ada di example-app.yaml) | 2026-08-10 |
| GSP395 | Create and Manage AlloyDB Instances: Challenge Lab | [gsp395.sh](gsp395.sh) | [docs/gsp395.md](docs/gsp395.md) | Terverifikasi, skor 100/100 (us-west1); SQL dijalankan lewat SSH ke VM `alloydb-client` (private IP tidak terjangkau Cloud Shell) | 2026-08-10 |
| GSP1048 | Cloud Spanner - Database Fundamentals | [gsp1048.sh](gsp1048.sh) | [docs/gsp1048.md](docs/gsp1048.md) | Terverifikasi, skor 100/100 | 2026-08-03 |
| GSP1049 | Cloud Spanner - Loading Data and Performing Backups | [gsp1049.sh](gsp1049.sh) | [docs/gsp1049.md](docs/gsp1049.md) | Terverifikasi, skor 100/100; ada jeda klik checkpoint sebelum tahap Dataflow | 2026-08-03 |
| GSP1050 | Spanner - Defining Schemas and Understanding Query Plans | [gsp1050.sh](gsp1050.sh) | [docs/gsp1050.md](docs/gsp1050.md) | Terverifikasi, skor 100/100 | 2026-08-03 |
| GSP381 | Create and Manage Cloud Spanner Instances: Challenge Lab | [gsp381.sh](gsp381.sh) | [docs/gsp381.md](docs/gsp381.md) | Terverifikasi, skor 100/100 | 2026-08-03 |
| GSP752 | Manage Terraform State | [gsp752.sh](gsp752.sh) | - | Belum diuji | - |
| GSP1124 | Get Started with Security Command Center | [gsp1124.sh](gsp1124.sh) | - | Belum diuji; Task 1-2 wajib manual (UI + enable SHA module) | - |
| GSP1164 | Analyze Findings with Security Command Center | [gsp1164.sh](gsp1164.sh) | - | Belum diuji | - |
| GSP1077 | Google Kubernetes Engine Pipeline using Cloud Build | [gsp1077.sh](gsp1077.sh) | [docs/gsp1077.md](docs/gsp1077.md) | Belum diuji; tiga fase, `gh auth login` + install Cloud Build GitHub App wajib manual | - |
| GSP190 | IAM Custom Roles | [gsp190.sh](gsp190.sh) | [docs/gsp190.md](docs/gsp190.md) | Terverifikasi, skor 100/100; keenam checkpoint diklik sekaligus di akhir | 2026-08-07 |
| GSP647 | Configuring IAM Permissions with gcloud | [gsp647.sh](gsp647.sh) | [docs/gsp647.md](docs/gsp647.md) | Terverifikasi, skor 100/100; dua fase, fase `vm` wajib (empat checkpoint dinilai dari dalam VM `centos-clean`) | 2026-08-07 |
| GSP526 | Privileged Access with IAM: Challenge Lab | [gsp526.sh](gsp526.sh) | [docs/gsp526.md](docs/gsp526.md) | Terverifikasi, skor 100/100; empat fase, dua di antaranya di Cloud Shell milik user kedua | 2026-08-07 |
| GSP499 | User Authentication: Identity-Aware Proxy | [gsp499.sh](gsp499.sh) | [docs/gsp499.md](docs/gsp499.md) | Belum diuji; nol langkah Console (IAP diatur lewat gcloud) | - |
| GSP1317 | Establish VPC to VPC Connectivity using NCC | [gsp1317.sh](gsp1317.sh) | [docs/gsp1317.md](docs/gsp1317.md) | Terverifikasi, skor 100/100 sekali jalan; dua fase, Task 6 (hapus hub/spoke) terpisah | 2026-08-07 |
| GSP528 | Connecting Cloud Networks with NCC: Challenge Lab | [gsp528.sh](gsp528.sh) | [docs/gsp528.md](docs/gsp528.md) | Terverifikasi, skor 100/100; dua fase (satu VPC cuma boleh nempel ke satu hub), nama resource dideteksi sendiri | 2026-08-07 |
| GSP393 | Implement CI/CD Pipelines on Google Cloud: Challenge Lab | [gsp393.sh](gsp393.sh) | [docs/gsp393.md](docs/gsp393.md) | Terverifikasi, skor 100/100; dua fase, rollback tidak boleh diberi `--rollout-id` kustom | 2026-08-08 |
| GSP1079 | Continuous Delivery with Google Cloud Deploy | [gsp1079.sh](gsp1079.sh) | [docs/gsp1079.md](docs/gsp1079.md) | Belum diuji; satu fase, 18-25 menit (tiga cluster GKE) | - |
| GSP319 | Build a Website on Google Cloud: Challenge Lab | [gsp319.sh](gsp319.sh) | [docs/gsp319.md](docs/gsp319.md) | Terverifikasi, skor 100/100 sekali jalan; nama image dan cluster diacak per instance | 2026-08-10 |
| GSP330 | Implement DevOps Workflows in Google Cloud: Challenge Lab | [gsp330.sh](gsp330.sh) | - | Belum diuji; lima fase, Task 3 (dua Cloud Build trigger) dan `gh auth login` wajib manual | - |
| GSP527 | Kickstarting Application Development with Gemini Code Assist: Challenge Lab | [gsp527.sh](gsp527.sh) | - | Dijalankan di lab sungguhan 2026-08-10 (dari situ ketahuan lab tidak men-deploy backend ke Cloud Run), skor akhir belum tercatat | 2026-08-10 |
| GSP1063 | Finding Data in Google Sheets | - | [docs/gsp1063.md](docs/gsp1063.md) | Tidak bisa di-script (100% Google Sheets); runbook terverifikasi 100/100 sekali jalan | 2026-08-07 |
| GSP1062 | Validate Data in Google Sheets | - | [docs/gsp1062.md](docs/gsp1062.md) | Tidak bisa di-script (100% Google Sheets); runbook terverifikasi 100/100 — Task 1 wajib hijau penuh sebelum Task 3 | 2026-08-08 |
| ARC126 | Develop with Apps Script and AppSheet: Challenge Lab | - | [docs/arc126.md](docs/arc126.md) | Tidak bisa di-script (AppSheet + Apps Script + Chat, semuanya UI); runbook terverifikasi 100/100 | 2026-08-08 |
| GSP1146 | Develop No-Code Chat Apps with AppSheet | - | [docs/gsp1146.md](docs/gsp1146.md) | Tidak bisa di-script (UI AppSheet + Google Chat); runbook belum diuji langsung, tapi alurnya sama dengan ARC126 | - |

Tiap lab punya runbook di `docs/` berisi urutan perintah, nilai yang harus muncul sebagai sanity check, dan troubleshooting. **Baca runbook-nya dulu sebelum jalan**, terutama GSP340 (parameter acak) dan GSP1143 (dua fase).

Keterangan status:

- **Terverifikasi** berarti script pernah dijalankan sampai selesai di lab instance sungguhan dan semua checkpoint hijau, dengan skor yang tercatat di kolom yang sama.
- **Belum diuji** berarti script lolos pemeriksaan syntax dan `shellcheck`, tapi belum pernah dijalankan di lab instance sungguhan.
- **Satu varian task** khusus untuk challenge lab: script terbukti 100% pada varian task yang tercatat di file, tapi karena tasknya diacak per instance, varian lain bisa butuh penyesuaian variabel.

Lab dites ulang saat Google memperbarui materinya. Kolom "Terakhir diuji" menunjukkan kapan verifikasi terakhir dilakukan, jadi kalau tanggalnya sudah lama sementara lab-nya baru saja diupdate, anggap statusnya perlu dikonfirmasi ulang.

## Validasi tanpa lab instance

```bash
bash test/run.sh            # semua script
bash test/run.sh gsp416.sh  # satu script
```

Tiga lapis: `bash -n`, `shellcheck -S error`, lalu **dry-run** — script benar-benar dijalankan,
tapi `gcloud`, `bq`, `gsutil`, `kubectl`, `terraform`, `curl`, dan `git` diganti stub di
`test/stubs.sh` yang mencatat tiap panggilan dan menjawab dengan data berbentuk masuk akal.

Yang ditangkap: syntax, variabel kosong yang kena `set -u`, urutan langkah salah, loop tak
berbatas, dan cabang yang tidak pernah tercapai. Yang **tidak** ditangkap: apakah flagnya benar
menurut API sungguhan, dan apakah checkpoint jadi hijau. Dua hal itu cuma bisa dibuktikan di lab
instance sungguhan, jadi status "Terverifikasi" di tabel atas tetap datang dari sana, bukan dari
harness ini.

Status `NEED-NET` berarti script mati karena stub tidak benar-benar mengunduh apa pun, jadi
`cd` ke direktori hasil `git clone`/`gsutil cp` gagal. Itu batas harness, bukan bug script.

Cakupan repo ini terhadap katalog Arcade ada di [docs/coverage.md](docs/coverage.md).

Selain lab, program Arcade kadang menawarkan tugas bonus yang dikerjakan di akun Google Cloud
pribadi. Yang pernah ditelusuri: [docs/gear-bonus.md](docs/gear-bonus.md) — GEAR Mini-Project
(bangun AI agent + submit form). **Tidak diselesaikan**: billing pribadi dengan kartu debit
Indonesia mewajibkan prabayar Rp 500rb.

### Lab yang tidak cocok diotomasi

**Challenge lab** memilih task secara acak per instance, ditandai teks `Dynamically selected task will show up here...` di halaman labnya. Nama dataset, tabel, dan kolom berbeda tiap peserta, jadi script statis bisa salah parameter.

`gsp340.sh` tetap disertakan, tapi semua nilai yang bisa berubah dikumpulkan di satu blok variabel di awal file. **Cocokkan blok itu dengan teks task di lab-mu sebelum menjalankan.** Kalau nama datasetnya beda, ubah variabelnya, jangan query di bawahnya.

**Lab berbasis Console** menilai artefak yang dibuat lewat UI, bukan resource yang bisa dibuat lewat API. Contoh terdokumentasi: **GSP1154 (Getting Started with Agent Studio)** — runbook lengkapnya di [docs/gsp1154.md](docs/gsp1154.md).

`gsp1154.sh` ada di repo ini tapi **sudah terbukti menghasilkan 0 poin**, dan sengaja tidak dimasukkan ke tabel di atas. Dites di lab instance sungguhan pada 2026-07-17: skor 0/5.

Yang menarik, kegagalannya bukan karena scriptnya error. Task 1, 2, dan 3 jalan tuntas, API-nya merespons, isinya sesuai lab — **dan tetap 0 poin**. Pesan checkpoint-nya yang menjelaskan kenapa:

```
Please create the 'Insurance Risk Factor Identification' prompt to see the 'Compare' feature
Please run the prompt to generate an image with 'Nano Banana 2'
```

Yang dicari checkpoint adalah **prompt tersimpan dengan nama tertentu** di Agent Studio, app Cloud Run hasil "Deploy as app", dan media hasil generate di Media Studio. Memanggil Vertex AI API dengan isi prompt yang sama persis tidak meninggalkan satu pun artefak itu. Jadi asumsi "checkpoint melihat jejak pemakaian API di project" salah, dan tidak ada tambalan kecil yang bisa memperbaikinya.

Pelajarannya untuk lab lain: **kalau checkpoint menyebut nama artefak UI, otomasi lewat API tidak akan menghasilkan poin** — sebanyak apa pun API call yang sukses. Kerjakan manual, GSP1154 cuma ~15 menit klik.

Script-nya tetap disimpan sebagai pendamping belajar: dia menjalankan semua prompt lab lewat API sekaligus, jadi bisa dipakai membandingkan efek temperature, top-P, few-shot, dan Flash lawan Pro tanpa mengklik satu-satu. **Bukan pengganti lab-nya.**

Catatan lain dari pengujian itu, kalau nanti ada yang meneruskan:

- Model di lab: `gemini-3.5-flash` dan `gemini-2.5-pro` (pasangannya memang terbalik, Flash-nya lebih baru). Keduanya valid di endpoint `global`.
- Gemini 3 pakai `thinkingConfig.thinkingLevel` (enum, mis. `MINIMAL`), bukan `thinkingBudget` (angka) seperti generasi 2.x.
- `gemini-2.5-pro` gampang kena `429 Resource has been exhausted` di project lab.
- Akun student lab tidak punya izin `serviceusage`, jadi jangan panggil `gcloud services enable` — Qwiklabs sudah meng-enable API-nya sejak provisioning.
- Task 5 di materi terbaru pakai **Nano Banana 2**, bukan Imagen 4 seperti yang masih tertulis di teks tugas.

## Yang tidak diotomasi

Script ini mengerjakan bagian yang di-score lewat **Check my progress**, yaitu pembuatan dataset, load tabel, dan eksekusi query. Yang tetap harus dikerjakan manual:

- **Soal pilihan ganda.** Tidak ada API-nya, harus diklik sendiri di halaman lab.
- **Langkah yang murni baca UI.** Contohnya GSP416 Task 5, cuma star `bigquery-public-data` lalu lihat schema. Tidak ada yang di-score di situ.
- **Query yang sengaja dibuat error.** Beberapa lab menyuruh menjalankan query yang pasti gagal supaya kamu lihat pesan errornya. Ini dilewat karena `set -euo pipefail` akan menghentikan script. Jalankan manual di UI kalau ingin melihatnya.

## Catatan

- Script dibuat idempoten (`mk -f`, `load --replace`), jadi aman diulang kalau gagal di tengah.
- Location dikunci ke `US` karena dataset publik seperti `data-to-insights` dan `bigquery-public-data` ada di US, dan BigQuery menolak query lintas-location.
- Project diambil dari `$DEVSHELL_PROJECT_ID` (otomatis terisi di Cloud Shell), fallback ke `gcloud config get-value project`.

## Peringatan

Pola `curl ... | bash` menjalankan kode dari internet tanpa kamu baca dulu. Untuk repo ini kodenya milik sendiri, tapi biasakan tetap baca isinya, apalagi kalau kamu fork atau ada orang lain yang punya akses tulis ke repo ini.

Script ini dibuat untuk belajar. Kalau langsung dijalankan tanpa mengikuti materinya, kamu dapat centang hijau tapi tidak dapat ilmunya.
