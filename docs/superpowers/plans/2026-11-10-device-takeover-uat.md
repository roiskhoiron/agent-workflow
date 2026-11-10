# Ambil alih device + slot UAT: rencana implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agen boleh uninstall/`pm clear`/install di device yang ia kunci sendiri, bisa mengambil alih device agen lain atas izin user, dan `/develop-tiket --uat` memberi user slot uji manual di HP fisik yang dipantau lognya.

**Architecture:** Kunci tetap `device-lock.sh` (ditambah `move`). `guard.sh` membaca kunci dan catatan ambil alih langsung dari disk: blokir perintah pemasangan/penghapusan app ke device yang dikunci pihak lain, dan blokir semua perintah ke device yang sudah diambil alih dari agen ini. `device-preempt.sh` (pola `build-preempt.sh`) memindah kunci dan menghentikan uji pemilik lama. `uat-watch.sh` memantau log app selama slot `human-<KODE>` dan melepasnya setelah idle.

**Tech Stack:** Bash 3.2 (macOS, `stat -f`), jq, python3 (tokenizer guard yang sudah ada), adb, xcrun simctl/devicectl, pymobiledevice3.

**Spec:** `docs/superpowers/specs/2026-11-09-device-takeover-uat-design.md`

**Prasyarat:** `skills/_shared/devices.md` dan `ios-runner/AgentRunnerUITests/RunnerTests.swift` punya perubahan user yang belum di-commit. Minta user meng-commit/menyimpannya dulu; jangan ikut meng-commit hunk user.

## Global Constraints
- Lokasi kunci: `${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}/<res ter-encode>` (encode `%`→`%25`, `/`→`%2F`, `:`→`%3A`), isi file `pid` dan `owner`. Kunci dengan pid mati = bebas.
- Catatan ambil alih: `${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/preempted/device-<pid pemilik lama>`, satu baris per device: `<res>\t<owner baru>\t<YYYY-MM-DD HH:MM>`.
- Resource device: `android:<serial>`, `ios:<udid>`. Owner slot UAT: `human-<KODE>`.
- "Diri sendiri" = pid di kunci/catatan adalah `$$` guard atau salah satu leluhurnya (maks. 8 tingkat, seperti deteksi audit di `guard.sh`).
- `UAT_IDLE_SEC` default `180` (3 menit), dihitung sejak serah terima, diulang tiap baris log app.
- Pesan ke agen dalam bahasa Indonesia, diawali `DIBLOKIR oleh guard:` (fungsi `block` yang ada).
- Tes: `tests/<nama>_test.sh` memakai `tests/lib.sh` (`assert_eq`, `assert_exit`), dijalankan `tests/run.sh`. Stub perintah lewat env (`ADB`, `XCRUN`, `PMD3`).
- README wajib menyebut tiap skrip baru di `bin/` (`tests/readme_test.sh`).

## Review Focus
1. Perintah tanpa `-s` saat dua device tersambung → blokir minta `-s` (bukan menebak device). Tes di Task 3.
2. `xcrun simctl uninstall booted <bundle>` → blokir minta udid eksplisit. Tes di Task 3.
3. Agen pemegang kunci menulis serial lewat `ANDROID_SERIAL=<s> adb uninstall …` → harus dikenali sebagai target. Tes di Task 3.
4. Slot UAT yang dilepas SPV (user bilang selesai) saat watcher masih jalan → watcher berhenti sendiri, tidak melepas kunci milik orang lain. Tes di Task 4.
5. Take saat pemegang lama sedang menjalankan Maestro di device **lain** → proses itu tidak ikut dihentikan. Tes di Task 2.

---

### Task 1: `device-lock.sh move`

**Files:**
- Modify: `bin/device-lock.sh`
- Test: `tests/device_test.sh` (bagian `# --- locks ---`)

**Interfaces:**
- Produces: `device-lock.sh move <res> <from-owner> <to-owner>` → exit 0 bila owner saat ini = `from` (owner jadi `to`, pid jadi `${AGENT_LOCK_PID:-$PPID}`), exit 1 bila bukan (cetak owner saat ini). Tanpa jeda kunci kosong.

