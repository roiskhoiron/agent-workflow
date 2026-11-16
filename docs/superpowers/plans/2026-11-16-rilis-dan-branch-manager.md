# Rilis per tiket + /branch-manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/rilis-tiket` jadi alat per tiket (feedback QA → Todo / build variant / merge PR tiket), skill baru `/branch-manager --rilis` untuk rilis per versi (tracing, laporan Docs, PR rilis, build live, tag), plus validasi ulang tiket yang kembali ke Todo.

**Architecture:** Skill = instruksi Markdown (`skills/<nama>/SKILL.md`) yang dibaca sesi Claude; aturan bersama di `skills/_shared/`; peran di `agents/`. Satu skrip baru `bin/release-trace.sh` (bash + git, teruji) memberi tracing commit `<primary>..<protected>` yang deterministik; sisanya (API `gh`/`glab`, Jira, Docs) dijalankan agen sesuai SKILL.

**Tech Stack:** Bash, git, `tests/lib.sh` (`assert_eq`, `assert_exit`), `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/2026-11-16-rilis-dan-branch-manager-design.md`

## Global Constraints
- Bahasa Indonesia di semua dokumen; istilah teknis/perintah apa adanya.
- Tidak ada nama branch/server/folder khusus project di konfigurasi global: pakai `<primary>`, `<protected>`, memory project (`rules.md` → Lokasi).
- Tidak ada branch `release/*`; tidak ada tag pra-rilis (`alpha`/`beta`/`rc`).
- Branch tidak pernah di-push ke `upstream`; tag `vX.Y.Z` boleh ke `upstream` dan `origin` (aturan yang ada).
- Agen tidak pernah memindah tiket ke Done; agen tidak pernah merge PR rilis `<protected>` → `<primary>`.
- PR rilis wajib merge commit (bukan squash); PR tiket boleh squash atau merge commit.
- Transisi ke Todo butuh izin user per tiket; prod/live upload butuh izin eksplisit.
- Setiap build menyebut nama server + base URL API.
- Setiap perubahan workflow memperbarui README atau `docs/*.md` di commit yang sama (`tests/readme_test.sh`).
- Stage hanya file sendiri (`git add <file>`), tidak pernah `git commit -a`; commit diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. `release-trace.sh` pada riwayat squash-merge (judul `… (#123)`) dan merge commit GitHub/GitLab: tiap PR = satu baris, KODE dan nomor PR benar.
2. `<primary>` tidak terkandung di `<protected>` (hotfix belum di-back-merge) → skrip menolak (exit 3), skill berhenti dan tanya.
3. Commit langsung di `<protected>` tanpa PR/KODE → ditandai tak terlacak (exit 1), tidak diam-diam lolos.
4. String mirip KODE (`UTF-8`, `SHA-256`) tidak dihitung sebagai tiket (prefix project wajib).
5. `/rilis-tiket` pada tiket dengan feedback bertentangan atau tanpa feedback → tanya / tidak bertindak, bukan memilih sendiri.

---

### Task 1: `bin/release-trace.sh` (tracing commit rilis)

**Files:**
- Create: `bin/release-trace.sh`
- Create: `tests/release_trace_test.sh`
- Modify: `docs/alat.md` (baris tabel skrip `bin/`)

**Interfaces:**
- Produces: `release-trace.sh <primary-ref> <protected-ref> <PREFIX>...` → stdout TSV satu baris per commit `git log --first-parent <primary>..<protected>` (lama → baru): `sha7<TAB>pr<TAB>kode<TAB>author<TAB>subject`. `pr` = `#N` (dari `Merge pull request #N` atau akhiran `(#N)`), `!N` (dari `See merge request …!N` di body), atau `-`. `kode` = KODE pertama `<PREFIX>-<angka>` di subject+body (prefix dari argumen, huruf besar), atau `-`. Exit: 0 semua punya kode; 1 ada baris `kode=-` (tetap dicetak); 2 usage/ref tidak ada; 3 `<primary-ref>` bukan ancestor `<protected-ref>` (pesan: `primary belum terkandung di protected: back-merge dulu`).

