# Pagar keamanan

**Selalu diblokir oleh guard** (juga di mode otonom):
- Push branch ke selain `origin`; force-push atau hapus `main`/`master`/`develop`. Pengecualian: tag `vX.Y.Z` eksplisit boleh ke `origin` dan `upstream`.
- `rm -r` di luar folder project, kecuali artefak build (`build`, `.gradle`, `DerivedData`, dan sejenisnya) di worktree lain repo yang sama atau di folder project yang terdaftar di `~/.agent-workflow/build-roots.txt`, serta isi `/tmp/qa/`. Worktree rilis sementara `<repo>-rilis-vX.Y.Z` (saudara checkout) boleh dihapus tanpa `--force`. Agen membersihkan artefak build worktree tempat ia bekerja setelah tiket/batch selesai.
- Memindah tiket ke status di luar `~/.agent-workflow/jira-transitions.json` (Done tidak pernah ada di sana).
- Edit file di worktree primary; membuka tab/workspace/project Orca baru; worktree di luar folder project.
- Uninstall, `pm clear`, dan install app hanya di device yang dikunci agen itu sendiri (atau tidak dikunci siapa pun); agen yang device-nya diambil alih diblokir dari perintah device tanpa target.
- Mode audit: semua penulisan ke repo, git remote, dan Jira.

**Dijaga aturan skill (bukan guard):**
- Merge PR rilis (`<protected>` → `<primary>`): hanya manusia. Agen hanya merge PR tiket (ke `<protected>`), setelah audit dan "ya" dari user.
- Pindah tiket ke Todo tanpa izin user.
- Upload build produksi (Play production/`.aab` ke store, TestFlight untuk rilis App Store) hanya dengan izin eksplisit user per upload, dan hanya setelah smoke live lulus.
- Regresi penuh di beta wajib jalan sebelum user ditanya Konfirmasi rilis; suite kosong/tidak bisa jalan ditulis sebagai risiko, bukan lulus.

**Agen selalu berhenti dan bertanya** bila: upload ke prod, akan merge PR tiket (setelah audit), hotfix (sementara manual: tanya dulu), nomor build tidak jelas, kredensial tidak ditemukan, dua fix hotfix bentrok, atau `build:heavy` / device sedang dipakai tiket Jira lain atau kamu sendiri untuk UAT (kamu memilih: tunggu, atau dahulukan/ambil alih untuk tugas ini).

**Kredensial** dibaca dari file lokal (mis. `qa.local.properties`) dan tidak pernah ditulis ke Docs, Jira, atau MR. Data uji di dev/staging diawali kode tiket (mis. `PROJ-1234-user`). Regresi UI di **beta** (`/branch-manager`) boleh menulis data lewat app dengan akun uji, data diawali versi (mis. `v1.4.0-…`). Di **live** hanya smoke baca-saja (`smoke-live`). Cek API ke beta/live tetap method aman.

---
[← kembali ke README](../README.md)
