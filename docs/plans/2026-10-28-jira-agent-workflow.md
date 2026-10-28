# Jira Agent Workflow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pasang `/validate-tiket`, `/develop-tiket`, `/rilis-tiket`, tim agen, pagar keamanan, dan pembersihan berkala di Claude Code + Orca pada Mac ini.

**Architecture:** Semua sumber ada di repo `~/agent-workflow`; `install.sh` membuat symlink ke `~/.claude/skills`, `~/.claude/agents`, memasang hook pagar di `~/.claude/settings.json`, dan memuat satu job launchd. Skill (markdown) mengatur alur; logika yang harus pasti (pagar, kunci device, nomor build, manifest, anotasi screenshot, pembersihan) ada di skrip kecil yang dites. Multi-agent dan worktree bertingkat memakai Orca CLI (`orca worktree create --parent-worktree`, `orca orchestration worker-start --worktree new-child --model`, `orca orchestration gate-create`).

**Tech Stack:** bash + jq (skrip & tes), Python 3 via `uv run --with pillow` (anotasi), Claude Code skills/agents/hooks, Orca CLI, Atlassian MCP, Claude Docs MCP, gh/glab, Maestro, Schemathesis, Pact, Firebase CLI, xcodebuild, launchd.

**Spec:** Claude Docs https://claude.ai/artifact/EA7oF3JpM3ahrmgPakUfzV · salinan lokal `docs/design-summary.md`

## Global Constraints

- Agen tidak pernah: push ke remote selain `origin` (downstream); force-push ke `master`/`main`/`develop`; `rm -rf` di luar folder project; pindah tiket Jira ke Done; mengubah file di worktree primary (`isMainWorktree`).
- Selalu berhenti & tanya (Orca gate bila di Orca, selain itu tanya di chat): upload prod; sebelum buat branch rilis/hotfix; nomor build tidak jelas; kredensial tidak ditemukan; dua fix hotfix bentrok.
- Model: SPV/Validator/Reviewer = opus (`claude-opus-5-5`), Coder/QA = sonnet (`claude-sonnet-5-5`), Release = haiku (`claude-haiku-5-5`). Housekeeping = skrip shell, tanpa model.
- Branch prefix: `feature/` `fix/` `hotfix/` `docs/` `chore/`; branch rilis `release/vX.Y.Z`, `hotfix/vX.Y.Z`. Judul tiket rilis: `[release-request] …`, `[hotfix-release] …`.
- Nomor build: dev = angka tiket (`PROJ-1234` → `1234`; batch = tiket pertama); beta/prod = terakhir + 1.
- Device: fisik dulu; maks 3 device virtual menyala bersamaan; satu device / satu akun uji = satu agen.
- Kredensial dari `local.properties` (`qa.*`) / `qa.local.properties` / `.env*.local` / `*.xcconfig` gitignored; isi tidak pernah ditulis ke Docs/Jira/MR.
- Laporan: Claude Docs, gaya singkat, tabel + mermaid, bahasa ramah pemula, Bahasa Indonesia; link laporan di baris pertama komentar Jira.
- Pembersihan: harian ≥03:00, mingguan Minggu ≥03:30, darurat disk kosong < 50 GB; tunda bila build/upload/device sedang dipakai.

## Review Focus

1. Perintah `git push` yang menyamarkan remote (`git push https://…upstream…`, `git -C dir push upstream`, `git push origin +master`) — pagar harus tetap menolak.
2. `/develop-tiket` dijalankan di worktree primary atau folder non-Orca — harus berhenti dengan pesan jelas, bukan mulai mengedit.
3. Kunci device/akun basi setelah agen crash — kunci dengan PID mati harus bisa diambil ulang.
4. Sumber nomor build saling beda atau kosong — skrip harus keluar dengan kode "tanya user", bukan memilih diam-diam.
5. Pembersihan saat Xcode/Gradle sedang build — harus ditunda, tidak menghapus DerivedData yang sedang dipakai.

Tes untuk kelimanya ada di Task 2, 3, 4, 6, 10.

---

## File Structure

