# Pagar keamanan

**Selalu diblokir oleh guard** (juga di mode otonom):
- Push branch ke selain `origin`; force-push atau hapus `main`/`master`/`develop`. Pengecualian: tag `vX.Y.Z` eksplisit boleh ke `origin` dan `upstream`.
- `rm -r` di luar folder project, kecuali artefak build (`build`, `.gradle`, `DerivedData`, dan sejenisnya) di worktree lain repo yang sama atau di folder project yang terdaftar di `~/.agent-workflow/build-roots.txt`, serta isi `/tmp/qa/`. Worktree rilis sementara `<repo>-rilis-vX.Y.Z` (saudara checkout) boleh dihapus tanpa `--force`. Agen membersihkan artefak build worktree tempat ia bekerja setelah tiket/batch selesai.
- Memindah tiket ke status di luar `~/.agent-workflow/jira-transitions.json` (Done tidak pernah ada di sana).
- Edit file di worktree primary; membuka tab/workspace/project Orca baru; worktree di luar folder project.
- Uninstall, `pm clear`, dan install app hanya di device yang dikunci agen itu sendiri (atau tidak dikunci siapa pun); agen yang device-nya diambil alih diblokir dari perintah device tanpa target.
- Merge PR rilis (`<protected>` → `<primary>`): hanya manusia. Agen hanya merge PR tiket (ke `<protected>`), setelah audit dan "ya" dari user.
- Pindah tiket ke Todo tanpa izin user; upload ke live/prod tanpa izin eksplisit.
- Mode audit: semua penulisan ke repo, git remote, dan Jira.

**Agen selalu berhenti dan bertanya** bila: upload ke prod, akan merge PR tiket (setelah audit), hotfix (sementara manual: tanya dulu), nomor build tidak jelas, kredensial tidak ditemukan, dua fix hotfix bentrok, atau `build:heavy` / device sedang dipakai tiket Jira lain atau kamu sendiri untuk UAT (kamu memilih: tunggu, atau dahulukan/ambil alih untuk tugas ini).

**Kredensial** dibaca dari file lokal (mis. `qa.local.properties`) dan tidak pernah ditulis ke Docs, Jira, atau MR. Data uji hanya di dev/staging, diawali kode tiket (mis. `PROJ-1234-user`).

---
[← kembali ke README](../README.md)
