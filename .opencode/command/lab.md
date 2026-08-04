---
description: Bikin script solusi untuk satu lab GSP (pakai kode lab sebagai argumen)
agent: build
---

Buat script solusi untuk lab **$ARGUMENTS**.

Script yang sudah ada di repo ini:

!`ls *.sh docs/*.md 2>/dev/null | tr '\n' ' '`

Langkah:

1. Kalau `docs/` atau instruksi lab-nya belum ada di repo, minta saya paste instruksi labnya dulu. Jangan menebak isi lab.
2. Baca satu script yang paling mirip topiknya sebagai contoh gaya.
3. Tulis `$ARGUMENTS.sh` (huruf kecil) mengikuti konvensi di AGENTS.md: header + daftar checkpoint, `set -euo pipefail`, idempoten, nol interaksi, banner `step()`.
4. Tandai task yang harus manual di Console, jangan dipaksa otomatis.
5. Tulis runbook `docs/$ARGUMENTS.md`: kenapa cocok di-script, cara jalan, tabel task otomatis vs manual, status uji.
6. Jalankan `bash -n` untuk cek sintaks.

Berhenti di situ. Saya yang menjalankan di Cloud Shell dan commit sendiri.