```
agent-workflow/
  install.sh                      # symlink + hook + launchd (idempotent)
  tests/run.sh                    # jalankan semua tests/*_test.sh
  tests/lib.sh                    # assert_eq, assert_exit
  hooks/guard.sh                  # PreToolUse pagar (stdin JSON → exit 2 = blokir)
  bin/device-lock.sh              # acquire|release|who <resource>
  bin/device-pick.sh              # pilih device: fisik dulu, batas virtual 3
  bin/annotate.py                 # kotak merah + label dari JSON
  bin/build-number.sh             # dev <KEY> | next <n>...
  bin/manifest-check.sh           # bandingkan kunci tiket di git log vs manifest
  bin/housekeeping.sh             # pembersihan berkala
  launchd/com.agentworkflow.housekeeping.plist
  agents/{spv,validator,reviewer,release,coder,qa}.md
  skills/validate-tiket/SKILL.md
  skills/develop-tiket/SKILL.md
  skills/rilis-tiket/SKILL.md
  skills/_shared/{rules,report-format,devices,credentials,build-release}.md
  templates/qa.local.properties
  config/jira-transitions.json    # id transisi yang boleh dipakai, per project Jira
```

---

### Task 1: Kerangka repo, harness tes, installer

**Files:**
- Create: `install.sh`, `tests/run.sh`, `tests/lib.sh`, `tests/install_test.sh`, `.gitignore`

**Interfaces:**
- Produces: `tests/lib.sh` → `assert_eq <expected> <actual> <msg>`, `assert_exit <code> <msg> -- <cmd...>`; `tests/run.sh` exit 0 bila semua lulus.
- Produces: `install.sh [--home DIR]` (default `$HOME`): symlink `skills/*` (kecuali `_shared`) ke `DIR/.claude/skills/`, `skills/_shared` ke `DIR/.claude/skills/_agent-workflow-shared`, `agents/*.md` ke `DIR/.claude/agents/`; tambah ke `DIR/.claude/settings.json` hook `PreToolUse` matcher `Bash|Edit|Write|MultiEdit|mcp__claude_ai_Atlassian__transitionJiraIssue` → `~/agent-workflow/hooks/guard.sh` (tidak duplikat bila dijalankan ulang); salin plist ke `DIR/Library/LaunchAgents/` dan `launchctl bootstrap` hanya bila `--home` tidak diberikan.

- [ ] **Step 1:** Tulis `tests/install_test.sh`: buat `HOME` sementara berisi `.claude/settings.json` = `{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}`; jalankan `install.sh --home $tmp` dua kali; assert: symlink `skills/validate-tiket` ada, `jq '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))]|length'` = `1`, hook `rtk hook claude` masih ada.
- [ ] **Step 2:** `bash tests/run.sh` → FAIL (install.sh belum ada).
- [ ] **Step 3:** Implement `tests/lib.sh`, `tests/run.sh`, `install.sh` (jq untuk merge; backup `settings.json.bak-agent-workflow` sebelum tulis). Buat folder kosong yang dirujuk (skills/validate-tiket dsb. dengan SKILL.md placeholder satu baris) agar symlink bisa dites.
- [ ] **Step 4:** `bash tests/run.sh` → PASS.
- [ ] **Step 5:** `git add -A && git commit -m "chore: repo scaffold, test harness, installer"`

### Task 2: Pagar — git push & rm -rf

**Files:**
- Create: `hooks/guard.sh`, `tests/guard_git_test.sh`

**Interfaces:**
- Produces: `hooks/guard.sh` membaca JSON hook Claude Code dari stdin (`.tool_name`, `.tool_input`, `.cwd`); exit 0 = izinkan; exit 2 + pesan Bahasa Indonesia di stderr = blokir. Task 3 menambah aturan ke file yang sama.

- [ ] **Step 1:** Tulis tes tabel (input `tool_input.command` → exit yang diharapkan), cwd = repo git sementara dengan remote `origin` dan `upstream`:
  - `git push origin fix/PROJ-1` → 0
  - `git push upstream fix/PROJ-1` → 2
  - `git -C /x push upstream main` → 2
  - `git push https://example.com/up.git main` → 2 (URL ≠ url `origin`)
  - `git push` (tanpa argumen, upstream tracking ke `upstream`) → 2; tracking ke `origin` → 0
  - `git push --force origin main` → 2; `git push origin +develop` → 2; `git push -f origin fix/x` → 0
  - `git push upstream --delete fix/x` / `git push upstream --tags` → 2
  - `rm -rf ./build` → 0; `rm -rf ~/Library` (cwd di repo) → 2; `rm -rf ~` → 2; `rm -fr ../other` → 2
  - `echo ok && git push upstream main` (perintah berantai) → 2
