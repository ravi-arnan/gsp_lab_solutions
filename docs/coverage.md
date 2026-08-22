# Cakupan terhadap katalog Arcade

Katalog di [arcadehub-id.vercel.app/catalog](https://arcadehub-id.vercel.app/catalog) memuat
**68 skill badge**, bukan 68 lab. Tiap badge berisi 3–7 lab, jadi total lab di katalog itu
sekitar 250–400. Repo ini mengerjakan lab satuan, jadi angka yang relevan adalah lab, bukan badge.

## Dari mana daftar ini

Syllabus resmi (`cloudskillsboost.google/course_templates/<id>`) adalah SPA dan isinya butuh
login, jadi tidak bisa dienumerasi dari luar. Pemetaan badge → GSP di bawah berasal dari sumber
komunitas, terutama [gist hotdogee](https://gist.github.com/hotdogee/94745f03887d66e874e9c9e8f0b71f99)
(snapshot 2024-09), divalidasi silang jumlah labnya dengan [arcadecalculator.in/syllabus](https://arcadecalculator.in/syllabus) (2026).

**Perlakukan kode GSP di sini sebagai petunjuk, bukan fakta.** Cocokkan dengan halaman lab-mu
sebelum dipakai. Judul lab banyak berubah (Dataplex → Knowledge Catalog, DLP → Sensitive Data
Protection), tapi kode GSP-nya tetap — jadi pakai kode sebagai kunci, jangan judul.

## 20 badge yang sudah dipetakan

Tanda ✅ berarti scriptnya sudah ada di repo ini.

| Badge | Lab |
|-------|-----|
| 636 Build Infrastructure with Terraform | ✅GSP156, ✅GSP750, ✅GSP751, ✅GSP752, ✅GSP345 — **lengkap** |
| 655 Optimize Costs for GKE | ✅GSP766, ✅GSP767, GSP768, GSP769, ✅GSP343 |
| 624 Build a Data Warehouse with BigQuery | ✅GSP413, ✅GSP414, ✅GSP412, ✅GSP416, ✅GSP340 — **lengkap** |
| 623 Derive Insights from BigQuery Data | GSP281, GSP072/GSP071, GSP407, GSP408, GSP409, GSP787 |
| 681 Build a Data Mesh with Dataplex | ✅GSP1143, ✅GSP1145, ✅GSP1157, ✅GSP1158, ✅GSP514 — **lengkap** |
| 726 Get Started with Dataplex | ✅GSP1143, ✅GSP1144, ✅GSP1145, ✅ARC117 — **lengkap** |
| 1164 Secure Software Delivery | ✅GSP1183, ✅GSP1184, ✅GSP1185, ✅GSP521 |
| 783 Manage Kubernetes in Google Cloud | ✅GSP053, ✅GSP736, ✅GSP1026, ✅GSP510 — **lengkap** |
| 663 Deploy Kubernetes Applications | GSP055, GSP100, GSP021, GSP318 |
| 750 Get Started with Sensitive Data Protection | GSP107, GSP864, GSP1073, ARC116 |
| 1177 Discover and Protect Sensitive Data | ✅GSP1281, ✅GSP1282, GSP1283, ✅GSP522 |
| 728 Get Started with Pub/Sub | GSP096, GSP401, GSP832, ✅ARC113 |
| 725 Get Started with Cloud Storage | ✅GSP421, ✅GSP074, ✅GSP297, ✅ARC111 — **lengkap**, keempatnya sudah terverifikasi 100/100 |
| 727 Get Started with Eventarc | ✅GSP095, ✅GSP1089, GSP773, ARC118 |
| 641 Set Up a Google Cloud Network | ✅GSP647, GSP662, GSP021, GSP016, GSP617, GSP918, GSP314 |
| 654 Build a Secure Google Cloud Network | GSP1036, GSP211, GSP213, GSP215, GSP216, GSP322 |
| 625 Develop Your Google Cloud Network | GSP064, GSP281, GSP211, ✅GSP089, ✅GSP053, GSP321 |
| 648 Implement Load Balancing on Compute Engine | GSP001/GSP093, GSP002, GSP007, GSP313 |
| 716 Implement DevOps Workflows | GSP121, ✅GSP053, ✅GSP1077, ✅GSP330 |
| 691 Implement CI/CD Pipelines | GSP1076, ✅GSP1077, ✅GSP1079, ✅GSP393 |

Badge 623 dan 648 menawarkan lab alternatif (`A/B`), jadi jumlah lab wajibnya lebih kecil dari
jumlah kode yang tertulis.

48 badge sisanya belum dipetakan. Urutan pengerjaan 51 badge yang belum selesai ada di [roadmap.md](roadmap.md).

## Lab bersertifikat di luar 20 badge itu

Sesi 2026-08-21/22 menambah sebelas lab yang badge-nya belum ada di tabel atas.
Dicatat di sini supaya tidak ditulis ulang dari nol nanti, semuanya sudah
terverifikasi 100/100 kecuali yang ditandai:

| Lab | Tema |
|-----|------|
| ✅GSP073, ✅GSP074 | Cloud Storage Qwik Start (console dan CLI) |
| ✅GSP095 | Pub/Sub Qwik Start CLI |
| ✅GSP207, ✅GSP903, ✅ARC110 | Dataflow: batch, streaming Pub/Sub→GCS, dan challenge-nya |
| ✅GSP659 | Deploy website di Cloud Run |
| ✅ARC100, ✅ARC102 | Challenge thumbnail: gen2 (Memories) dan gen1 (Wild) |
| ✅ARC112 | Challenge App Engine |
| ✅ARC131 | Challenge Speech API |
| ✅GSP351 | Challenge Database Migration Service |
| ✅GSP328 | Challenge Cloud Run serverless |
| ✅GSP523 | Challenge multimodal vector search BigQuery |
| ⚠️ARC114 | Challenge Speech + Language — maks 75/100, checkpoint Task 4 rusak |

## Badge yang sudah tertutup penuh

- **636 Build Infrastructure with Terraform** — GSP156 + 750 + 751 + 752 + 345.
- **624 Build a Data Warehouse with BigQuery** — GSP413 + 414 + 412 + 416 + 340.
- **681 Build a Data Mesh with Dataplex** — GSP1143 + 1145 + 1157 + 1158 + 514.
- **726 Get Started with Dataplex** — GSP1143 + 1144 + 1145 + ARC117.
- **1164 Secure Software Delivery** — GSP1183 + 1184 + 1185 + 521.
- **725 Get Started with Cloud Storage** — GSP421 + 074 + 297 + ARC111.
- **783 Manage Kubernetes in Google Cloud** — GSP053 + 736 + 1026 + 510.

"Lengkap" berarti scriptnya ada untuk tiap lab, **bukan** berarti sudah terbukti
100 poin. Yang masih berstatus belum diuji: GSP156, GSP413,
GSP053, GSP510, GSP1026, GSP1158, GSP1184, GSP1185, GSP521. GSP1158 malah memang hanya bisa mencapai
60/100 lewat script.

## Badge berikutnya yang paling dekat

- **1177 Discover and Protect Sensitive Data** — punya GSP1281 + 1282 + 522, kurang GSP1283.
- **655 Optimize Costs for GKE** — punya GSP766 + 767 + 343, kurang GSP768 dan GSP769.

## Kenapa sisanya tidak ditulis borongan

Menulis script dari nama lab saja menghasilkan tebakan yang kelihatan benar tapi tidak
menghasilkan poin. Repo ini sudah punya buktinya: `gsp1154.sh` jalan tuntas, semua API call
sukses, skor 0/5 — karena checkpoint-nya mencari artefak UI, bukan jejak API. Rinciannya di
[README](../README.md#lab-yang-tidak-cocok-diotomasi).

Jadi tiap script baru butuh teks task lab-nya dulu, bukan cuma judulnya.