- [ ] **Step 1: Tulis tes yang gagal** `tests/release_trace_test.sh` (pola `tests/build_manifest_test.sh`: repo git sementara di `mktemp -d`, `git init -q -b master`, user.name/email diset):
  - riwayat: commit awal di `master`; branch `develop` dari situ; (a) merge `--no-ff` branch `feature/PROJ-1` dengan pesan `Merge pull request #12 from fork/feature/PROJ-1`; (b) commit squash `bugfix: PROJ-2 validasi nomor (#13)`; (c) merge dengan subject `Merge branch 'feature/PROJ-3' into 'develop'` dan body `See merge request grp/app!7`; (d) commit langsung `chore: rapikan UTF-8 SHA-256`.
  - `assert_eq` baris (a): `#12` dan `PROJ-1`; (b): `#13`, `PROJ-2`; (c): `!7`, `PROJ-3`; (d): `-`, `-` (UTF-8 tidak terhitung).
  - `assert_exit 1` untuk run itu (ada baris tak terlacak); tanpa commit (d) → `assert_exit 0`.
  - `assert_exit 3` saat `master` punya commit yang tidak ada di `develop`.
  - `assert_exit 2`: argumen kurang dari 3; ref tidak ada.
  - jumlah baris = 4 (merge commit tidak memecah jadi commit isi branch: `--first-parent`).
- [ ] **Step 2:** `bash tests/release_trace_test.sh` → FAIL (skrip belum ada).
- [ ] **Step 3: Implementasi** `bin/release-trace.sh` (`#!/usr/bin/env bash`, gaya `bin/manifest-check.sh`: komentar kepala usage + exit code, Bahasa Inggris di komentar). Cek ancestor dengan `git merge-base --is-ancestor`; baca per commit `git log --first-parent --reverse --format='%h%x1f%an%x1f%s%x1f%b%x1e'`.
- [ ] **Step 4:** `bash tests/release_trace_test.sh` → semua ok; `chmod +x bin/release-trace.sh`.
- [ ] **Step 5:** tambah baris `release-trace.sh` di tabel skrip `docs/alat.md` (kegunaan + contoh `bin/release-trace.sh upstream/master upstream/develop PROJ`). `bash tests/run.sh` → ALL PASS.
- [ ] **Step 6: Commit** `git add bin/release-trace.sh tests/release_trace_test.sh docs/alat.md && git commit -m "bin: release-trace.sh untuk tracing rilis primary..protected"`.

### Task 2: Aturan bersama (rules, build-release, report-format)

**Files:**
- Modify: `skills/_shared/rules.md` (Lokasi, tabel base di Workspace & worktree, Setup transisi Jira, tabel tim Release)
- Modify: `skills/_shared/build-release.md` (PR/MR, ganti bagian "Tiket rilis dan hotfix")
- Modify: `skills/_shared/report-format.md` (bagian baru "Laporan rilis")

**Interfaces:**
- Produces (dirujuk Task 3–5): judul bagian `report-format.md` → `## Laporan rilis (/branch-manager)`; `build-release.md` → `## Rilis (/branch-manager)` dan `## Merge PR tiket (/rilis-tiket)`; memory project memuat **strategi merge** per repo.

- [ ] **Step 1: `rules.md`**
  - Lokasi → bullet Branch project: tambah "strategi merge upstream (squash / merge commit) untuk PR tiket; PR rilis wajib merge commit".
  - Tabel base: hapus baris "Ter-link tiket `[release-request]`/`[hotfix-release]` yang branch-nya sudah ada"; baris hotfix → `upstream/<primary>` atau tag live, "sementara ditangani manual dengan bertanya (`--hotfix` belum ada)".
  - Setup transisi langkah 3: user memilih id **Todo**, **In Progress**, **Ready To Review** (contoh `jq` menyertakan Todo).
  - Tabel tim baris Release: tambah "merge PR tiket setelah audit (/rilis-tiket), PR revert"; larangan: "merge PR rilis ke `<primary>`".
- [ ] **Step 2: `build-release.md`**
  - PR/MR: hapus tujuan "branch rilis"; semua PR tiket ke `<protected>`.
  - Ganti "Tiket rilis dan hotfix (`/rilis-tiket`)" + contoh mermaid dengan `## Merge PR tiket (/rilis-tiket)` (syarat audit dari spec Bagian B) dan `## Rilis (/branch-manager)` (PR rilis `<protected>` → `<primary>` merge commit, di-merge manusia; build live dari head PR; tag beranotasi `vX.Y.Z` di commit merge, push `upstream` + `origin`; PR revert `revert/<KODE>`; revert-dari-revert saat tiket Done lagi; hotfix sementara manual).
- [ ] **Step 3: `report-format.md`** tambah `## Laporan rilis (/branch-manager)`: judul `Perubahan rilis vX.Y.Z`; diagram mermaid branch tiket → `<protected>` → `<primary>` → tag; versi + ref (hash); tabel `KODE | Ringkasan | Branch | PR/MR | Programmer | Status Jira`; commit tak terlacak; Matriks env live; rekomendasi agen; build + server API; komentar Jira baris pertama = link dokumen.
- [ ] **Step 4:** `grep -n "release-request\|hotfix-release\|release/v" skills/_shared/*.md` hanya menyisakan teks yang memang menjelaskan model lama sudah tidak dipakai (idealnya kosong). `bash tests/run.sh` → ALL PASS.
- [ ] **Step 5: Commit** tiga file itu: `"shared: aturan rilis tanpa branch rilis, merge PR tiket, laporan rilis"`.