- [ ] **Step 2:** Jalankan → FAIL.
- [ ] **Step 3:** Implement: pecah perintah pada `&&`, `||`, `;`, `|`; untuk tiap segmen `git … push …` tentukan remote (argumen non-flag pertama setelah `push`, atau `branch.<cur>.remote`); izinkan hanya bila remote = `origin` atau URL = `git remote get-url origin`; cek force (`-f`, `--force*`, refspec `+`) ke `main|master|develop`. `rm` dengan `-r`/`-R` dan `-f`: resolve tiap path (`realpath -m` via python bila perlu); blokir bila di luar `git rev-parse --show-toplevel` dari cwd (atau cwd bila bukan repo).
- [ ] **Step 4:** Jalankan → PASS.
- [ ] **Step 5:** Commit `feat: guard hook blocks upstream push, protected force-push, rm outside project`

### Task 3: Pagar — worktree primary & transisi Jira

**Files:**
- Modify: `hooks/guard.sh`
- Create: `config/jira-transitions.json` (`{}`), `tests/guard_scope_test.sh`

**Interfaces:**
- Consumes: `guard.sh` dari Task 2.
- Produces: `config/jira-transitions.json` format `{"PROJ": {"allow": ["21","31"], "names": {"21":"In Progress","31":"Ready To Review"}}}`; skill menulis file ini setelah user konfirmasi (lihat Task 7).

- [ ] **Step 1:** Tes:
  - `Edit` dengan `file_path` di repo main worktree → 2; di linked worktree (`git worktree add`) → 0; file di luar repo git → 0.
  - `Bash` `sed -i … file` / `> file` di main worktree → 0 (shortcut: hanya Edit/Write/MultiEdit yang dicek, upgrade bila agen ketahuan menulis lewat shell).
  - `transitionJiraIssue` `{"issueIdOrKey":"PROJ-5","transition":{"id":"21"}}` dengan config di atas → 0; id `41` → 2 dengan pesan menyebut "Done hanya dipindah kolega"; project tanpa entri → 2 dengan pesan "jalankan setup transisi".
- [ ] **Step 2:** Jalankan → FAIL.
- [ ] **Step 3:** Implement: main worktree = `git -C <dir> rev-parse --git-dir` sama dengan `--git-common-dir` (absolut). Path config dibaca dari `${AGENT_WORKFLOW_DIR:-$HOME/agent-workflow}/config/jira-transitions.json`.
- [ ] **Step 4:** Jalankan semua tes → PASS.
- [ ] **Step 5:** Commit `feat: guard primary worktree edits and Jira transitions`

### Task 4: Kunci & pemilihan device

**Files:**
- Create: `bin/device-lock.sh`, `bin/device-pick.sh`, `tests/device_test.sh`

**Interfaces:**
- Produces: `device-lock.sh acquire <resource> <owner>` → exit 0 dapat, 1 dipakai (stdout: owner sekarang); `release <resource> <owner>`; `who <resource>`. Resource = `ios:<udid>`, `android:<serial>`, `account:<project>:<user>`. Kunci di `${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}` (mkdir atomik + file `pid`, `owner`). Kunci dengan PID mati dianggap kosong.
- Produces: `device-pick.sh <ios|android> <owner>` → stdout resource yang sudah di-acquire; exit 1 bila tidak ada (QA menandai TC "Tertahan"). Urutan: fisik terhubung (`adb devices` state `device`; `xcrun devicectl list devices` state `connected`) → device virtual yang sudah menyala → boot virtual baru bila jumlah virtual menyala < 3. Perintah device bisa diganti lewat env `ADB`, `XCRUN` (untuk tes).

- [ ] **Step 1:** Tes: acquire dua kali owner beda → kedua exit 1 dengan owner pertama; release → acquire berhasil; kunci dengan pid `999999` → acquire berhasil (Review Focus 3). Pick dengan stub `ADB` yang mencetak satu device `unauthorized` + stub emulator → memilih virtual; stub dengan device fisik `device` → memilih fisik; stub dengan 3 virtual menyala semua terkunci → exit 1.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: device and test-account locking, physical-first picker`

### Task 5: Anotasi screenshot

**Files:**
- Create: `bin/annotate.py`, `tests/annotate_test.sh`

**Interfaces:**
- Produces: `uv run --with pillow python -I bin/annotate.py <in.png> <boxes.json> <out.png>`; `boxes.json` = `[{"x":20,"y":240,"w":885,"h":125,"label":"AC2 inisial BR, tanpa deskripsi"}]` dalam piksel gambar asli. Gaya: garis merah `#E02020` tebal 6 px; label teks putih tebal di latar merah, menempel di atas kotak (di bawah bila tidak muat di atas). Koordinat diambil agen dari `maestro hierarchy` (Android/iOS) — bukan ditebak.

