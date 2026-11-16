# Rilis per tiket + /branch-manager — rancangan

Status: draf, menunggu persetujuan user (2026-11-16).

## Tujuan dan alasan
Model branch berubah (gambar user): **tidak ada branch rilis lagi**. Downstream (fork, `origin`) murni untuk menyelesaikan tiket (`feature/*`, `bugfix/*`, PR/MR ke `<protected>`); integrasi di `<protected>` upstream; produksi di `<primary>` upstream dengan tag `vX.Y.Z`; hotfix dari `<primary>` lalu back-merge ke `<protected>`.

Kenyataan di lapangan: reviewer manusia/QA lebih sering mengembalikan tiket ke **Todo**, atau meminta build variant lain (Beta/Prod) sebelum memindah ke Done. Workflow harus menangkap feedback itu, dan rilis produksi harus bisa dipertanggungjawabkan: setiap perubahan terlacak ke tiket, branch, PR/MR, dan programmernya.

## Sasaran
1. Tiket yang kembali ke Todo dikerjakan ulang dengan tahu persis apa yang ditolak.
2. `/rilis-tiket` = alat **per tiket** yang membaca feedback QA terakhir dan bertindak sesuai keadaan tiket.
3. `/branch-manager --rilis <tiket>` = alat **per versi**: tracing perubahan `<protected>` → `<primary>`, laporan rilis di Claude Docs, PR rilis, build live, tag.
4. Setiap build menyebut server + base URL API; Matriks env dicek ulang sebelum build ke server lain.

Bukan sasaran: tag pra-rilis (`alpha`/`beta`/`rc`, disepakati tidak dipakai; build dibedakan nomor build); branch `release/*`; `--hotfix` di `/branch-manager` (rancangan terpisah berikutnya; aturan hotfix lama tetap sampai itu dibuat).

Anti-sasaran: produksi memuat perubahan yang tidak terlacak ke tiket Done; agen merge PR rilis ke `<primary>` tanpa keputusan manusia; build live saat endpoint tiket belum ada di server live.

## Pendekatan yang dipertimbangkan
- **Build live dari `<protected>` langsung setelah merge tiket**: paling sederhana, tapi tiket lain yang sudah ter-merge dan belum Done ikut ke produksi. Ditolak.
- **Lewat `<primary>` (dipilih)**: PR rilis `<protected>` → `<primary>`, build live dari commit yang sama, tag setelah merge. Isi produksi terkendali dan terlacak.
- **Satu skill besar `/rilis-tiket`** vs **dua skill** (dipilih): per tiket (`/rilis-tiket`) dan per versi (`/branch-manager`) punya input, risiko, dan peran manusia berbeda.

## Bagian A — Tiket kembali ke Todo (validasi ulang)
- `/validate-tiket` mendeteksi jejak pengerjaan sebelumnya: branch `*/<KODE>` di `origin`, PR/MR terbuka/tertutup, komentar laporan uji/rencana di Jira. Ada → **mode validasi ulang**.
- Baca alasan penolakan sejak putaran terakhir: komentar Jira + komentar review PR/MR (manusia).
- Golongkan: **requirement berubah/kurang** (cek ulang bisnis/mockup/kontrak; tanya user/PM bila perlu) atau **implementasi meleset** (langsung Layak, daftar revisi).
- Laporan berbentuk **delta**: apa yang berubah dibanding validasi sebelumnya + daftar "Yang ditolak".
- `/develop-tiket` pada tiket dengan jejak: **wajib membaca** komentar review manusia (PR/MR + Jira) sejak putaran terakhir → bagian **"Yang ditolak"** di rencana revisi, tiap poin jadi tugas/TC. Lanjut di branch, worktree, dan PR/MR yang sama; PR/MR dikembalikan ke Draft (`gh pr ready --undo` / `glab mr update --draft`).

## Bagian B — `/rilis-tiket KODE...` (per tiket)
Dijalankan untuk tiket di Ready To Review atau Done. Per tiket, agen membaca **feedback QA terakhir** (komentar Jira + PR/MR) dan memilih:

