# agent-workflow

Tim agen Claude Code + Orca untuk mengerjakan tiket Jira di proyek mobile (native iOS/Android, KMP): dari cek tiket, menulis kode, uji di device, build, sampai PR/MR dan rilis. Dilengkapi pagar keamanan (`guard.sh`) dan pembersihan disk otomatis.

Status: **v1 terpasang**, siap uji coba di tiket nyata.

## Daftar isi
1. [Mulai cepat](#mulai-cepat) dan [istilah penting](#istilah-penting) (di halaman ini)
2. [Alur kerja + papan kanban](docs/alur-kerja.md): `/validate-tiket`, `/develop-tiket` (semua flag), `/rilis-tiket`, `/audit-issue`
3. [Tim agen](docs/tim-agen.md): peran, nama, model
4. [Pagar keamanan](docs/pagar-keamanan.md): yang diblokir guard, kapan agen berhenti dan bertanya
5. [Alat (tools) + MCP](docs/alat.md): skrip `bin/`, alat device, skill pendukung, MCP, pembersihan otomatis
6. [Pasang di komputer lain](docs/pasang.md)
7. [Masalah umum](docs/masalah-umum.md)
8. [Isi repo](#isi-repo) dan [merawat dokumen](#merawat-dokumen-ini) (di halaman ini)

## Mulai cepat

Ketik perintah ini di Claude Code, di dalam terminal Orca:

| Perintah | Gunanya | Jalankan dari |
| --- | --- | --- |
| `/validate-tiket KODE... [--solo\|--tim]` | Cek tiket layak dikerjakan; bug direproduksi di device. `--tim`: dibagi ke PdM, Product Designer, Contract Runner, HoE, PjM (+ Spesialis eskalasi). Hasil: laporan bergambar + komentar Jira | mana saja |
| `/develop-tiket KODE... [--solo\|--tim] [--batch\|--separate] [--uat]` | Rencana, kode (TDD), review, uji di device, build, PR/MR, komentar Jira, tiket ke Ready To Review | workspace domain |
| `/rilis-tiket KODE-RILIS` atau `/rilis-tiket baru release\|hotfix` | Kumpulkan tiket ke branch rilis/hotfix, cek manifest, build beta, satu MR ke upstream | root project atau domain |
| `/audit-issue "teks" [--solo\|--tim] [lampiran...]` | Telusuri keluhan yang belum jadi tiket, **hanya-baca**. Hasil: laporan + saran tiket | mana saja |

Contoh:
```text
/validate-tiket PROJ-1234
/develop-tiket PROJ-1234 PROJ-1240 --tim
/develop-tiket PROJ-1300 --solo --separate
/audit-issue "chat tidak muncul notifikasi di iOS 18" --solo
```

Semua flag dan alur tiap perintah: [docs/alur-kerja.md](docs/alur-kerja.md).

## Istilah penting

| Istilah | Penjelasan sederhana |
| --- | --- |
| **SPV** | Agen "mandor": membaca tiket, membagi tugas, memutuskan tiket selesai |
| **Workspace domain** | Workspace Orca yang kamu buka untuk kerja kode (mis. "Manager", "BAA"). Root project hanya untuk audit, tanya, dan rilis |
| **Worktree tiket** | Salinan kerja repo khusus satu tiket, folder `<repo>-<nomor>` di sebelah checkout domain. Dihapus otomatis setelah Ready To Review bila bersih dan sudah di-push |
| **Branch batch** | Branch lokal tempat semua tiket `--batch` digabung untuk satu build. Tidak pernah di-push |
| **Titik tunggu** | Di `--batch`, build dan QA ulang menunggu semua tiket siap, lalu jalan sekali |
| **Guard** | Hook yang memblokir perintah berbahaya sebelum dijalankan |
| **Claude Docs** | Tempat laporan bergambar; link-nya ditaruh di baris pertama komentar Jira |
| **Downstream / upstream** | `origin` = fork kita (boleh push branch); `upstream` = repo utama (hanya lewat MR) |
| **TC / AC** | Test case / acceptance criteria tiket. Hasil TC: Lulus, Gagal, atau Tertahan (dengan alasan) |

## Isi repo

| Folder | Isi |
| --- | --- |
| `skills/<perintah>/SKILL.md` | Langkah tiap perintah (`/validate-tiket`, `/develop-tiket`, `/rilis-tiket`, `/audit-issue`) |
| `skills/_shared/` | Aturan bersama: `rules.md` (tim, guard, git, worktree), `devices.md` (device & alat), `build-release.md`, `credentials.md`, `report-format.md` |
| `agents/` | Peran agen (model, tugas, larangan) |
| `bin/` | Skrip pembantu (tabel di [docs/alat.md](docs/alat.md)) |
| `hooks/guard.sh` | Pagar keamanan |
| `ios-runner/` | XCUITest runner untuk iOS |
| `tests/` | Tes skrip & guard: `bash tests/run.sh` |
| `docs/` | Panduan lengkap (alur kerja, tim agen, pagar, alat, pasang, masalah umum), rancangan ([design-summary.md](docs/design-summary.md)), spec dan rencana implementasi |

## Merawat dokumen ini

README + folder `docs/` adalah pintu masuk untuk pemula. README tetap singkat (mulai cepat, istilah, daftar isi); detail ada di `docs/<topik>.md` yang ditautkan dari Daftar isi. **Setiap perubahan workflow atau alat wajib memperbarui README atau halaman `docs/` yang sesuai di commit yang sama**: perintah atau flag baru, skrip `bin/` baru, alat device baru, atau aturan keamanan baru. `tests/readme_test.sh` gagal bila ada perintah, skrip `bin/`, atau MCP yang belum disebut di README maupun `docs/*.md`. Detail teknis tetap di `skills/` dan `agents/`; dokumen ini cukup menjelaskan apa, kapan, dan contoh.
