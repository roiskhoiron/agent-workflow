# `/audit-issue` — desain

## Maksud
User sering menerima permintaan audit yang belum menjadi tiket Jira: keluhan, pertanyaan "kenapa X begini", atau temuan sendiri. Permintaan itu sering datang bersama file non-kode (mockup, PDF, gambar). User butuh audit yang **sangat terperinci**: bukti dari kode, riwayat, log, layar device, dan lampiran, disimpulkan menjadi akar masalah dan saran. Hasilnya satu laporan Claude Docs. Tiket Jira hanya saran.

## Pemanggilan
```
/audit-issue "<teks permintaan>" [--solo|--tim] [<path atau link lampiran>...]
```
- Teks wajib, dalam tanda kutip.
- `--solo` / `--tim` memaksa mode; tanpa flag SPV menilai (permintaan satu platform dan sempit = solo, selain itu tim). *(keputusan Claude, mengikuti `/develop-tiket`)*
- Lampiran: path lokal (gambar, PDF, mockup, file lain), link (Figma, Google Drive, Jira, web), dan file yang ditempel di chat.

## Tujuan
- Satu laporan Claude Docs yang menjawab permintaan dengan bukti: kode (file:baris), git log/blame, Crashlytics/log, screenshot device bertanda, kutipan lampiran.
- Perbandingan lampiran vs kode vs layar sebenarnya bila lampiran ada.
- Akar masalah dengan tingkat keyakinan (pasti / kuat / dugaan), dampak, perkiraan ukuran perbaikan, saran langkah berikutnya.
- Saran tiket Jira di akhir laporan (judul, deskripsi, AC, platform), siap dipakai user bila setuju.

## Bukan tujuan
- Memperbaiki masalah, menulis kode, membuat branch, commit, worktree, PR/MR.
- Membuat tiket Jira, berkomentar di Jira, atau memindah status tiket.
- Build atau upload aplikasi.

## Anti-tujuan (gagal walau "jalan")
- Kesimpulan tanpa bukti, atau dugaan ditulis seolah pasti.
- Lampiran dilewati diam-diam (file tidak terbaca harus disebut).
- Laporan di luar Claude Docs, atau lebih dari satu dokumen per audit.
- Panel worker ganda / dibiarkan terbuka setelah tugasnya habis.

## Batasan
- Mengikuti `rules.md` (guard, tanya dengan satu saran, kredensial tidak pernah ditulis, workspace Orca, panel lewat `worker-pane.sh`, nama agen).
- **Hanya-baca** terhadap repo dan Jira, dipaksa guard (lihat "Hanya-baca dipaksa guard"). Boleh dijalankan dari root project (yang memang untuk audit) atau workspace domain.
- **Model: semua peran `claude-opus-5-5`** (keputusan user), ditulis sebagai satu nilai di skill.
- Device dan akun uji **boleh** bila permintaan menyangkut perilaku aplikasi: `device-pick.sh`, akun dev/staging, kunci dilepas sesudahnya (sama seperti `/validate-tiket`). Permintaan soal dokumen/desain saja → device tidak disentuh.
- Bahasa laporan: Indonesia; ringkasan di awal ditulis untuk pembaca awam, detail teknis di bawahnya.

## Alur (disetujui user)
0. **Cek awal:** kenali tempat jalan (root/domain). Baca semua lampiran; yang gagal dibuka dicatat.
1. **Pecah permintaan:** gejala, platform, fitur/layar, daftar pertanyaan yang harus dijawab. Kabur → periksa dulu, lalu tanya dengan satu saran.
2. **Buat dokumen Claude Docs sejak awal:** kerangka per pertanyaan (blok `pending`), supaya user bisa melihatnya terisi. Ini juga dokumen laporan final.
3. **Penelusuran:**
   - Solo: satu sesi mengerjakan semua peran berurutan.
   - Tim: worker sebagai panel lewat `worker-pane.sh open`, semua Opus; SPV membagi pertanyaan per worker, worker menulis temuan ke file di `${TMPDIR:-/tmp}/audit/<slug>/`, SPV memasukkannya ke Docs.
4. **Reproduksi** (bila relevan): Maestro → Android CLI → adb (urutan `devices.md`), screenshot dengan kotak merah dari koordinat.
5. **Simpulkan (SPV):** akar masalah + keyakinan, dampak, ukuran perbaikan, saran.
6. **Rapikan dokumen yang sama menjadi laporan final**, termasuk saran tiket Jira.
7. **Bersihkan:** `worker-pane.sh close` semua panel, lepas kunci device/akun. Chat: link laporan + satu kalimat kesimpulan.

## Peran tim *(keputusan Claude)*
| Peran | Label | Nama | Tugas |
|---|---|---|---|
| SPV | SPV | Pak Darmo | pecah permintaan, bagi tugas, simpulkan, tulis Docs |
| Penelusur kode | Auditor | Cecep, Dadang, Sarip (per platform: android/ios/api) | kode, git log/blame, Crashlytics/log |
| Penelaah lampiran | Analis | Bu Lastri | baca mockup/PDF/gambar/link, daftar perbedaan dengan kode/layar |
| QA reproduksi | QA | Paijo, Euis, Ningsih (dipakai ulang) | reproduksi di device, screenshot bertanda |

