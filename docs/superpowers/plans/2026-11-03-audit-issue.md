# `/audit-issue` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skill `/audit-issue "<teks>" [--solo|--tim] [lampiran...]` yang mengaudit sebuah permintaan secara hanya-baca (dipaksa guard) dan menghasilkan satu laporan Claude Docs.

**Architecture:** Penanda mode audit (env `AGENT_AUDIT=1` untuk worker, file penanda per pid Claude lewat `bin/audit-mode.sh` untuk SPV) membuat `hooks/guard.sh` hanya mengizinkan baca. Skill baru + dua file peran (`auditor`, `analis`, semua Opus) memakai ulang `worker-pane.sh`, device lock, dan format laporan.

**Tech Stack:** bash, jq, python3 (sudah dipakai guard), Markdown skill/agent, tes bash `tests/*_test.sh` (`tests/lib.sh`: `assert_eq`, `assert_exit`).

**Spec:** `docs/superpowers/specs/2026-11-03-audit-issue-design.md`

## Global Constraints
- Semua peran audit memakai `claude-opus-5-5` (frontmatter `model: opus`; panel `--command "AGENT_AUDIT=1 claude --model claude-opus-5-5"`).
- Teks skill/agent/aturan dalam bahasa Indonesia, gaya file yang ada (ringkas, bullet). Pesan blokir guard diawali `DIBLOKIR oleh guard:` (fungsi `block`).
- Repo publik: tidak ada `/Users/` atau email di file yang di-track (`tests/agents_test.sh` memeriksa).
- Tidak mengubah perilaku `/develop-tiket`, `/validate-tiket`, `/rilis-tiket` di luar mode audit; `qa.md` dan tabel model yang ada tidak berubah.
- Folder kerja audit: `${TMPDIR:-/tmp}/audit/<slug>/`.
- Direktori state: `${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}` (pola `check_jira`).

## Review Focus
1. **Penanda SPV tertinggal** (audit berhenti tanpa `off`): sesi lain tidak boleh ikut terkunci → penanda hanya berlaku untuk pid leluhur guard yang masih hidup. Tes di Task 1 dan 2.
2. **Mode normal tidak berubah:** semua tes guard lama tetap lulus, dan tanpa penanda `git commit` tetap boleh. Tes di Task 2.
3. **Tulis lewat shell** (`sed -i`, `>` ke file repo) tidak tertangkap guard. Diterima sebagai batas, ditulis sebagai komentar `shortcut:` di guard dan di laporan cara-audit. Tidak dites.
4. **Path folder audit lewat symlink** (`/tmp` → `/private/tmp` di macOS): Write ke `/tmp/audit/x/a.md` harus boleh. Tes di Task 2.
5. **Git baca dengan opsi global** (`git -C <repo> log`, `git --no-pager show`) tetap boleh dalam mode audit. Tes di Task 2.

---

### Task 1: `bin/audit-mode.sh`

**Files:**
- Create: `bin/audit-mode.sh`
- Test: `tests/audit_mode_test.sh`

**Interfaces:**
- Produces: `audit-mode.sh on|off|status`. Penanda = file `${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/audit/<pid>`, pid = `${AGENT_LOCK_PID:-$PPID}`. `status` keluar 0 dan mencetak `on` bila penanda pid itu ada, selain itu keluar 1 dan mencetak `off`. `on` juga menghapus penanda yang pid-nya sudah mati (`kill -0`).

- [ ] **Step 1: Tulis tes yang gagal** (`tests/audit_mode_test.sh`, pola `tests/device_test.sh`, `AGENT_WORKFLOW_STATE=$(mktemp -d)`):
  - `AGENT_LOCK_PID=$$ audit-mode.sh on` → file `$STATE/audit/$$` ada; `status` exit 0, cetak `on`.
  - `off` → file hilang; `status` exit 1, cetak `off`.
  - Penanda basi: buat file `$STATE/audit/999999` (pid mati), jalankan `on` → file basi terhapus.
  - Argumen salah → exit 2.
  - Akhiri dengan `exit $FAILS`.
- [ ] **Step 2:** `bash tests/audit_mode_test.sh` → FAIL (skrip belum ada).
- [ ] **Step 3:** Tulis `bin/audit-mode.sh` (header usage seperti `device-lock.sh`), `chmod +x`.
- [ ] **Step 4:** `bash tests/audit_mode_test.sh` → semua `ok`.
- [ ] **Step 5:** Commit `feat(audit): audit-mode.sh marker per Claude pid`.