- [ ] **Step 1: Tulis tes gagal** di `tests/device_test.sh` setelah blok `stale pid reclaimed`:
```bash
"$L" acquire dev:m A
assert_exit 1 "move: from salah ditolak" -- "$L" move dev:m B C
assert_exit 0 "move: A -> human-X" -- env AGENT_LOCK_PID=$$ "$L" move dev:m A human-X
assert_eq "human-X" "$("$L" who dev:m)" "move: owner baru"
assert_exit 1 "move: kunci bebas -> 1" -- "$L" move dev:none A B
"$L" release dev:m human-X
```
- [ ] **Step 2:** `bash tests/device_test.sh` → FAIL (`usage`, exit 2).
- [ ] **Step 3:** Tambah cabang `move)` di `case $cmd`: `[ "$(cur)" = "$owner" ]` (arg ke-3 = from) lalu tulis pid dulu, kemudian `owner` = arg ke-4; selain itu `cur; exit 1`. Perbarui baris `Usage` dan pesan usage.
- [ ] **Step 4:** `bash tests/device_test.sh` → semua `ok`.
- [ ] **Step 5:** `git commit -m "feat(device): device-lock move untuk serah terima kunci tanpa jeda"`

### Task 2: `bin/device-preempt.sh`

**Files:**
- Create: `bin/device-preempt.sh` (pola dan helper `tree`/`gone`/`wait_gone` seperti `bin/build-preempt.sh`)
- Test: `tests/device_preempt_test.sh` (pola stub `holder` dari `tests/build_preempt_test.sh`)

**Interfaces:**
- Consumes: `device-lock.sh who|acquire|move` (Task 1).
- Produces:
  - `device-preempt.sh info <res>` → stdout `owner=<o> since=<n>m testing=yes|no`; exit 1 bila bebas.
  - `device-preempt.sh take <res> <new-owner>` → exit 0 kunci milik kita; 1 keburu diambil pihak lain; 2 usage. Bebas → langsung acquire. Dipegang orang lain → hentikan proses uji pemilik lama untuk device itu (INT → TERM → KILL, `PREEMPT_TIMEOUT` detik, default 30), tulis catatan (Global Constraints) ke `device-<pid lama>` (append, satu baris per res, ganti baris res yang sama), lalu `move`.
  - "Proses uji untuk device itu" = di pohon pid pemilik lama, command cocok `maestro|am instrument|xcodebuild.*test|ios-ui\.sh` **dan** memuat id device. Owner `human-*` → tidak menghentikan apa pun.

- [ ] **Step 1: Tulis tes gagal** (stub `maestro` yang loop sampai INT, seperti stub di `build_preempt_test.sh`):
  - `assert_exit 2` tanpa argumen; `info` pada device bebas → exit 1.
  - take saat bebas → exit 0, `who android:EMU1` = owner baru.
  - holder menjalankan `maestro --device EMU1 test f.yaml`, kunci `android:EMU1` milik `PROJ-1-qa1` dengan pid holder → `info` memuat `owner=PROJ-1-qa1` dan `testing=yes`; `take android:EMU1 PROJ-2-qa1` exit 0; owner = `PROJ-2-qa1`; proses maestro mati; file `$AGENT_WORKFLOW_STATE/preempted/device-<pid holder>` berisi baris diawali `android:EMU1<TAB>PROJ-2-qa1`.
  - (Review Focus 5) holder menjalankan `maestro --device OTHER test f.yaml` dan memegang `android:EMU1` → take EMU1 → proses maestro OTHER tetap hidup.
  - holder memegang `android:PHY1` sebagai `human-PROJ-3` → take exit 0, catatan tertulis, tidak ada proses dihentikan.
- [ ] **Step 2:** `bash tests/device_preempt_test.sh` → FAIL (file tidak ada).
- [ ] **Step 3:** Implementasi sesuai Interfaces. Komentar header gaya `build-preempt.sh` (usage + exit code). `shortcut:` bila helper disalin dari `build-preempt.sh`.
- [ ] **Step 4:** tes → semua `ok`.
- [ ] **Step 5:** `git commit -m "feat(device): device-preempt info/take untuk ambil alih device atas izin user"`

### Task 3: guard — izin pasang/hapus app dan blokir agen yang diambil alih

**Files:**
- Modify: `hooks/guard.sh` (fungsi baru `check_device`, dipanggil dari `check_Bash`)
- Test: `tests/guard_device_test.sh` (gaya `run()` dari `tests/guard_scope_test.sh`)

**Interfaces:**
- Consumes: format kunci dan catatan (Global Constraints); `ADB`/`XCRUN` env untuk stub (`${ADB:-adb}`).
- Produces: perilaku guard berikut (tidak ada fungsi publik).

