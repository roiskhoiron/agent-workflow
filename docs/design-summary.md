# Rancangan Workflow Agen Jira

Context (not in doc, for builder): Target is Claude Code on a Mac (M6, 24 GB RAM). Deliverables live in ~/.claude (skills, agents/*.md with `model:` frontmatter, settings.json permissions.deny, launchd jobs). Jira via Atlassian MCP; reports via Claude Docs MCP; git hosting may be GitHub (gh) or GitLab (glab) per project. Apps: native Swift / Kotlin / Java, KMP; maybe Flutter/React later. iOS upload via xcodebuild archive+upload (user is App Store Connect admin); Android via Firebase CLI App Distribution. Tools installed: maestro, schemathesis, pact (ruby standalone), firebase-cli, cocoapods, adb, xcrun. Global CLAUDE.md already says: superpowers for big features, ponytail for small fixes.

## Ringkasan
Tim agen Claude mengerjakan tiket Jira dari Todo sampai Ready To Review lewat `/validate-tiket` dan `/develop-tiket`. Kamu memeriksa hasil akhir; Done = kolega.
- `/validate-tiket KODE...` — cek tiket layak, laporan bergambar
- `/develop-tiket KODE...` — rencana, kode, uji, build, PR/MR
- Tim agen (management + development), sendirian atau beramai-ramai per tiket
- Pagar keamanan; pembersihan berkala
Bisa satu atau beberapa tiket.

## Alur kanban
Todo --/validate-tiket layak--> In Progress --/develop-tiket--> Ready To Review --kolega--> Done. Tidak layak: tetap Todo + komentar alasan.
Todo: Validator (laporan + komentar). In Progress: SPV+Coder+QA. RTR: Release (PR/MR + komentar). Done: manusia.

## Tim agen
Management memutuskan dan berbicara ke luar (Jira, Docs, git remote, Firebase/TestFlight); development hanya kode dan device. Mode satu agen tetap ikut larangan sama.
Hierarki: Kamu -> SPV -> Coder x2-5, QA x2-3; Coder -> Reviewer -> Release; QA -> SPV.
| Agen | Model | Tugas | Tidak boleh |
| SPV | Opus | bagi tugas, jatah device, putuskan selesai | kode produk |
| Validator | Opus | /validate-tiket | kode produk |
| Reviewer | Opus | performa & crash sebelum PR | review kode sendiri |
| Release | Haiku | nomor build, build+upload, PR/MR, komentar & geser tiket | Done, upload prod tanpa izin |
| Housekeeping | Haiku | cache & branch lama | kode, data uji, kredensial |
| Coder | Sonnet | TDD di branch sendiri | Jira, push, upload, device di luar jatah |
| QA | Sonnet | Maestro, Schemathesis, Pact di device | Jira, push, upload, device di luar jatah |
Model diubah di ~/.claude/agents/<peran>.md.

## Mode kerja dan pagar
Diawasi (sesi biasa) vs Otonom (bypass permission). Pagar aktif di keduanya.
Selalu diblokir (permissions.deny): push apa pun ke remote `upstream` (termasuk tag, hapus branch); force-push ke master/main/develop; rm -rf di luar project; pindah tiket ke Done.
Selalu berhenti & bertanya: upload prod; sebelum buat branch rilis/hotfix; nomor build tidak jelas; kredensial tidak ditemukan; dua fix hotfix bentrok.

## /validate-tiket
Meniru laporan contoh. Alur: baca tiket+komentar -> bug: reproduksi di device fisik dulu lalu emulator / fitur: cek requirement + kesiapan API/desain -> screenshot tiap langkah + kotak merah -> laporan Claude Docs -> komentar Jira (link laporan baris pertama) -> layak/ya dengan catatan: geser In Progress; tidak: tetap Todo.
Laporan: Judul `Validasi KODE — judul`, tanggal, nama; Ringkasan tabel AC -> Lulus/Tertahan; Keputusan kalimat tebal + diagram + alasan; satu bagian per TC (langkah bernomor + screenshot); Temuan (data uji, commit diuji, checklist).
Tanda screenshot: kotak merah + label merah teks putih berisi kode AC; posisi dari koordinat elemen di layar device (UI hierarchy), bukan ditebak.
Keputusan parsial boleh; TC butuh device lebih dari tersedia = Tertahan.

## /develop-tiket
1 SPV cek requirement + tiket terkait/blocking -> 2 SPV dokumen rencana + test case (Claude Docs) -> 3 Coder kode+tes TDD, branch feature/ fix/ hotfix/ docs/ chore/ di downstream -> 4 Reviewer performa/crash (revisi loop ke 3) -> 5 QA uji Maestro/Schemathesis/Pact, Claude Docs + screenshot -> 6 Release build dev/beta/prod ke Firebase/TestFlight -> 7 Release push downstream + PR/MR ke upstream -> 8 komentar Jira semua link -> 9 geser Ready To Review.
Tiket kecil: satu agen, langkah 2 catatan singkat.

## Rilis dan hotfix
Branch kerja di downstream (fork); upstream hanya satu MR per rilis/hotfix.
Contoh: hotfix/v1.0.2 dari master; fix/PROJ-101 & fix/PROJ-105 masing2 MR ke hotfix/v1.0.2 di downstream; lalu satu MR hotfix/v1.0.2 -> master upstream.
- Tiket rilis di Jira dibuat Release. Dua jenis: Rilis, Hotfix on Production; judul berisi versi.
- Manifest: tiket yang ikut di-link ke tiket rilis.
- Cek isi build: kode tiket di commit == manifest, beda = berhenti.
- Asal hotfix: master upstream / tag versi live, bukan develop.
- Hotfix yang sudah di-build tidak ditambah; fix baru = versi berikutnya.
- Tag versi dibuat maintainer/CI, bukan agen.
Periksa dulu lalu tanya: bandingkan master, develop, versi live; lapor dengan saran; jawaban dicatat di CLAUDE.md project.

## Device, akun uji, nomor build
Satu device, satu agen, satu waktu. iPhone 13 Pro fisik (prioritas iOS), HP Android fisik (prioritas Android, perlu izin USB), 6 simulator iPhone, 1 emulator Android. Maks 2-3 virtual sekaligus; antre.
Akun uji dari local.properties (qa.*) atau .env/.xcconfig gitignored; belum ada -> sarankan qa.local.properties (template qa.env, qa.user1.phone/password, qa.user2..., qa.api.baseUrl). Wajib di .gitignore; isi tidak pernah ditulis ke Docs/Jira/MR. Satu akun satu agen pada satu waktu.
Data uji hanya dev/staging, awalan kode tiket.
Nomor build: Dev = angka tiket (PROJ-1234 -> 1234); Beta/Prod = terakhir+1, sumber App Store Connect API (jika ada key .p8), Firebase, tag git, file project; tidak cocok/tidak ketemu -> tanya dengan saran; nomor terkonfirmasi dicatat di CLAUDE.md project. Dev pakai ID aplikasi terpisah (.dev).

## Pembersihan berkala
launchd lokal: harian 03:00, mingguan Minggu 03:30, darurat disk < 50 GB. Jika build/upload/device dipakai -> tunda 1 jam. Gagal/disk masih penuh -> notifikasi; selain itu log.
DerivedData >3 hari (mingguan semua); APK/AAB/IPA di build/ >7 hari; Gradle stop daemon (mingguan cache >14 hari); ~/.konan >30 hari; DeviceSupport lama, simulator unavailable; cache CocoaPods/npm/Homebrew; branch downstream sudah merge; Archives hanya jika dSYM otomatis ter-upload: >30 hari, 3 Archive prod terakhir disimpan; jika tidak, tawarkan setup.

## Keputusan Claude dan yang masih terbuka
Keputusan Claude: Reviewer di management; Release terpisah dari SPV; Haiku untuk Release/Housekeeping; batas 50 GB & hari; tag tidak dibuat agen; kotak dari koordinat; launchd lokal.
Terbuka: format judul versi rilis; peran Fable 5.1; API key ASC (opsional); izin USB Android; token GitHub MCP.

## Tambahan (disetujui 2026-10-28)
- Judul tiket rilis: `[release-request] …` / `[hotfix-release] …` (pola versi setelah prefix masih terbuka).
- Tujuan MR: tiket di-link ke tiket rilis → MR ke branch rilis di downstream; selain itu → MR langsung ke upstream.
- Perintah ketiga `/rilis-tiket KODE-RILIS`: buat branch, cek manifest, build, satu MR ke upstream.
- Build per tiket: dev selalu, beta juga, prod setelah izin.
- Validator reproduksi di versi yang tertulis di tiket; kosong → build dev/beta terbaru.
- SPV pilih satu agen / tim; paksa dengan `--solo` / `--tim`.
- Build berat antre satu per satu (RAM 24 GB).
- Pembersihan = skrip shell (tanpa Claude).
- Spec API & kontrak Pact dicari di repo, tidak ada → tanya, catat di CLAUDE.md project.

## Worktree Orca bertingkat
Primary (audit/tanya saja, tidak ada perubahan file) → worktree domain (branch gabungan batch, lokal/downstream saja; 1 build, 1 distribusi, laporan per tiket) → child per tiket (branch + MR sendiri) → child per coder (hanya tiket multi-coder).
- User memilih domain: `/develop-tiket` dijalankan dari dalam worktree domain; di primary → berhenti.
- Nomor build dev batch = angka tiket pertama; semua tiket di catatan rilis Firebase.
- Child worktree dibuat/dihapus lewat Orca, dibersihkan setelah MR di-merge.
- Multi-agent via orkestrasi Orca (coordinator + worker).
