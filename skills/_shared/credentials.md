# Akun uji dan kredensial

Isi kredensial **tidak pernah** ditulis ke Claude Docs, Jira, PR/MR, commit, log laporan, atau `CLAUDE.md`. Di laporan cukup sebut nama kunci (mis. `qa.user1`).

## Urutan cari
1. `local.properties` → kunci `qa.*`
2. `qa.local.properties`
3. `.env*.local` / `.env` yang di-gitignore
4. `*.xcconfig` yang di-gitignore

Cek gitignore sebelum memakai file: `git check-ignore -q <file>`. Jika file berisi kredensial **tidak** di-ignore: jangan dipakai, berhenti dan tanya (jangan commit, jangan tampilkan isinya).

## Belum ada kredensial
Berhenti dan tanya (lihat `rules.md`) dengan saran:
1. Tambahkan `qa.local.properties` ke `.gitignore` **lebih dulu**.
2. Salin template `$AGENT_WORKFLOW_DIR/templates/qa.local.properties` ke root project.
3. User mengisi nilainya sendiri.

Kunci di template:
| Kunci | Isi |
|---|---|
| `qa.env` | `dev` atau `staging` |
| `qa.api.baseUrl` | URL API dev/staging |
| `qa.user1.phone`, `qa.user1.password` | akun uji 1 |
| `qa.user2.phone`, `qa.user2.password` | akun uji 2 (tambah `user3...` bila perlu) |

## Pemakaian
- Satu akun, satu agen, satu waktu: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" acquire account:qa.user1 <owner>`, lepas setelah selesai (lihat `devices.md`).
- Kredensial dibaca saat dipakai (mis. env Maestro `-e USER_PHONE=...`), tidak disalin ke file lain yang ter-track.

## Data uji
- Hanya di **dev/staging**; jika `qa.env`/baseUrl mengarah ke prod → berhenti.
- Semua data yang dibuat diawali kode tiket, mis. `PROJ-1234 Alamat Uji`, `proj1234+a@example.com`.
- Catat data yang dibuat di bagian Temuan laporan (tanpa password).