Aturan:
1. **Perintah mutasi** (dari token per segmen yang sudah ada di `check_Bash`): `adb … uninstall`, `adb … install|install-multiple`, `adb … shell pm clear`, `android install`, `xcrun simctl install|uninstall <udid>`, `xcrun devicectl device install|uninstall app … --device|-d <udid>`.
   Target: `adb -s <s>` / `android … --device <s>` / token `ANDROID_SERIAL=<s>` sebelum `adb` di segmen yang sama; tidak tertulis → `"$ADB" devices` (baris status `device`): tepat satu → itu, selain itu blokir "tulis -s <serial>". simctl `booted` → blokir "tulis udid".
   Kunci target ada + pid hidup + pid bukan diri sendiri → blokir: "device <res> dikunci <owner>. Tunggu atau tanya user untuk ambil alih (devices.md → Device dipakai)." Tidak dikunci / dikunci diri sendiri → lolos.
2. **Catatan ambil alih:** untuk tiap leluhur `p`, bila `preempted/device-<p>` ada: tiap baris `<res>`, id = `${res#*:}`. Kunci `res` sekarang milik `p` → hapus baris itu (sudah dikunci ulang). Selain itu, bila teks perintah Bash memuat id itu → blokir: "device <res> diambil alih oleh <owner baru> pada <waktu>: berhenti, antre dengan device-pick, ulangi uji dari awal (uji terhenti ini bukan kegagalan tiket)." File kosong → hapus.
3. Pemeriksaan hanya jalan bila segmen memuat `adb`, `xcrun`, `android`, `maestro`, atau `ios-ui.sh` (supaya Bash biasa tidak membayar `ps`/`adb devices`).

- [ ] **Step 1: Tulis tes gagal.** Pemilik "lain" = `sleep 60 &` (hidup, bukan leluhur); "diri sendiri" = `$$` skrip tes (guard dijalankan sebagai turunannya). Stub `adb devices` lewat `ADB="$T/adb"` yang membaca `$T/adb.out`. Kasus (exit diharapkan):
  - 0 `adb -s EMU1 uninstall com.x` (tidak dikunci)
  - 0 sama, kunci `android:EMU1` pid `$$`
  - 2 sama, kunci pid sleep; stderr memuat owner
  - 2 `adb -s EMU1 shell pm clear com.x` dan `adb -s EMU1 install -r a.apk` (kunci lain)
  - 2 `ANDROID_SERIAL=EMU1 adb uninstall com.x` (kunci lain) — Review Focus 3
  - 2 `adb uninstall com.x` dengan dua device di `adb.out` — Review Focus 1; 0 bila satu device dan tidak dikunci
  - 2 `xcrun simctl uninstall booted com.x` — Review Focus 2; 2 `xcrun simctl uninstall U1 com.x` dengan `ios:U1` dikunci lain; 2 `xcrun devicectl device uninstall app --device U1 com.x` (sama)
  - 0 `adb -s EMU1 shell input tap 1 1` dengan kunci lain (bukan mutasi, tanpa catatan)
  - catatan `device-$$` berisi `android:EMU1<TAB>PROJ-2-qa1<TAB>…`, kunci milik pid sleep → 2 `maestro --device EMU1 test f.yaml`, 2 `adb -s EMU1 shell input tap 1 1`, 0 `adb -s EMU2 shell input tap 1 1`
  - kunci `android:EMU1` lalu jadi milik `$$` → 0, dan baris catatan terhapus
  - 0 `ls -la` (tidak tersentuh)
- [ ] **Step 2:** `bash tests/guard_device_test.sh` → FAIL.
- [ ] **Step 3:** Implementasi `check_device` + panggilan dari `check_Bash` (aturan 1 per segmen; aturan 2 sekali per perintah memakai `input` mentah). Satu helper `ancestors` (daftar pid `$$` ke atas, 8 tingkat) dipakai juga oleh blok audit yang sudah ada bila bisa tanpa mengubah perilakunya; bila tidak, biarkan blok audit apa adanya.
- [ ] **Step 4:** `bash tests/run.sh` → `ALL PASS` (guard test lain tidak boleh rusak).
- [ ] **Step 5:** `git commit -m "feat(guard): uninstall/pm clear/install hanya di device milik sendiri; agen yang diambil alih berhenti"`

### Task 4: `bin/uat-watch.sh`

**Files:**
- Create: `bin/uat-watch.sh`
- Test: `tests/uat_watch_test.sh`