### Task 2: Mode audit di `hooks/guard.sh`

**Files:**
- Modify: `hooks/guard.sh`
- Test: `tests/guard_audit_test.sh` (baru)

**Interfaces:**
- Consumes: penanda dari Task 1 (`$STATE/audit/<pid>`).
- Produces: variabel `AUDIT` (non-kosong = mode audit), dihitung sekali setelah `cwd` diisi: `AGENT_AUDIT=1` di env, **atau** ada penanda untuk salah satu pid leluhur guard (`$$`, lalu naik lewat `ps -o ppid= -p <pid>`, maksimal 8 tingkat) yang masih hidup.

Aturan saat `AUDIT` aktif (pesan blokir menyebut "mode audit hanya-baca"):
- **git:** hanya allowlist subcommand baca: `show log grep blame diff fetch status ls-files ls-tree rev-parse rev-list describe cat-file for-each-ref show-ref shortlog reflog name-rev merge-base help version`; `branch` dan `tag` hanya tanpa argumen non-opsi dan tanpa `-d -D -m -M -c -C -f -a`(tag)/`-s`/`-u`; `remote` hanya tanpa argumen, `-v`, `get-url`, `show`; `config` hanya `--get`, `--get-regexp`, `--list`, `-l`; `worktree list`; `stash list|show`. Selain itu blokir. Pemeriksaan setelah opsi global (pakai posisi subcommand dari `check_git`).
- **gh/glab** (token perintah baru di `check_Bash`, seperti `git`/`orca`): blokir `pr|mr|issue` dengan `create comment merge close edit review approve reopen note`, `release create|delete|edit`, dan `api` dengan `-X`/`--method` selain `GET` atau dengan `-f -F --field --raw-field --input`.
- **orca:** blokir `worktree create`.
- **Edit/Write/MultiEdit/NotebookEdit:** boleh hanya bila realpath file berada di bawah realpath `${TMPDIR:-/tmp}/audit/` atau `/tmp/audit/` (yang belum ada: pakai induk terdekat yang ada, seperti `check_edit`). NotebookEdit memakai `.tool_input.notebook_path`.
- **`mcp__claude_ai_Atlassian__*`:** blokir nama yang mengandung `__create`, `__edit`, `__add`, `__update`, `__transition`. Di luar mode audit, `transitionJiraIssue` tetap ke `check_jira` seperti sekarang; tool Atlassian lain lolos.
- Tambah komentar: `# shortcut: shell writes (sed -i, > file) are not caught in audit mode; upgrade with a sandbox if agents start writing via shell`.

- [ ] **Step 1: Tulis tes yang gagal** `tests/guard_audit_test.sh` (pola `tests/guard_git_test.sh`: repo git sementara, helper `check <exit> '<cmd>'` lewat `AGENT_AUDIT=1`, helper `tool_check <exit> <tool> <json tool_input>`):
  - Mode audit lewat env: `check 2 'git commit -m x'`, `check 2 'git checkout -b x'`, `check 2 'git stash'`, `check 2 'git add .'`, `check 2 'git branch feat/x'`, `check 2 'git tag v1.0.0'`, `check 2 'git worktree add ../w-1'`, `check 2 'git config user.name x'`; `check 0 'git log --oneline -5'`, `check 0 'git -C /x show HEAD:a.txt'`, `check 0 'git --no-pager blame a.txt'`, `check 0 'git fetch origin --tags'`, `check 0 'git branch -a'`, `check 0 'git tag -l'`, `check 0 'git remote -v'`, `check 0 'git worktree list'`, `check 0 'git grep foo v1.2.3'`.
  - `check 2 'gh pr create --title x'`, `check 2 'glab mr note 1 -m x'`, `check 2 'gh api -X POST repos/a/b/issues'`, `check 0 'gh pr view 1'`, `check 0 'gh api repos/a/b/pulls'`; `check 2 'orca worktree create --name x'`.
  - Write `"$REPO/a.txt"` → 2; Write `/tmp/audit/s1/temuan.md` → 0; Write `"${TMPDIR}audit/s1/a.md"` → 0; NotebookEdit `notebook_path` di repo → 2.
  - `mcp__claude_ai_Atlassian__addCommentToJiraIssue`, `createJiraIssue`, `editJiraIssue`, `transitionJiraIssue` → 2; `getJiraIssue`, `searchJiraIssuesUsingJql` → 0.
  - Mode audit lewat penanda: `AGENT_WORKFLOW_STATE=$T/st`, buat `$T/st/audit/$$` (pid shell tes = leluhur guard) tanpa env → `git commit -m x` → 2. Penanda pid mati saja (`999999`) → `git commit -m x` → 0.
  - Tanpa mode audit: `git commit -m x` → 0, Write `"$REPO/a.txt"` → 0 (repo tanpa worktree tambahan), `addCommentToJiraIssue` → 0.
  - Akhiri dengan `exit $FAILS`.
