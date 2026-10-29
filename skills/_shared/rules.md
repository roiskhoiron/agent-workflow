# Aturan bersama tim agen

Berlaku untuk semua agen dan skill (`/validate-tiket`, `/develop-tiket`, `/rilis-tiket`), juga saat hanya satu agen yang bekerja.

## Lokasi
- Dokumen bersama: `~/.claude/skills/_agent-workflow-shared/<file>.md`.
- Skrip: `$AGENT_WORKFLOW_DIR/bin/<skrip>`. Jika `AGENT_WORKFLOW_DIR` kosong, isi dengan folder repo:
  `export AGENT_WORKFLOW_DIR="$(cd "$(readlink ~/.claude/skills/_agent-workflow-shared)/../.." && pwd -P)"`
  Tiap panggilan Bash = shell baru: ulangi export ini di awal panggilan yang memakai skrip.
- State lokal (bukan di repo): `${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/` — daftar transisi Jira (kunci device ada di `~/.agent-workflow/locks`).

## Tim dan model
| Agen | Model (Orca `--model`) | Tugas | Tidak boleh |
|---|---|---|---|
| SPV | opus (`claude-opus-5-5`) | bagi tugas, jatah device, putuskan selesai | kode produk |
| Validator | opus (`claude-opus-5-5`) | /validate-tiket | kode produk |
| Reviewer | opus (`claude-opus-5-5`) | performa & crash sebelum PR | review kode sendiri |
| Release | haiku (`claude-haiku-5-5`) | nomor build, build+upload, PR/MR, komentar & geser tiket | Done, upload prod tanpa izin |
| Coder | sonnet (`claude-sonnet-5-5`) | TDD di branch sendiri | Jira, push, upload, device di luar jatah |
| QA | sonnet (`claude-sonnet-5-5`) | Maestro, Schemathesis, Pact di device | Jira, push, upload, device di luar jatah |

Management (SPV, Validator, Reviewer, Release) memutuskan dan berbicara ke luar: Jira, Claude Docs, git remote, Firebase/TestFlight. Development (Coder, QA) hanya kode dan device. Housekeeping = skrip shell, tanpa agen. Model diubah di `~/.claude/agents/<peran>.md`.

## Mode kerja
- **Diawasi**: sesi biasa, user menyetujui izin.
- **Otonom**: bypass permission. Pagar di bawah tetap aktif di kedua mode.

## Selalu diblokir (hook `guard.sh`)
- `git push` ke remote selain `origin` (downstream/fork), termasuk `--tags` dan hapus branch. Pengecualian: tag versi `vX.Y.Z` yang ditulis eksplisit (tanpa force/hapus) boleh ke `origin` dan `upstream`.
- Force-push atau hapus `master`/`main`/`develop`.
- `rm -r`/`rm -rf` di luar folder project.
- Memindah tiket Jira ke status yang tidak ada di `~/.agent-workflow/jira-transitions.json` (Done tidak pernah ada di sana).
- Edit/Write file di worktree primary; berlaku untuk repo yang punya worktree tambahan (pola Orca).
- Membuka terminal/agen di **tab baru** (`orca terminal create`, `orca agent launch`, `worker-start --agent`): agen tambahan selalu panel split.
- Membuat workspace/worktree/project baru (`git worktree add`, `orca repo add`, `orca project setup-*`, `--worktree new-child|new-top-level`, `--no-parent`).

Jangan mencari jalan memutar. Jika diblokir, laporkan pesannya ke SPV/user.

## Selalu berhenti dan tanya
1. Upload ke prod.
2. Sebelum membuat branch rilis/hotfix.
3. Nomor build tidak jelas (`build-number.sh` keluar dengan kode 3).
4. Kredensial tidak ditemukan.
5. Dua fix hotfix bentrok.

Cara tanya:
- Di dalam run Orca: `orca orchestration gate-create --task <task_id> --question "<pertanyaan + saran>" --options '["Ya","Tidak"]'`, lalu tunggu `gate-resolve`.
- Di luar Orca: tanya di chat dan tunggu jawaban.

## Periksa dulu, lalu tanya
Sebelum bertanya, kumpulkan fakta sendiri (git log, branch master/develop, versi live, file project). Ajukan pertanyaan dengan ringkasan temuan dan **satu saran**. Baca dulu `## Catatan agen` di `CLAUDE.md` project. Agen tidak menulis `CLAUDE.md` sendiri (worktree primary diblokir guard): jawaban user + temuan diberikan sebagai blok `## Catatan agen` siap tempel, untuk di-commit user sendiri ke `CLAUDE.md` project supaya tidak ditanya ulang. Kredensial tidak pernah dicatat.

## Workspace & worktree (Orca)
Workspace = item Orca tempat terminal agen tampil: git worktree, atau workspace folder (`<repo-id>::<path>::workspace:<uuid>`, path sama dengan folder project).

**Kenali domain:** `$ORCA_WORKTREE_ID` = workspace terminal ini; cari di `orca worktree list --json` (`id` sama) → `displayName` = domain, `path`, `isMainWorktree`. Jangan pakai `orca worktree current` untuk ini: ia mencari dari folder, jadi di workspace folder hasilnya root project. Tidak ketemu → tanya user nama domainnya.
- **Root project** (`isMainWorktree: true`, mis. "Brighton RE"): hanya audit, tanya, dan `/rilis-tiket`.
- **Domain** = workspace yang dibuka user. **Semua agen batch bekerja di dalam domain itu saja**: satu sesi (yolo) atau panel terbelah di workspace yang sama (panel split, lihat Orkestrasi; jangan tab baru).
  - Domain git worktree (mis. BrightonChat "Manager"): kerja di checkout workspace itu.
  - Domain workspace folder (mis. Brighton RE "BAA"): kerja di folder worktree domain yang sudah ada, `<path>/<repo>-<slug>` (slug = `displayName` huruf kecil, spasi → `-`; mis. `brighton-android-baa`, `brighton-ios-baa`). Belum ada → berhenti, minta user membuatnya.
  - Tiket = branch `feature/|fix/|...<KODE>` di checkout domain, dikerjakan **bergantian** (satu branch aktif per checkout). Beberapa coder di satu tiket hanya bila file/modulnya terpisah.
