# Alat (tools)

## Skrip di `bin/`
Agen memanggilnya sebagai `$AGENT_WORKFLOW_DIR/bin/<skrip>`. Kamu juga boleh menjalankannya manual.

| Skrip | Gunanya | Contoh |
| --- | --- | --- |
| `device-pick.sh` | Ambil device bebas: virtual yang menyala → boot virtual bila belum menyala (1 per platform) → device fisik bila virtual penuh. `--physical` = hanya fisik, untuk fitur yang butuh hardware asli | `AGENT_LOCK_PID=$PPID bin/device-pick.sh ios PROJ-1234-qa1` → `ios:<udid>` |
| `device-lock.sh` | Kunci device/akun/checkout supaya satu benda dipakai satu agen | `bin/device-lock.sh who ios:<udid>` |
| `ios-ui.sh` | Jalankan langkah uji iOS lewat XCUITest runner (lihat bawah) | `bin/ios-ui.sh <udid> steps.json out/` |
| `annotate.py` | Gambar kotak merah + label di screenshot dari koordinat | `uv run --with pillow python3 bin/annotate.py in.png boxes.json out.png` |
| `build-number.sh` | Tentukan nomor build; exit 3 = sumber tidak sepakat, agen bertanya | `bin/build-number.sh next asc=41 firebase=41 tag=40` |
| `manifest-check.sh` | Bandingkan tiket di commit branch rilis dengan manifest | `bin/manifest-check.sh origin/master origin/release/v1.2.0 PROJ-1 PROJ-2` |
| `build-preempt.sh` | `reap`: lepas `build:heavy` yang lupa dilepas (tidak ada build 20 menit; housekeeping menjalankannya tiap jam). Saat `build:heavy` dipakai tiket lain: `info` (siapa, berapa lama, sedang upload?), `take` (hentikan build itu dan ambil kunci, setelah kamu setuju), `check` (agen yang dihentikan tahu harus build ulang) | `bin/build-preempt.sh info` |
| `device-preempt.sh` | Ambil alih device yang dikunci agen lain, hanya setelah kamu setuju: `info` (siapa, berapa lama, sedang diuji?), `take` (hentikan proses uji di device itu, tulis catatan untuk pemegang lama, pindahkan kunci) | `bin/device-preempt.sh info android:<serial>` |
| `uat-watch.sh` | Pantau log app selama slot UAT di HP fisik: catat semua baris dan crash, lepas kunci `human-<KODE>` setelah 3 menit tanpa log; exit 3 = paket Android tidak ketemu atau proses log berhenti (`end=error`), kunci tidak disentuh | `bin/uat-watch.sh android:<serial> <package> human-<KODE> <outdir>` |
| `audit-mode.sh` | Nyalakan/matikan mode hanya-baca untuk `/audit-issue` | `AGENT_LOCK_PID=$PPID bin/audit-mode.sh status` |
| `housekeeping.sh` | Bersihkan cache build tiap jam (dijalankan launchd, lihat bawah) | otomatis |

Setiap kunci memakai `AGENT_LOCK_PID=$PPID` di perintah yang sama; kunci milik proses yang sudah mati otomatis dianggap bebas.

## Alat device: pilih yang mana?

| Kebutuhan | Android | iOS |
| --- | --- | --- |
| Alur pengguna (E2E, login, chat, regresi, visual dasar) | Maestro | Maestro |
| Maestro terkendala (driver gagal, timeout, elemen tidak terbaca) | Android CLI (`android`) → `adb` | XCUITest runner (`ios-ui.sh`) |
| Inspeksi UI native, screenshot satu elemen, alert sistem, tekan lama | Android CLI (`android layout`, `android input`) | XCUITest runner, langsung tanpa menunggu Maestro gagal |
| Metrik UI (waktu buka app, kelancaran scroll) | — | XCUITest runner `measure` |
| Posisi elemen untuk kotak merah | `maestro hierarchy` atau `android layout` | `maestro hierarchy` atau `<nama>-frames.json` dari XCUITest |
| Build | `./gradlew` (flavor project) | `xcodebuild` |

Urutan cadangan: coba Maestro sekali lagi setelah app di-restart → alat cadangan → kalau tetap gagal, TC ditandai **Tertahan** dengan alat yang dicoba dan error-nya.

## Virtual atau fisik?
**Virtual dulu** (simulator/emulator): lebih cepat dan device fisik tetap bebas. Tiap platform punya **1 virtual + 1 fisik**, jadi paling banyak 2 agen per platform memakai device bersamaan. Virtual penuh → otomatis pindah ke device fisik.

Langsung **device fisik** (`--physical`) bila yang diuji butuh hardware asli: push notification APNs, kamera/scan QR, NFC, Bluetooth, sensor/GPS bergerak, SMS/telepon asli, biometrik/pembayaran, metrik performa, atau bug di model device tertentu. TC seperti ini ditandai `(fisik)` di rencana. Daftar lengkap: "Kapan wajib device fisik" di [skills/_shared/devices.md](../skills/_shared/devices.md).

## XCUITest runner (iOS)
Proyek Xcode kecil di `ios-runner/` yang mengendalikan app apa pun lewat bundle id, jadi repo app tidak disentuh. Dibangun otomatis sekali (± 30 detik), lalu dipakai ulang.