### Task 3: `/rilis-tiket` per tiket

**Files:**
- Modify (tulis ulang): `skills/rilis-tiket/SKILL.md`
- Modify: `agents/release.md`

**Interfaces:**
- Consumes: Task 2 (`build-release.md` → Merge PR tiket; Todo di `jira-transitions.json`); `/develop-tiket` langkah 3 (Matriks env).
- Produces: pemanggilan `/rilis-tiket KODE...`; frontmatter `argument-hint: KODE...`.

- [ ] **Step 1: Tulis ulang SKILL.md** (frontmatter `name: rilis-tiket`, description baru: membaca feedback QA terakhir per tiket lalu Todo / build variant / audit+merge PR tiket; kata kunci). Isi:
  - Sesi = Release (`release.md`); keputusan ke user di chat.
  - Langkah 0 prasyarat: Atlassian MCP, `jira-transitions.json` punya Todo, branch project + strategi merge dari memory.
  - Langkah 1 per tiket: baca tiket, komentar Jira, PR/MR + review; "feedback QA terakhir" = komentar manusia terbaru setelah komentar agen terakhir.
  - Langkah 2 tabel keputusan persis dari spec Bagian B (4 baris) + urutan Done > ditolak > minta build; bertentangan → tanya.
  - Langkah 3a Ditolak: ringkas arahan, minta izin, `transitionJiraIssue` ke Todo, komentar.
  - Langkah 3b Minta build: sinkron dokumen (seperti `/validate-tiket` langkah 1), cek ulang Matriks env server tujuan (method aman), build variant (`build-release.md`, antre `build:heavy`, Prod izin), catatan rilis + komentar menyebut server + base URL API.
  - Langkah 3c Done: audit (approved, CI hijau, diff sesuai tiket, Matriks env live Sesuai); ada PR revert sebelumnya untuk tiket ini → buat PR revert-dari-revert dulu; lolos → minta "ya" lalu merge (`gh pr merge` / `glab mr merge`, strategi dari memory); gagal → lapor + saran.
  - Langkah 4 ringkasan tabel `KODE | Feedback | Tindakan | Build/PR | Status`.
  - Berhenti lebih awal: lepas `build:heavy`.
  - Mermaid singkat keputusan.
- [ ] **Step 2: `agents/release.md`**: description dan tugas 4 (hapus pembuatan tiket `[release-request]`/branch rilis; ganti: `/rilis-tiket` per tiket + bantu `/branch-manager`: PR rilis, build live, tag); "Tidak boleh" tambah "merge PR rilis ke `<primary>`".
- [ ] **Step 3:** `grep -n "release-request\|hotfix-release\|manifest" skills/rilis-tiket/SKILL.md` → kosong. `bash tests/run.sh` → ALL PASS.
- [ ] **Step 4: Commit** `"rilis-tiket: per tiket dari feedback QA (Todo / build variant / merge PR tiket)"`.

### Task 4: Skill baru `/branch-manager --rilis`

**Files:**
- Create: `skills/branch-manager/SKILL.md`
- Modify: `README.md` (tabel Mulai cepat + contoh), `docs/alur-kerja.md` (bagian baru `/branch-manager`)

**Interfaces:**
- Consumes: Task 1 `release-trace.sh`; Task 2 `report-format.md` → Laporan rilis, `build-release.md` → Rilis; `manifest-check.sh` tidak dipakai (diganti release-trace).
- Produces: pemanggilan `/branch-manager --rilis <KODE-TIKET>`; `argument-hint: --rilis KODE-TIKET`.