- **Cadangan (C):** tidak aman dibagi (coder menyentuh file yang sama, checkout dipakai domain lain, folder domain tidak ada) → satu agen (solo) saja, atau berhenti dan tanya.
- **Kunci checkout:** sebelum mengubah branch/file, `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" acquire checkout:<path checkout> <domain>`; dipegang domain lain → cadangan C. Lepas saat selesai/berhenti.
- **Dilarang (juga guard):** membuat workspace, worktree, atau project Orca baru dari `/develop-tiket` dan `/validate-tiket` (`orca worktree create`, `orca repo add`, `orca project setup-*`, `--worktree new-child|new-top-level`, `--no-parent`), `git worktree add`, worktree di folder sementara. Satu-satunya pengecualian: `/rilis-tiket` membuat anak rilis dengan `orca worktree create --parent-worktree current`.

Orkestrasi (SPV sebagai coordinator), tiap worker = **panel split** di terminal SPV, bukan tab baru. `worker-start --agent` selalu membuka tab sesuai setelan Orca, jadi jangan dipakai untuk worker; buat panelnya dulu, lalu serahkan ke `worker-start --terminal`:
```
orca orchestration run-create --objective "..." --json
orca orchestration task-create --run <run> --spec "..." --task-title "..." --json
# per worker: split panel (arah selang-seling vertical/horizontal), model di --command
orca terminal split --terminal "$ORCA_TERMINAL_HANDLE" --direction vertical --command "claude --model <id sesuai peran>" --json   # → handle panel = .result.split.handle
orca terminal set-pane-title --terminal <handle panel> --title "<Nama> (<Label><n>)" --json   # mis. "Paijo (QA1)"
orca terminal wait --terminal <handle panel> --for tui-idle --timeout-ms 60000 --json
orca orchestration worker-start --task <id> --terminal <handle panel> --worktree "id:$ORCA_WORKTREE_ID" --run <run> --json
orca orchestration worker-read ...
```
Mode izin worker = mode sesi SPV (otonom → tambah `--permission-mode bypassPermissions` di `--command`). `--model` tidak boleh digabung dengan `--terminal`; model ditentukan di `--command`.
Di isi tugas tiap worker, tulis: "Ikuti `~/.claude/agents/<peran>.md`" (mis. `coder.md`, `qa.md`).

**Nama agen** (judul panel, `--task-title`, dan sapaan di laporan/komentar): nama Jawa/Sunda tetap per peran dan urutan, format `<Nama> (<Label><n>)`. Satu nama satu agen dalam satu batch; sisa kunci tetap `<KODE>-<peran><n>`.
| Peran | Label | Nama berurutan |
|---|---|---|
| SPV | SPV | Pak Darmo |
| Validator | Validator | Kang Jajang |
| Coder | Programmer | Maman, Ujang, Tarjo, Asep, Parmin |
| Reviewer | Reviewer | Mbah Karto |
| QA | QA | Paijo, Euis, Ningsih |
| Release | Release | Sutini |
Contoh: `Maman (Programmer1)`, `Ujang (Programmer2)`, `Paijo (QA1)`, `Euis (QA2)`.

## Git
- Branch kerja: `feature/` `fix/` `hotfix/` `docs/` `chore/` + kode tiket (mis. `fix/PROJ-1234`), dibuat di downstream.
- Branch rilis: `release/vX.Y.Z`, `hotfix/vX.Y.Z` (selalu tanya dulu).
- Commit menyebut kode tiket (dibaca `manifest-check.sh`).
- Tag versi `vX.Y.Z` (beranotasi) dibuat Release setelah MR upstream di-merge, di commit hasil merge, lalu di-push ke `upstream` dan `origin`. Tag tidak pernah di-force atau dihapus.
- Push hanya oleh Release: branch hanya ke `origin`; tag versi ke `upstream` dan `origin`.

## Setup transisi Jira (sekali per project)
Hook menolak transisi sebelum project punya daftar. Jika ditolak "belum punya daftar transisi":
1. `mcp__claude_ai_Atlassian__getTransitionsForJiraIssue` pada satu tiket project itu.
2. Tunjukkan tabel `id → nama status` ke user.
3. User memilih id untuk **In Progress** dan **Ready To Review** (jangan pernah Done).
4. Tulis lewat Bash (bukan Edit/Write), gabungkan dengan isi lama:
```bash
S=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}; F="$S/jira-transitions.json"
mkdir -p "$S" && { [ -s "$F" ] || echo '{}' > "$F"; } &&
jq '. + {"PROJ":{"allow":["21","31"],"names":{"21":"In Progress","31":"Ready To Review"}}}' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
```
Pemindahan tiket: `mcp__claude_ai_Atlassian__transitionJiraIssue` dengan id dari file itu.

## Gaya tulis (laporan, komentar Jira, pertanyaan)
Bahasa Indonesia, singkat padat, ramah pemula; tabel dan diagram mermaid lebih dulu daripada paragraf. Komentar Jira: humanis dan mudah dipahami pembaca awam (tanpa istilah teknis), orang pertama "aku", sapaan ramah (Mas/Mba/Kak), baris pertama memuat link laporan Claude Docs. Detail format: `report-format.md`. Kredensial tidak pernah ditulis ke Docs/Jira/MR.