**Interfaces:**
- Consumes: `device-lock.sh who|release` (Task 1).
- Produces: `uat-watch.sh <res> <app> <owner> <outdir>` — `<app>` = package Android atau nama proses iOS (CFBundleExecutable). Berjalan sampai selesai lalu cetak satu baris `end=idle|released crash=<n> log=<outdir>/uat-log.txt`, exit 0; usage → exit 2.
  - Sumber log: `UAT_LOG_CMD` (string, dijalankan `sh -c`, untuk tes) atau bawaan: Android `"$ADB" -s <s> logcat -T 1 -v threadtime --uid=<uid>` dengan uid dari `"$ADB" -s <s> shell pm list packages -U <app>`; iOS `"$PMD3" syslog live --udid <u> -pn <app>` (`PMD3` default `pymobiledevice3`).
  - Tiap baris → `uat-log.txt`; baris cocok `FATAL EXCEPTION|ANR in|Fatal signal|Terminating app due to|EXC_BAD|SIGABRT|Fatal error` → juga `uat-crash.txt`.
  - Loop `read -t 1`: owner `res` ≠ `<owner>` → `end=released` (tidak menyentuh kunci); tidak ada baris selama `UAT_IDLE_SEC` (default 180) sejak start/baris terakhir → `device-lock.sh release <res> <owner>`, `end=idle`. Selalu matikan proses log saat keluar.
  - `shortcut:` ANR yang dicatat system_server (uid lain) tidak tertangkap `--uid`; upgrade dengan logcat penuh + filter pid bila ANR sering terlewat.

- [ ] **Step 1: Tulis tes gagal** (`UAT_IDLE_SEC=2`, kunci `android:PHY1` milik `human-PROJ-1` pid `$$`):
  - `UAT_LOG_CMD='echo a; sleep 1; echo "E AndroidRuntime: FATAL EXCEPTION: main"; sleep 30'` → output memuat `end=idle crash=1`; `who android:PHY1` kosong; `uat-crash.txt` memuat `FATAL EXCEPTION`; `uat-log.txt` 2 baris.
  - (Review Focus 4) log `sleep 30`, setelah 1 detik tes melepas kunci lalu `acquire` sebagai `PROJ-9-qa1` → output `end=released`; owner tetap `PROJ-9-qa1`.
  - log yang terus mencetak tiap 1 detik selama 4 detik lalu diam → total durasi ≥ 5 detik (idle diulang tiap baris).
  - tanpa argumen → exit 2.
- [ ] **Step 2:** `bash tests/uat_watch_test.sh` → FAIL.
- [ ] **Step 3:** Implementasi sesuai Interfaces.
- [ ] **Step 4:** tes → `ok`; `bash tests/run.sh` → `ALL PASS`.
- [ ] **Step 5:** `git commit -m "feat(uat): uat-watch pantau log app selama slot UAT dan lepas setelah idle"`

### Task 5: `install.sh` mencabut soft_deny adb

**Files:**
- Modify: `install.sh` (filter jq yang sudah ada)
- Test: `tests/install_test.sh`

**Interfaces:** — 

- [ ] **Step 1: Tulis tes gagal:** settings awal `{"autoMode":{"soft_deny":["$defaults","Bash(adb:* uninstall *)","Bash(adb:* shell pm clear *)","Bash(x)"]}}` → setelah `install.sh --home "$T"`: `jq -c .autoMode.soft_deny` = `["$defaults","Bash(x)"]`. Settings tanpa `autoMode` → tidak muncul `autoMode`.
- [ ] **Step 2:** `bash tests/install_test.sh` → FAIL.
- [ ] **Step 3:** Di filter jq: `| if .autoMode.soft_deny then .autoMode.soft_deny |= map(select(test("^Bash\\(adb:\\* (uninstall|shell pm clear) \\*\\)$") | not)) else . end` (alasan satu baris: izin kini dijaga guard terhadap kunci device).
- [ ] **Step 4:** tes → `ok`.
- [ ] **Step 5:** `git commit -m "feat(install): cabut soft_deny adb uninstall/pm clear, kini dijaga guard"`
- [ ] **Step 6:** Minta **user** menjalankan `! ~/agent-workflow/install.sh` (auto mode menolak agen mengubah aturannya sendiri), lalu buka ulang sesi.

### Task 6: Dokumen alur (`devices.md`, `develop-tiket`, `spv.md`, `qa.md`, README)

**Files:**
- Modify: `skills/_shared/devices.md`, `skills/develop-tiket/SKILL.md`, `agents/spv.md`, `agents/qa.md`, `README.md`