```bash
cat > steps.json <<'X'
[{"launch":"com.app.dev"},
 {"type":"PROJ-1234-user","into":{"id":"phone"}},
 {"tap":{"label":"Masuk"}},
 {"alert":"Allow"},
 {"screenshot":"TC1-01"},
 {"hierarchy":"TC1-02"},
 {"elementShot":"TC1-03","of":{"id":"btnSave"}}]
X
bin/ios-ui.sh <udid> steps.json /tmp/qa/PROJ-1234/xcui-1
```
- Hasil: `TC1-01.png`, `TC1-02.txt` (pohon UI), `TC1-02-frames.json` (posisi elemen dalam piksel), `TC1-03.png`, `metrics/*.csv` (bila ada `measure`). Langkah gagal → exit ≠ 0 dan `fail-step<N>.png`.
- iPhone fisik butuh `IOS_TEAM` (Team ID dari project app); simulator tidak.
- Daftar aksi dan selector lengkap: bagian "Pilih alat iOS" di [skills/_shared/devices.md](../skills/_shared/devices.md).

## Alat lain

| Alat | Dipakai untuk |
| --- | --- |
| Maestro | Aksi di device (tap, ketik, scroll), screenshot tiap langkah |
| Android CLI (`android`) | Cadangan Maestro di Android, pasang/jalankan APK, docs Android |
| Schemathesis | Uji API terhadap spec di repo, hanya dev/staging |
| Pact | Uji kontrak bila ada kontrak di repo |
| `gh` / `glab` | Membuat PR (GitHub) / MR (GitLab) |
| Firebase CLI / TestFlight | Upload build dev/beta; prod hanya dengan izin |
| Orca CLI | Workspace, worktree, panel teammate (lewat plugin agent view Orca) |
| Atlassian MCP / Claude Docs MCP | Baca & komentar Jira / tulis laporan |

## Skill pendukung
Selain empat perintah di repo ini, agen memakai skill yang terpasang di `~/.claude/skills` atau sebagai plugin Claude Code. Skill ini tidak ada di repo; pasang terpisah (lihat [Pasang di komputer lain](pasang.md)).

| Skill | Dipakai untuk |
| --- | --- |
| `android-cli` | Android CLI Google: pasang/jalankan APK, inspeksi layout, input, emulator, docs Android; cadangan Maestro |
| `orca-cli` | Worktree, terminal, dan browser Orca; worktree tiket dan panel teammate |
| `orchestration` | Worker Orca terpisah (mis. Codex) dengan tugas dan hasil yang dilaporkan balik |
| `orca-computer-use` | Mengendalikan jendela app di Mac bila tidak ada jalur CLI |
| `graphify` | Peta pengetahuan codebase (`/graphify`) untuk pertanyaan arsitektur dan relasi file |
| `superpowers` (plugin) | Fitur besar: brainstorming → rencana → TDD → review → verifikasi |
| `ponytail` (plugin) | Fix kecil dengan perubahan sesedikit mungkin; juga review dan audit kualitas |
| `kotlin-agent-skills` (plugin) | Migrasi dan performa build Kotlin/KMP (AGP 9, CocoaPods → SPM, Kotlin/Native) |

## MCP yang dipakai
MCP = konektor yang membuat Claude bisa memakai layanan luar. Workflow ini memakai dua, keduanya dipasang sebagai konektor di claude.ai:

| MCP | Gunanya | Dipakai oleh | Fungsi yang dipanggil |
| --- | --- | --- | --- |
| **Atlassian** (Jira) | Baca tiket, komentar, pindah status, buat tiket rilis | Validator, SPV, Release, Auditor (baca saja) | `getJiraIssue`, `searchJiraIssuesUsingJql`, `addCommentToJiraIssue`, `transitionJiraIssue`, `getTransitionsForJiraIssue`, `createJiraIssue` + `createIssueLink` (tiket rilis), `atlassianUserInfo` (cek koneksi) |
| **Claude Docs** | Laporan validasi, rencana + test case, laporan uji, laporan audit (bergambar) | Validator, SPV, Planner, `/audit-issue` | `batch` (buat/isi dokumen), unggah screenshot |

Bukan bagian workflow (boleh terpasang, tidak dibutuhkan): GitHub MCP (PR dibuat lewat `gh` CLI), context7 (docs library untuk coding biasa). Guard ikut memeriksa panggilan Atlassian: transisi di luar daftar ditolak, dan di mode audit semua penulisan Jira diblokir.

## Pembersihan otomatis (`housekeeping.sh`)
Dijalankan launchd tiap jam (`com.agentworkflow.housekeeping`). Gratis, jalan walau Orca tertutup, tanpa agen Claude.

**Kapan dilewati:** hanya saat ada build yang benar-benar jalan: kunci `build:heavy` dipegang, atau proses `xcodebuild`, `gradlew`, atau upload aktif. Kunci checkout/device/akun milik sesi yang dibiarkan terbuka, dan Gradle daemon yang diam, **tidak** dihitung sibuk.
- **Harian (≥ 03.00):** DerivedData Xcode > 3 hari; APK/AAB/IPA > 7 hari di folder `~/.agent-workflow/build-roots.txt`.
- **Mingguan (Minggu ≥ 03.30):** semua DerivedData, cache Gradle/Kotlin Native lama, iOS DeviceSupport > 90 hari, simulator rusak, cache CocoaPods/brew/npm.
- **Darurat:** sisa disk < 50 GB → bersihkan harian sekarang; masih kurang → notifikasi. Saat build jalan, darurat tetap membersihkan bagian yang aman (DeviceSupport lama, simulator rusak, cache CocoaPods/brew/npm).
- **Pengingat:** pembersihan harian terlewat lebih dari sehari karena build terus berjalan → notifikasi sekali per hari.
- Log: `~/.agent-workflow/logs/housekeeping.log`. Banyak "busy, skipping" berarti ada build yang tidak selesai. Kunci `build:heavy` yang lupa dilepas agen (tidak ada build 20 menit) dilepas otomatis di awal tiap putaran ("released forgotten build:heavy" di log).

---
[← kembali ke README](../README.md)