- [ ] **Step 2:** `bash tests/guard_audit_test.sh` → FAIL.
- [ ] **Step 3:** Implementasikan di `hooks/guard.sh`: hitung `AUDIT`; `check_git_audit` dipanggil dari `check_git` setelah `GSUB_OFF`; `check_forge` untuk `gh|glab`; cabang di `check_orca`; `check_edit` memeriksa folder audit lebih dulu bila `AUDIT`; dispatch `case $tool` menambah `NotebookEdit` dan `mcp__claude_ai_Atlassian__*`.
- [ ] **Step 4:** `bash tests/run.sh` → `ALL PASS` (tes lama + baru).
- [ ] **Step 5:** Commit `feat(guard): read-only audit mode (AGENT_AUDIT or audit-mode marker)`.

### Task 3: Matcher hook di `install.sh`

**Files:**
- Modify: `install.sh`
- Test: `tests/install_test.sh`

**Interfaces:**
- Produces: matcher entri guard = `Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__claude_ai_Atlassian__.*`, untuk instalasi baru **dan** entri guard yang sudah ada (matcher lama diganti, entri tetap satu).

- [ ] **Step 1:** Tambah tes: settings awal berisi entri guard dengan matcher lama `Bash|Edit|Write|MultiEdit|mcp__claude_ai_Atlassian__transitionJiraIssue` → setelah install, matcher = nilai baru dan entri guard tetap 1. Instalasi baru juga memakai matcher baru.
- [ ] **Step 2:** `bash tests/install_test.sh` → FAIL.
- [ ] **Step 3:** Ubah filter jq di `install.sh`: bila entri guard ada, set `.matcher` ke nilai baru; bila belum, tambahkan dengan nilai baru.
- [ ] **Step 4:** `bash tests/run.sh` → `ALL PASS`.
- [ ] **Step 5:** Commit `feat(install): guard matcher covers NotebookEdit and Atlassian writes`.

### Task 4: Peran `auditor` dan `analis`, nama, format laporan

**Files:**
- Create: `agents/auditor.md`, `agents/analis.md`
- Modify: `skills/_shared/rules.md` (tabel peran baris 13-20, tabel "Nama agen"), `skills/_shared/report-format.md` (bagian baru `## Laporan audit (/audit-issue)`), `tests/agents_test.sh`

**Interfaces:**
- Produces: frontmatter `name: auditor` / `name: analis`, `model: opus`, tanpa `tools` (mewarisi semua), `description` satu kalimat Indonesia.
- `auditor.md`: hanya-baca (mode audit); baca kode di ref yang diberikan SPV tanpa checkout (`git show <ref>:<path>`, `git log <ref>`, `git grep <pola> <ref>`, `git blame <ref> -- <path>`); Crashlytics/log bila alat tersedia, selain itu catat "tidak bisa diperiksa"; reproduksi di device bila ditugaskan (`devices.md`: `device-pick.sh`, urutan Maestro → Android CLI → adb, kotak merah `report-format.md`); tulis temuan ke `${TMPDIR:-/tmp}/audit/<slug>/<nama-panel>.md` dengan tiap klaim + bukti (file:baris, commit, screenshot) + tingkat keyakinan pasti/kuat/dugaan; lepas kunci device/akun.
- `analis.md`: baca lampiran path/link yang diberikan (gambar, PDF, mockup, Figma/Drive bila alat tersedia); daftar perbedaan lampiran vs kode/layar dengan rujukan halaman/bagian; file gagal dibuka → sebut; tulis ke `${TMPDIR:-/tmp}/audit/<slug>/<nama-panel>.md`.
- `rules.md`: tabel peran tambah `| Auditor | opus (`claude-opus-5-5`) | /audit-issue: kode, log, reproduksi | menulis repo/Jira |` dan `| Analis | opus (`claude-opus-5-5`) | /audit-issue: lampiran | menulis repo/Jira |`; tabel nama tambah `| Auditor | Auditor | Cecep, Dadang, Sarip |` dan `| Analis | Analis | Bu Lastri |`; satu kalimat: di `/audit-issue` worker reproduksi memakai nama QA (Paijo, Euis, Ningsih) tetapi mengikuti `auditor.md`.
- `report-format.md` → `## Laporan audit (/audit-issue)`: 8 bagian persis dari spec "Isi laporan", satu dokumen per audit, dibuat di awal dengan blok `pending` lalu diisi.

