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
- `git push` ke remote selain `origin` (downstream/fork), termasuk tag dan hapus branch.
- Force-push atau hapus `master`/`main`/`develop`.
- `rm -r`/`rm -rf` di luar folder project.
- Memindah tiket Jira ke status yang tidak ada di `~/.agent-workflow/jira-transitions.json` (Done tidak pernah ada di sana).
- Edit/Write file di worktree primary; berlaku untuk repo yang punya worktree tambahan (pola Orca).

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

## Worktree (Orca)
Cek posisi: `orca worktree current --json`.
- `isMainWorktree: true` → **primary**: hanya audit dan tanya, tidak ada perubahan file. `/develop-tiket` dan `/rilis-tiket` berhenti di sini dan minta user membuka worktree domain.
- **Domain**: branch gabungan batch, hanya lokal/downstream; satu build, satu distribusi, laporan per tiket.
- **Child per tiket**: branch + PR/MR sendiri.
  `orca worktree create --name PROJ-1234 --parent-worktree current --base-branch <ref> --reference PROJ-1234`
- **Child per coder**: hanya untuk tiket multi-coder.

Child dibuat dan dihapus lewat Orca, dibersihkan setelah MR di-merge.

Orkestrasi (SPV sebagai coordinator):
```
orca orchestration run-create ...
orca orchestration task-create ...
orca orchestration worker-start --task <id> --worktree new-child --agent claude --model <id sesuai peran, lihat tabel>
orca orchestration worker-read ...
```
Di isi tugas tiap worker, tulis: "Ikuti `~/.claude/agents/<peran>.md`" (mis. `coder.md`, `qa.md`).

## Git
- Branch kerja: `feature/` `fix/` `hotfix/` `docs/` `chore/` + kode tiket (mis. `fix/PROJ-1234`), dibuat di downstream.
- Branch rilis: `release/vX.Y.Z`, `hotfix/vX.Y.Z` (selalu tanya dulu).
- Commit menyebut kode tiket (dibaca `manifest-check.sh`).
- Tag versi dibuat maintainer/CI, bukan agen.
- Push hanya oleh Release, hanya ke `origin`.

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
Bahasa Indonesia, singkat padat, ramah pemula; tabel dan diagram mermaid lebih dulu daripada paragraf. Komentar Jira: humanis, orang pertama "aku", sapaan ramah (Mas/Mba/Kak), baris pertama memuat link laporan Claude Docs. Detail format: `report-format.md`. Kredensial tidak pernah ditulis ke Docs/Jira/MR.