- [ ] **Step 1:** Tes: gambar 400×800 abu-abu, satu kotak → piksel di tepi kotak merah, piksel di tengah kotak tidak berubah, area label di atas kotak ada piksel putih; kotak di y=0 → label pindah ke bawah kotak.
- [ ] **Step 2:** FAIL. **Step 3:** Implement (font: `/System/Library/Fonts/Supplemental/Arial Bold.ttf`, ukuran = 3% lebar gambar). **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: screenshot annotation`

### Task 6: Nomor build & cek manifest

**Files:**
- Create: `bin/build-number.sh`, `bin/manifest-check.sh`, `tests/build_manifest_test.sh`

**Interfaces:**
- Produces: `build-number.sh dev PROJ-1234 [PROJ-1240…]` → `1234` (tiket pertama). `build-number.sh next <src=n>...` (mis. `asc=57 tag=57 project=56`) → bila semua sumber yang terisi sama: cetak n+1, exit 0; bila beda atau kosong semua: cetak ringkasan sumber + saran `max+1`, exit 3 (= tanya user).
- Produces: `manifest-check.sh <base-ref> <head-ref> <KEY>...` → ambil kunci `[A-Z][A-Z0-9]+-[0-9]+` dari `git log base..head`; exit 0 bila himpunan sama; exit 1 dengan dua daftar "di branch tapi tidak di manifest" / "di manifest tapi tidak di branch".

- [ ] **Step 1:** Tes: `dev PROJ-1234 PROJ-1240` → `1234`; `next asc=57 tag=57` → `58` exit 0; `next asc=57 project=56` → exit 3, stdout memuat `58`; `next` tanpa nilai → exit 3. Manifest: repo sementara dengan commit `PROJ-1 fix`, `PROJ-2 feat` → `manifest-check base head PROJ-1 PROJ-2` exit 0; dengan `PROJ-1` saja → exit 1 menyebut `PROJ-2`.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: build-number and release manifest checks`

### Task 7: Aturan bersama & definisi agen

**Files:**
- Create: `skills/_shared/rules.md`, `devices.md`, `credentials.md`, `build-release.md`, `report-format.md`; `agents/{spv,validator,reviewer,release,coder,qa}.md`; `templates/qa.local.properties`; `tests/agents_test.sh`

**Interfaces:**
- Produces: agen dengan frontmatter `name`, `description`, `model` (`opus`/`sonnet`/`haiku` sesuai Global Constraints), `tools` (Coder/QA tanpa tool Atlassian & Claude Docs). Isi tiap agen: kewajiban + "Tidak boleh" persis tabel Tim agen di spec, dan merujuk file `_shared` yang relevan.
- Produces: `rules.md` — mode diawasi/otonom, daftar blokir & daftar "berhenti dan tanya", cara tanya: di Orca `orca orchestration gate-create`, selain itu tanya di chat; aturan "periksa dulu lalu tanya, catat jawaban di `CLAUDE.md` project"; setup transisi Jira (ambil `getTransitionsForJiraIssue`, tunjukkan nama → user pilih id untuk In Progress & Ready To Review → tulis `config/jira-transitions.json`).
- Produces: `devices.md` (pakai `device-lock.sh`/`device-pick.sh`, maks 3 virtual, Maestro untuk aksi & `maestro hierarchy` untuk bounds), `credentials.md` (urutan cari, template, cek `.gitignore` dulu, data uji awalan kode tiket di dev/staging saja), `build-release.md` (build-number.sh, sumber nomor, `.dev` ID terpisah, upload Firebase/TestFlight via `xcodebuild -exportArchive` + upload, prod = gate), `report-format.md` (struktur laporan validasi & laporan uji, contoh laporan validasi yang sudah dipakai user, gaya kotak merah, komentar Jira link di baris pertama).