Nama baru ditambahkan ke tabel "Nama agen" di `rules.md`. Peran baru mendapat file `agents/auditor.md` dan `agents/analis.md`.

## Isi laporan
1. Ringkasan untuk awam (3–5 kalimat).
2. Permintaan asli + daftar lampiran (terbaca / gagal).
3. Temuan per pertanyaan, masing-masing dengan bukti.
4. Perbandingan lampiran vs kode vs layar (bila ada lampiran).
5. Akar masalah + tingkat keyakinan, dampak, ukuran perbaikan.
6. Saran langkah berikutnya.
7. Saran tiket Jira (opsional, bukan dibuat).
8. Cara audit: alat yang dipakai, device/build, hal yang tidak bisa diperiksa.

## Keputusan dari pemeriksaan desain *(keputusan Claude, bisa dikoreksi user)*
- **Versi yang diaudit:** versi yang disebut di permintaan; tidak disebut → versi produksi (tag rilis terbaru, mis. `vX.Y.Z`, atau `master`). Kode dibaca tanpa checkout: `git show <ref>:<path>`, `git log <ref>`, `git grep <pattern> <ref>`. Checkout yang ada tidak diubah. Reproduksi memakai build yang setara (store/TestFlight/Firebase, cara memilih seperti `build-release.md`), dan versinya dicatat di laporan.
- **Repo per platform dari root project:** dari `orca worktree list --json` / folder project; pilih repo sesuai platform di permintaan. Tidak jelas → tanya dengan satu saran.
- **Crashlytics, log, dan link lampiran:** dipakai bila alatnya tersedia di sesi (MCP Firebase, Figma, Drive, Atlassian, CLI). Tidak tersedia atau belum login → ditulis di bagian "hal yang tidak bisa diperiksa", audit tetap jalan.
- **Instruksi worker:** semua worker audit mengikuti `agents/auditor.md` (penelusuran kode + reproduksi) atau `agents/analis.md` (lampiran), bukan `qa.md`. Nama QA (Paijo dst.) hanya dipakai ulang untuk worker reproduksi. `qa.md` dan tabel model `/develop-tiket` tidak berubah. Model Opus ditentukan lewat `--command "claude --model claude-opus-5-5"` saat membuka panel.
- **Lampiran yang ditempel di chat:** dipegang SPV (hanya sesi SPV yang bisa melihatnya); SPV menelaahnya sendiri dan memberi worker ringkasannya. Lampiran berupa path/link dibagikan ke Analis. Agar gambar bisa diunggah ke Docs, user dianjurkan memberi path file.

## Hanya-baca dipaksa guard (keputusan user)
Selama audit, `hooks/guard.sh` berada dalam **mode audit** dan memblokir semua tulis ke repo dan Jira. Rincian di bawah adalah keputusan Claude:
- **Penanda mode audit:**
  - Worker dibuka dengan `AGENT_AUDIT=1` di `--command` (`"AGENT_AUDIT=1 claude --model claude-opus-5-5"`). Hook mewarisi env itu.
  - Sesi SPV (sudah berjalan, env tidak bisa diubah) memakai file penanda per pid Claude lewat skrip baru `bin/audit-mode.sh on|off` (pola `AGENT_LOCK_PID=$PPID` seperti `device-lock.sh`). Guard menelusuri pid leluhurnya untuk menemukan penanda. Penanda dengan pid mati diabaikan.
  - `/audit-issue` menyalakan penanda di langkah 0 dan mematikannya di langkah 7 serta saat berhenti lebih awal.
- **Diblokir dalam mode audit:**
  - Edit/Write/MultiEdit/NotebookEdit di luar folder kerja audit `${TMPDIR:-/tmp}/audit/`.
  - git yang mengubah repo: `commit`, `checkout`, `switch`, `restore`, `reset`, `merge`, `rebase`, `pull`, `push`, `stash`, `cherry-pick`, `revert`, `am`, `apply`, `clean`, `tag` (kecuali daftar), `branch` dengan `-d/-D/-m/-c` atau nama baru, `worktree add|remove|move`. `git fetch` boleh (tidak mengubah kode yang di-checkout, dan diperlukan untuk membaca tag produksi terbaru).
  - Tulis ke Jira/Confluence lewat MCP: buat/edit tiket, komentar, transisi, worklog, link tiket, buat/edit halaman. Matcher hook di `install.sh` diperluas ke tool-tool itu.
  - `gh`/`glab` yang menulis (`pr|mr create`, `comment`, `merge`, `close`), dan `orca worktree create`.
- **Tetap boleh:** membaca semua hal, `git show/log/grep/blame/diff/fetch`, Claude Docs, device (Maestro/Android CLI/adb), `device-lock.sh`, `worker-pane.sh`, tulis file di folder kerja audit.
- Tes guard baru: tiap jenis yang diblokir dan yang boleh, untuk penanda env maupun penanda file.

## Diserahkan ke pembangun
- Format persis argumen (parsing teks berkutip + flag + lampiran).
- Slug folder kerja audit.
- Susunan kerangka dokumen Docs dan cara unggah screenshot (ikuti `report-format.md`).
- Tes: cek agen/skill seperti `tests/agents_test.sh` (referensi file ada, nama di tabel).