- [ ] **Step 1:** Di `tests/agents_test.sh` tambah `auditor:opus analis:opus` ke daftar `for pair in ...` → `bash tests/agents_test.sh` FAIL.
- [ ] **Step 2:** Tulis kedua file peran dan perubahan `rules.md`/`report-format.md`.
- [ ] **Step 3:** `bash tests/run.sh` → `ALL PASS`.
- [ ] **Step 4:** Commit `feat(audit): auditor and analis roles, names, audit report format`.

### Task 5: Skill `skills/audit-issue/SKILL.md` dan dokumentasi

**Files:**
- Create: `skills/audit-issue/SKILL.md`
- Modify: `templates/claude-global.md`, `README.md` (tabel perintah), `docs/design-summary.md` (bagian singkat `/audit-issue`)

**Interfaces:**
- Consumes: `bin/audit-mode.sh` (Task 1), mode audit guard (Task 2), `auditor.md`/`analis.md` + nama + format (Task 4), `bin/worker-pane.sh`, `device-pick.sh`, `device-lock.sh`.
- Frontmatter: `name: audit-issue`, `description` Indonesia + kalimat Inggris "Use when asked to audit an issue, complaint, or question without a Jira ticket; kata kunci - audit issue, audit masalah, telusuri keluhan.", `argument-hint: "\"<teks permintaan>\" [--solo|--tim] [lampiran...]"`.
- Isi (gaya `skills/validate-tiket/SKILL.md`: baca dulu shared docs, mermaid singkat, langkah bernomor), langkah 0–7 dari spec "Alur" dengan detail ini:
  - Model sebagai satu nilai di awal skill: `MODEL=claude-opus-5-5`.
  - Langkah 0: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/audit-mode.sh" on` sebelum apa pun; slug = `<yyyymmdd-hhmm>-<3 kata pertama permintaan, huruf kecil, spasi → ->`; `mkdir -p "${TMPDIR:-/tmp}/audit/<slug>"`.
  - Versi: dari permintaan; tidak ada → tag `vX.Y.Z` terbaru setelah `git fetch --tags` (atau `master`); dicatat.
  - Tim: panel `"$AGENT_WORKFLOW_DIR/bin/worker-pane.sh" open "<Nama> (<Label><n>)" "AGENT_AUDIT=1 claude --model $MODEL"` lalu `worker-start --task <id> --terminal <handle> --worktree "id:$ORCA_WORKTREE_ID" --run <run> --json`; isi tugas: "Ikuti `~/.claude/agents/auditor.md`" (atau `analis.md`), slug, ref versi, pertanyaan yang ditugaskan, jatah device/akun, path lampiran. Lampiran dari chat ditelaah SPV sendiri.
  - Langkah 2 dan 6: satu dokumen Claude Docs sesuai `report-format.md` → "Laporan audit".
  - Langkah 7 dan "Berhenti lebih awal": `worker-pane.sh close` semua panel, lepas kunci, `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/audit-mode.sh" off`.
  - Tidak pernah: membuat tiket/komentar Jira, mengubah repo, build/upload.
- `templates/claude-global.md` baris Perintah: tambah `/audit-issue`.

- [ ] **Step 1:** Tulis `skills/audit-issue/SKILL.md` dan perubahan dokumentasi.
- [ ] **Step 2:** `bash tests/run.sh` → `ALL PASS` (agents_test memeriksa referensi `AGENT_WORKFLOW_DIR/bin/*` dan `_agent-workflow-shared/*.md` di skill baru).
- [ ] **Step 3:** Commit `feat(audit): /audit-issue skill` dan push ke `origin main`.
- [ ] **Step 4 (user):** jalankan `! ~/agent-workflow/install.sh` supaya skill baru ter-symlink dan matcher hook diperbarui; tambahkan `/audit-issue` ke baris Perintah di `~/.claude/CLAUDE.md`.
- [ ] **Step 5:** Uji langsung di sesi baru: `AGENT_LOCK_PID=$PPID audit-mode.sh on` lalu `git commit --allow-empty -m x` di repo uji → diblokir; `off` → tidak diblokir.