- [ ] **Step 1:** Tes `agents_test.sh`: setiap `agents/*.md` punya frontmatter dengan `model` yang sesuai peta; coder & qa tidak memuat `mcp__claude_ai_Atlassian` di `tools`; setiap rujukan `_shared/*.md` di file agen/skill benar-benar ada.
- [ ] **Step 2:** FAIL. **Step 3:** Tulis file. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: shared rules and agent definitions`

### Task 8: Skill `/validate-tiket`

**Files:**
- Create: `skills/validate-tiket/SKILL.md`

**Interfaces:**
- Consumes: Task 4–7. Argumen: satu atau lebih kunci Jira. Boleh jalan di primary (tidak mengedit file repo).

- [ ] **Step 1:** Tulis SKILL.md: frontmatter `name: validate-tiket`, `description` (pemicu `/validate-tiket KODE…`), `argument-hint: KODE-TIKET...`. Alur per tiket = diagram `/validate-tiket` di spec: baca tiket+komentar+link (Atlassian MCP) → bug: tentukan versi dari tiket (kosong → build dev/beta terbaru), `device-pick.sh`, reproduksi via Maestro, screenshot tiap langkah, bounds dari `maestro hierarchy`, `annotate.py` → fitur: cek requirement & kesiapan API/desain → laporan Claude Docs (format `_shared/report-format.md`, upload screenshot) → komentar Jira (link baris pertama + keputusan: Layak / Layak dengan catatan / Tidak layak) → transisi ke In Progress bila layak. Beberapa tiket: proses berurutan; satu laporan per tiket; ringkasan akhir tabel kunci → keputusan → link.
- [ ] **Step 2:** Uji kering (mode diawasi) pada satu tiket nyata yang dipilih user; periksa: laporan sesuai format, screenshot berkotak tepat, komentar Jira link di baris pertama, transisi memakai id yang diizinkan.
- [ ] **Step 3:** Perbaiki SKILL.md dari temuan uji kering.
- [ ] **Step 4:** Commit `feat: /validate-tiket skill`

### Task 9: Skill `/develop-tiket`

**Files:**
- Create: `skills/develop-tiket/SKILL.md`

**Interfaces:**
- Consumes: Task 2–7; Orca CLI: `orca worktree current --json` (`isMainWorktree`), `orca worktree create --name <KEY> --parent-worktree current --base-branch <base> --reference <KEY>`, `orca orchestration run-create`, `task-create`, `worker-start --worktree new-child --agent claude --model <id>`, `gate-create`, `worker-read`.
- Argumen: kunci Jira…, opsional `--solo` / `--tim`.

- [ ] **Step 1:** Tulis SKILL.md: (0) tolak bila `isMainWorktree` true atau bukan worktree Orca — pesan: "Jalankan dari worktree domain"; (1) SPV baca requirement & tiket terkait/blocking; (2) dokumen rencana + test case di Claude Docs; ukuran → `--solo` (satu agen, langkah 2 catatan singkat) atau tim (Orca run: satu child worktree per tiket; child per coder hanya bila >1 coder; coder sonnet, QA sonnet, reviewer opus); (3) TDD di branch tiket; (4) review performa/crash; (5) gabung semua branch tiket ke branch batch lokal di worktree domain → satu build → QA per tiket (Maestro/Schemathesis/Pact; spec & kontrak dicari di repo, tidak ada → tanya) → laporan uji per tiket; (6) build dev (`build-number.sh dev` semua kunci batch) + beta (`build-number.sh next`, exit 3 → gate) + prod hanya via gate; build berat antre satu-satu; (7) push branch tiket ke `origin`, MR: tiket di-link ke tiket `[release-request]`/`[hotfix-release]` → target branch rilis di downstream, selain itu → upstream (gh/glab sesuai URL remote); (8) komentar Jira berisi semua link; (9) transisi ke Ready To Review.
- [ ] **Step 2:** Uji kering `--solo` pada satu tiket kecil di worktree domain; lalu uji kering dari primary → harus berhenti.
- [ ] **Step 3:** Uji kering `--tim` pada dua tiket satu domain; periksa child worktree dibuat di bawah domain, satu build, dua laporan.
- [ ] **Step 4:** Perbaiki dari temuan. **Step 5:** Commit `feat: /develop-tiket skill`

### Task 10: Pembersihan berkala

**Files:**
- Create: `bin/housekeeping.sh`, `launchd/com.agentworkflow.housekeeping.plist`, `tests/housekeeping_test.sh`
- Modify: `install.sh` (sudah memuat plist dari Task 1 — pastikan path benar)

**Interfaces:**
- Produces: `housekeeping.sh` dipanggil launchd tiap jam (`StartInterval` 3600). Memutuskan mode sendiri: `weekly` bila Minggu, jam ≥ 03:30, belum jalan minggu ini; `daily` bila jam ≥ 03:00, belum jalan hari ini; `emergency` (= daily) bila disk kosong < 50 GB; selain itu keluar. Stempel di `~/.agent-workflow/state/`. Tunda (keluar tanpa stempel) bila `pgrep -f 'xcodebuild|GradleDaemon|konan|appdistribution|altool'` ada atau ada kunci di folder locks. Override untuk tes: `HK_NOW` (epoch), `HK_FREE_GB`, `HK_BUSY` (0/1), `HOME`.
- Target sesuai tabel spec. Repo = main worktree dari `orca worktree list --json` (Orca tidak jalan → lewati langkah repo). Branch: hapus branch lokal & di `origin` yang sudah di-merge ke base upstream, kecuali `main|master|develop|release/*|hotfix/*` yang belum di-merge. Archives: hanya bundle ID yang tercantum di `~/.agent-workflow/archives-prune.txt`, > 30 hari, 3 terbaru per bundle ID selalu disimpan. Log `~/.agent-workflow/logs/housekeeping.log`; gagal atau disk masih < 50 GB → `osascript -e 'display notification …'`.

- [ ] **Step 1:** Tes dengan `HOME` sementara berisi DerivedData lama/baru (`touch -t`): `HK_NOW`=Senin 03:10 → daily menghapus DerivedData > 3 hari saja; jalan kedua di hari sama → tidak berbuat apa-apa; `HK_BUSY=1` → tidak menghapus & tidak menulis stempel (Review Focus 5); Minggu 03:40 → weekly menghapus semua DerivedData; Archives bundle tak terdaftar → tidak tersentuh; terdaftar dengan 5 archive tua → tersisa 3.
- [ ] **Step 2:** FAIL. **Step 3:** Implement + plist. **Step 4:** PASS; `plutil -lint launchd/*.plist` OK.
- [ ] **Step 5:** Commit `feat: periodic housekeeping`

### Task 11: Skill `/rilis-tiket`

**Files:**
- Create: `skills/rilis-tiket/SKILL.md`

**Interfaces:**
- Consumes: `manifest-check.sh`, `build-number.sh`, `_shared/build-release.md`, Orca gate.
- Argumen: kunci tiket rilis (judul `[release-request] …` / `[hotfix-release] …`), atau `baru release|hotfix` untuk membuat tiket rilis.

- [ ] **Step 1:** Tulis SKILL.md: buat/ambil tiket rilis; manifest = tiket ter-link; pemeriksaan kondisi repo (master vs develop vs versi live, fix yang belum di-merge balik) → laporkan + saran → gate (selalu, termasuk mode otonom) → catat jawaban di `CLAUDE.md` project; buat `release/vX.Y.Z` atau `hotfix/vX.Y.Z` di downstream (hotfix dari `master`/tag live, bukan `develop`); MR per tiket ke branch itu di downstream; `manifest-check.sh` (exit 1 → stop & lapor); build beta, prod via gate; satu MR ke upstream; komentar di tiket rilis; ingatkan maintainer membuat tag. Hotfix yang sudah di-build tidak ditambah.
- [ ] **Step 2:** Uji kering pada repo uji (fork sendiri) dengan dua tiket fix → periksa satu MR ke upstream dan manifest cocok; ulangi dengan tiket ekstra di branch → harus berhenti.
- [ ] **Step 3:** Perbaiki. **Step 4:** Commit `feat: /rilis-tiket skill`

### Task 12: Pasang & aturan global

**Files:**
- Modify: `~/.claude/CLAUDE.md` (tambah bagian "Jira agent workflow": rujuk `_agent-workflow-shared/rules.md`, worktree primary hanya audit, catat keputusan per project di `CLAUDE.md` project)

- [ ] **Step 1:** `bash tests/run.sh` → semua PASS.
- [ ] **Step 2:** `./install.sh`; verifikasi: `ls -l ~/.claude/skills/validate-tiket ~/.claude/agents/spv.md` adalah symlink; `jq '.hooks.PreToolUse' ~/.claude/settings.json` memuat guard + rtk; `launchctl print gui/$(id -u)/com.agentworkflow.housekeeping` aktif.
- [ ] **Step 3:** Uji pagar langsung di sesi Claude: minta `git push upstream x` di repo uji → ditolak dengan pesan Indonesia.
- [ ] **Step 4:** Tambah bagian CLAUDE.md global. Commit `docs: global rules for Jira agent workflow`.
