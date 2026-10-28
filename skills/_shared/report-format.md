# Format laporan

Laporan dipublikasikan ke Claude Docs oleh agen management (Validator/SPV) lewat `mcp__claude_ai_Claude_Docs__batch` / `update`. QA tidak publikasi: QA menulis `${TMPDIR:-/tmp}/qa/<KODE>/report.md` + screenshot bertanda (di luar repo) lalu menyerahkan path-nya ke SPV.

Gaya: Bahasa Indonesia, singkat padat, ramah pemula. Tabel dan diagram mermaid lebih dulu daripada paragraf. Tanpa kredensial (sebut nama kunci saja, mis. `qa.user1`).

## Laporan validasi (`/validate-tiket`)
Meniru laporan validasi yang sudah dipakai user. Urutan bagian:

1. **Judul**: `Validasi PROJ-1234 — judul singkat`, lalu tanggal dan nama user.
2. **Ringkasan**: tabel AC → status.
   | AC | Isi singkat | Status |
   |---|---|---|
   | AC1 | Tombol Simpan aktif setelah form lengkap | Lulus |
   | AC2 | Pesan galat muncul jika nomor salah | Tertahan |
3. **Keputusan**: satu kalimat tebal — **Layak**, **Layak dengan catatan**, atau **Tidak layak** — lalu diagram mermaid dan alasan singkat.
   ```mermaid
   flowchart LR
     T[PROJ-1234] --> A1[AC1 Lulus] & A2[AC2 Tertahan]
     A2 --> K{Layak dengan catatan}
   ```
4. **Satu bagian per TC** (`TC1 — judul`):
   - Kalimat pertama: **Lulus** atau **Tertahan** + alasan satu baris.
   - Langkah bernomor; screenshot berurutan sesuai langkah.
5. **Temuan**:
   - Data uji yang dibuat (awalan kode tiket) dan akun yang dipakai (nama kunci).
   - Versi/commit/nomor build yang diuji, device yang dipakai.
   - Checklist tindak lanjut (`- [ ] ...`).

Keputusan parsial boleh. TC yang butuh device lebih dari yang tersedia = **Tertahan**, tulis alasannya.

## Laporan uji (`/develop-tiket`)
1. **Judul**: `Uji PROJ-1234 — judul singkat`, tanggal, nama user.
2. **Ringkasan**: tabel TC → AC → Lulus/Gagal/Tertahan, plus jenis uji (Maestro / Schemathesis / Pact).
3. **Keputusan**: kalimat tebal **Siap review** atau **Belum siap** + alasan.
4. **Satu bagian per TC**: hasil di kalimat pertama, langkah bernomor, screenshot berurutan; untuk API/kontrak tampilkan tabel endpoint → hasil.
5. **Temuan**: branch + commit, nomor build dev/beta + link distribusi, data uji, checklist tindak lanjut.

## Screenshot bertanda
- Kotak merah + label merah teks putih, dibuat dengan `annotate.py` dari koordinat `maestro hierarchy` (cara lengkap: `devices.md`).
- Label = kode AC + penjelasan singkat, mis. `AC2 pesan galat tampil`.
- Satu hal penting per kotak; nama file urut: `TC1-01.png`, `TC1-02.png`.

## Komentar Jira
Baris pertama **selalu** link laporan Claude Docs. Lalu beberapa baris singkat:
```
Laporan: <link Claude Docs>
Keputusan: Layak dengan catatan (AC2 tertahan: butuh device Android kedua)
Build dev: <link Firebase> · PR: <link>
```
Kirim lewat `mcp__claude_ai_Atlassian__addCommentToJiraIssue`.