| Keadaan | Tindakan |
|---|---|
| Ditolak QA | Ringkas arahan QA → **minta izin** user → transisi ke **Todo** (id dari `jira-transitions.json`) + komentar ringkasan arahan. Pengerjaan berikutnya lewat Bagian A |
| Positif, belum Done, QA minta build variant lain (Beta/Prod) | Sinkron dokumen terbaru (kontrak API, blueprint, mockup); **cek ulang Matriks env** di server tujuan (method aman); pastikan isi tiket ada di build itu; build variant yang diminta (Prod: izin eksplisit). Endpoint **Belum ada**/**Beda kontrak** di server tujuan → berhenti dan tanya |
| Done + punya PR/MR | Audit: PR/MR approved, CI hijau, isi diff sesuai tiket, Matriks env live **Sesuai kontrak**. Lolos → **agen merge** PR/MR tiket ke `<protected>`. Gagal → lapor + saran, tidak merge |
| Tidak ada feedback QA | Lapor, tidak ada tindakan |

Setiap build menyebut nama server + base URL API (catatan rilis, komentar Jira, PR/MR). Agen tidak pernah memindah ke Done.

## Bagian C — `/branch-manager --rilis <KODE-TIKET>` (per versi, Agen First)
`<KODE-TIKET>` = tiket Jira tempat laporan rilis dikomentari (tiket rilis/request dari QA atau PM).

**Agen bekerja dulu:**
1. `git fetch upstream origin`. Cek `upstream/<primary>` ⊆ `upstream/<protected>` (hotfix sudah di-back-merge); tidak → berhenti dan tanya.
2. Versi `vX.Y.Z`: dari tiket atau file versi project; tidak jelas → tanya.
3. **Tracing** tiap commit `upstream/<primary>..upstream/<protected>`: PR/MR asal (`gh`/`glab` API: PR yang memuat commit), branch tiket di downstream, KODE Jira (judul PR / pesan commit / nama branch), **programmer** (pembuat PR + author commit), status Jira tiket.
4. Cek isi: semua tiket berstatus **Done** (`manifest-check.sh` untuk mencocokkan commit ↔ KODE). Commit tanpa tiket, atau tiket belum Done → ditandai, masuk rekomendasi.
5. **Matriks env live** untuk endpoint semua tiket (method aman). Belum ada/Beda kontrak → ditandai, masuk rekomendasi.
6. **Claude Docs "Perubahan rilis vX.Y.Z"**: diagram mermaid alur branch (branch tiket → `<protected>` → `<primary>` → tag), versi + ref asal (hash), tabel per perubahan (KODE, ringkasan, branch, PR/MR, programmer, status Jira), commit tak terlacak, Matriks env live, rekomendasi agen.
7. **Komentar di `<KODE-TIKET>`**: baris pertama link dokumen, lalu ringkasan versi, jumlah perubahan, dan rekomendasi.
8. Siapkan **PR rilis** `<protected>` → `<primary>` di upstream (isi: link dokumen, tabel perubahan).

**Manusia ditanya** (di chat): **Konfirmasi** / **Tolak** / **Ikuti rekomendasi agen**. Tolak → berhenti, PR rilis tetap Draft/ditutup sesuai jawaban.
- **Keluarkan tiket X dari rilis** (keputusan user: agen yang mengerjakan): agen membuat **PR revert** tiket X ke `<protected>` dari branch `revert/<KODE-X>` di downstream (`git revert -m 1 <merge commit>` atau commit squash-nya), judul `revert: <KODE-X> keluar dari rilis vX.Y.Z`. Merge PR revert mengikuti aturan merge PR tiket (Bagian B, setelah user bilang ya). Tracing diulang setelah PR revert ter-merge. Komentar di tiket X: dikeluarkan dari vX.Y.Z + link PR revert.
- Tiket X kelak Done lagi → `/rilis-tiket` (jalur Done) membuat PR **revert dari revert** dulu sebelum tiket itu dihitung masuk rilis berikutnya.

**Setelah konfirmasi:**
9. Build live dari commit head PR rilis: Android `.aab`, iOS TestFlight (versi produksi). Upload ke produksi store tetap izin eksplisit per upload. Catatan rilis menyebut server + base URL API live.
10. PR rilis di-merge oleh manusia (Release Manager). Agen menunggu/cek status; setelah merged: tag beranotasi `vX.Y.Z` di commit merge, push ke `upstream` dan `origin` (aturan tag yang ada).
11. Perbarui dokumen + komentar: build, link PR rilis, tag.

## Batasan
- **Strategi merge** (keputusan user): PR tiket ke `<protected>` boleh squash atau merge commit; tracing mendukung keduanya (squash: nomor PR di judul commit, mis. `(#123)`; merge commit: parent kedua). **PR rilis `<protected>` → `<primary>` wajib merge commit**, bukan squash, supaya `<primary>` tetap terkandung di `<protected>`. Strategi per repo dicatat di memory project; upstream hanya mengizinkan squash → berhenti dan tanya.
- Branch tidak pernah di-push ke `upstream`; PR rilis dibuat dari branch upstream `<protected>` (tanpa push) lewat `gh pr create --repo <upstream> --base <primary> --head <protected>` / `glab mr create`.
- Merge PR tiket oleh agen hanya di Bagian B setelah audit lolos; merge PR rilis tidak pernah oleh agen.
- Transisi ke Todo butuh izin user per tiket dan id Todo di `jira-transitions.json`.
- Branch, versi, server: dari memory project (`rules.md` → Lokasi), tidak ditulis di konfigurasi global.
- Pagar yang ada tetap: prod hanya dengan izin, tag tidak ditimpa, tidak pernah Done.

## Yang berubah
- `skills/validate-tiket/SKILL.md`, `agents/validator.md`: mode validasi ulang.
- `skills/develop-tiket/SKILL.md`, `agents/spv.md`, `agents/planner.md`: "Yang ditolak", lanjut di branch/PR sama, PR ke Draft.
- `skills/rilis-tiket/SKILL.md`: ditulis ulang (Bagian B); bagian branch `release/*`/`hotfix/*` dihapus.
- Baru `skills/branch-manager/SKILL.md` (+ symlink di `install.sh` bila skill dipasang per folder).
- `skills/_shared/build-release.md`, `report-format.md` (laporan rilis), `rules.md` (Todo transisi, merge oleh agen).
- `bin/manifest-check.sh` dipakai ulang; `build-number.sh` tetap.
- README, `docs/alur-kerja.md`, `tests/readme_test.sh` (perintah baru), halaman Claude Docs workflow.

## Keputusan builder (dari builder check, bisa dikoreksi user)
- `/rilis-tiket`: "feedback QA terakhir" = komentar manusia terbaru (Jira + PR/MR) setelah komentar agen terakhir. Beberapa keadaan sekaligus → urutan: Done > ditolak > minta build. Feedback saling bertentangan → tanya.
- Build live dibuat di worktree sementara `<repo>-rilis-vX.Y.Z` (detached di `upstream/<protected>`, sejajar checkout), dihapus setelah build; kunci `build:heavy`. `<KODE-TIKET>` tidak ditransisikan.
- Hotfix sementara: langkah `release/*`/`hotfix/*` dihapus dari `/rilis-tiket`; tiket hotfix ditangani manual dengan bertanya sampai `--hotfix` dirancang. Tabel base di `rules.md` dirapikan (baris branch rilis dihapus).
- Cek Matriks env live dengan method aman tidak butuh izin per run; tidak perlu kunci device.
- Merge PR rilis oleh agen dilarang lewat aturan skill/rules (guard tidak bisa membedakan base PR dari teks perintah).

## Diserahkan ke builder
- Cara persis mencari PR asal sebuah commit di GitHub/GitLab.
- Susunan visual dokumen rilis dan diagram mermaid.
- Nama agen untuk peran baru (bila dipakai teammate) mengikuti tabel "Nama agen".