**Interfaces:**
- Consumes: semua perintah Task 1–4 persis seperti di blok Interfaces-nya.

- [ ] **Step 1: `devices.md`** — bagian baru **"Device dipakai"** setelah "Ambil dan lepas device", meniru "Kunci dipakai" di Build berat:
  - `device-pick.sh` exit 1 → cek pemilik tiap device yang cocok (`device-lock.sh who`). Pemilik dari batch/rilis yang sama → antre tiap 30 detik. Pemilik tiket Jira lain atau `human-*` → **tanya user** (juga mode otonom; teammate lewat SPV): "Device <res> dipakai **<KODE> — <judul>** (<sudah n menit>, sedang uji: ya/tidak). Tugas kita: **<KODE> — <judul>**. Tunggu atau ambil alih?" Untuk `human-*`: "sedang dipakai Anda untuk UAT <KODE>".
  - **Ambil alih** → `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-preempt.sh" take <res> <owner kita>` (exit 0 milik kita, 1 ulangi dari awal). Tidak pernah tanpa pilihan user.
  - **Uji kita terhenti / guard bilang "diambil alih"**: bukan kegagalan tiket; antre lagi lewat `device-pick`, ulangi uji dari awal, laporan menyebut "uji sempat didahulukan untuk <KODE>".
  - **Uninstall / `pm clear` / install** boleh tanpa bertanya di device yang kamu kunci sendiri (atau yang tidak dikunci siapa pun); guard menolak bila dikunci pihak lain. Selalu tulis `-s <serial>` / udid.
  - Bagian **"Slot UAT (`--uat`)"**: serah terima `device-lock.sh move <res> <KODE>-qa<n> human-<KODE>`, `uat-watch.sh` di background, selesai saat user bilang selesai (SPV `release` kunci) atau 3 menit tanpa log.
- [ ] **Step 2: `develop-tiket/SKILL.md`** — `argument-hint` dan `description` jadi `KODE... [--solo|--tim] [--batch|--separate] [--uat]`; paragraf flag `--uat`; langkah baru **8b. UAT (`--uat`)** setelah QA lulus dan sebelum langkah 10:
  1. SPV menugaskan QA run `device-pick.sh <plat> <KODE>-qa<n> --physical`, QA memasang build dev yang diuji lalu lapor **tanpa melepas kunci**.
  2. SPV: `AGENT_LOCK_PID=$PPID device-lock.sh move <res> <KODE>-qa<n> human-<KODE>`; beri tahu user di chat (device, app, build, "bilang *selesai UAT* bila sudah").
  3. SPV jalankan `uat-watch.sh <res> <app> human-<KODE> ${TMPDIR:-/tmp}/qa/<KODE>/uat` di background (run_in_background).
  4. User bilang selesai → `device-lock.sh release <res> human-<KODE>` (watcher berhenti sendiri). Watcher `end=idle` → slot sudah lepas.
  5. `crash=0` → lanjut langkah 10; crash → potongan `uat-crash.txt` masuk laporan uji, tiket kembali ke langkah 5 (Coder → Reviewer → QA → UAT lagi).
  - `--batch`: satu slot untuk build batch, owner `human-<KODE pertama>`; `--separate`: per tiket. Tanpa `--uat` tidak ada slot manusia. Tambah node UAT di flowchart antara QA dan Laporan.
  - "Berhenti lebih awal": lepas juga `human-<KODE>`.
- [ ] **Step 3: `agents/spv.md`** — butir alur: dengan `--uat`, SPV memegang slot `human-<KODE>` dan menjalankan `uat-watch.sh` (langkah 8b). **`agents/qa.md`** — butir 6: kecuali tugas "siapkan UAT" dari SPV, kunci device tidak dilepas (SPV yang memindahkannya).
- [ ] **Step 4: `README.md`** — tabel skrip: baris `device-preempt.sh` (info/take, contoh `bin/device-preempt.sh info android:<serial>`) dan `uat-watch.sh`; bagian `/develop-tiket`: flag `--uat`; "Pagar keamanan": uninstall/pm clear/install hanya di device milik sendiri, agen yang diambil alih diblokir.
- [ ] **Step 5:** `bash tests/run.sh` → `ALL PASS` (termasuk `readme_test.sh`, `agents_test.sh`).
- [ ] **Step 6:** `git commit -m "docs(device): ambil alih device, izin uninstall, dan slot UAT --uat"`