- [ ] **Step 1: Tulis SKILL.md** (frontmatter `name: branch-manager`, description + kata kunci: rilis versi, branch manager, release notes). Sesi = Release (Agen First). Langkah persis spec Bagian C 1–11, dengan rincian:
  - Langkah 1: `git fetch upstream origin`; `release-trace.sh upstream/<primary> upstream/<protected> <PREFIX>` — exit 3 → berhenti dan tanya (back-merge); exit 2 → perbaiki ref.
  - Langkah 3 tracing: tiap baris → PR/MR (`gh pr view <N> --repo <upstream> --json headRefName,author,url` / `glab mr view <N>`), baris `pr=-` → cari PR lewat `gh api repos/<upstream>/commits/<sha>/pulls`; programmer = author PR + author commit; status Jira (`getJiraIssue`).
  - Langkah 4: tiket bukan Done / baris tanpa KODE → rekomendasi.
  - Langkah 6–7: dokumen Docs + komentar (format Task 2).
  - Langkah 8: PR rilis `gh pr create --repo <upstream> --base <primary> --head <protected>` / `glab mr create --source-branch <protected> --target-branch <primary>`, catatan "merge commit, bukan squash".
  - Pertanyaan ke user: **Konfirmasi / Tolak / Ikuti rekomendasi agen**; jalur "keluarkan tiket X" = PR revert (spec), lalu ulang dari langkah 1.
  - Langkah 9 build live di worktree sementara `git -C <checkout> worktree add --detach ../<repo>-rilis-vX.Y.Z upstream/<protected>` (hapus setelahnya), kunci `build:heavy`, upload store dengan izin.
  - Langkah 10 tunggu PR rilis merged (cek status; belum → ingatkan, berhenti); tag.
  - Langkah 11 perbarui dokumen + komentar.
  - Larangan: merge PR rilis, push branch ke upstream, menimpa tag, Done.
- [ ] **Step 2:** README tabel Mulai cepat: baris `/branch-manager --rilis KODE` (kegunaan, jalankan dari root project atau domain); perbarui baris `/rilis-tiket`. `docs/alur-kerja.md`: bagian `/rilis-tiket` ditulis ulang ringkas + bagian `/branch-manager`; kanban: alur Ready To Review → feedback QA.
- [ ] **Step 3:** `bash install.sh` (symlink skill baru) lalu `ls -l ~/.claude/skills/branch-manager` menunjuk ke repo. `bash tests/run.sh` → ALL PASS (readme_test mewajibkan `/branch-manager` tersebut).
- [ ] **Step 4: Commit** `skills/branch-manager/SKILL.md README.md docs/alur-kerja.md`: `"branch-manager: rilis per versi (tracing, laporan Docs, PR rilis, build live, tag)"`.

### Task 5: Validasi ulang + "Yang ditolak" di develop

**Files:**
- Modify: `skills/validate-tiket/SKILL.md`, `agents/validator.md`
- Modify: `skills/develop-tiket/SKILL.md` (langkah 2–4), `agents/spv.md`, `agents/planner.md`
- Modify: `docs/alur-kerja.md` (kanban: Ready To Review → Todo oleh QA)

**Interfaces:**
- Produces: istilah **validasi ulang** dan bagian rencana **"Yang ditolak"** (dirujuk `/rilis-tiket` jalur Ditolak).

- [ ] **Step 1: `/validate-tiket`**: deteksi jejak (branch `*/<KODE>` di `origin` via `git branch -r --list 'origin/*/<KODE>'`, PR/MR via `gh pr list --search <KODE>` / `glab mr list --search <KODE>`, komentar laporan uji/rencana). Ada → mode validasi ulang: baca penolakan sejak putaran terakhir, golongkan (requirement berubah/kurang vs implementasi meleset), laporan delta + "Yang ditolak". `validator.md` ikut.
- [ ] **Step 2: `/develop-tiket`**: langkah 2 baca komentar review manusia (PR/MR + Jira) sejak putaran terakhir bila ada jejak; langkah 3 worktree/branch yang ada dipakai; langkah 4 rencana revisi dengan bagian "Yang ditolak" (tiap poin → tugas/TC), PR/MR kembali ke Draft (`gh pr ready <n> --undo` / `glab mr update <n> --draft`) alih-alih membuat Draft baru. `spv.md`, `planner.md` (bagian rencana + brief) ikut.
- [ ] **Step 3:** `bash tests/run.sh` → ALL PASS.
- [ ] **Step 4: Commit** `"validate/develop: validasi ulang tiket kembali ke Todo, bagian Yang ditolak"`.

### Task 6: Dokumen luar + penutup

**Files:**
- Modify: `docs/tim-agen.md` (baris Release), `docs/pagar-keamanan.md` (merge PR rilis hanya manusia), memory `~/.claude/projects/-Users-brightonit-mini/memory/agent-workflow-readme-upkeep.md` bila struktur berubah
- Claude Docs "Rancangan Workflow Agen Jira" (container `6a8caf7b-a8b7-473b-997d-ee8295404ee6`): bagian `/rilis-tiket` + bagian baru `/branch-manager`

- [ ] **Step 1:** perbarui dua halaman docs; `bash tests/run.sh` → ALL PASS; commit `"docs: tim agen + pagar untuk rilis baru"`; `git push origin main`.
- [ ] **Step 2:** perbarui halaman Claude Docs (baca dulu bagian rilis, ganti isinya; tambah bagian `/branch-manager` dengan tabel langkah dan mermaid).
- [ ] **Step 3:** ubah status spec ke "disetujui, diimplementasikan (2026-11-16)"; commit + push.
