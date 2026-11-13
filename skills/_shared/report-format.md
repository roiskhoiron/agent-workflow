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

**Mode tim** (`--tim`): setelah Keputusan, tambah empat bagian sebelum TC, masing-masing menyebut agen sumbernya (`<Nama> (<Label>)`) dan tingkat keyakinan:
- **Bisnis** (PdM): tujuan, AC ↔ aturan bisnis, celah, pertanyaan untuk user.
- **Desain** (Product Designer): link mockup yang dipakai (wajib, untuk Planner/Coder), checklist state, selisih mockup vs app.
- **Teknis** (HoE + Contract Runner, + Spesialis eskalasi bila dipanggil): dampak ke blueprint, modul yang disentuh, status API/kontrak, ukuran pekerjaan.
- **Ketergantungan** (PjM): tabel tiket/PR → status → dampak, risiko bentrok, saran urutan.
Di Temuan, sebut ref dokumen yang dibaca (hasil sinkron sumber).

## Laporan uji (`/develop-tiket`)
1. **Judul**: `Uji PROJ-1234 — judul singkat`, tanggal, nama user.
2. **Ringkasan**: tabel TC → AC → Lulus/Gagal/Tertahan, plus jenis uji (Maestro / XCUITest / Schemathesis / Pact).
3. **Keputusan**: kalimat tebal **Siap review** atau **Belum siap** + alasan.
4. **Satu bagian per TC**: hasil di kalimat pertama, langkah bernomor, screenshot berurutan; untuk API/kontrak tampilkan tabel endpoint → hasil.
5. **Temuan**: branch + commit, nomor build dev/beta + link distribusi, data uji, checklist tindak lanjut.

## Laporan audit (`/audit-issue`)
Satu dokumen per audit, dibuat di awal audit dengan blok `pending` per bagian, lalu diisi dan dirapikan menjadi laporan final (dokumen yang sama). Urutan bagian:

1. **Ringkasan untuk awam** (3–5 kalimat): apa yang ditanyakan, jawabannya, dan saran utama.
2. **Permintaan asli** + daftar lampiran (terbaca / gagal + alasan).
3. **Temuan per pertanyaan**: satu bagian per pertanyaan, tiap klaim dengan bukti (file:baris di ref, commit, potongan log, screenshot bertanda).
4. **Perbandingan lampiran vs kode vs layar** (bila ada lampiran): tabel `Lampiran | Kode | Layar | Beda?`.
5. **Akar masalah** + tingkat keyakinan (**pasti** / **kuat** / **dugaan**), dampak, perkiraan ukuran perbaikan.
6. **Saran langkah berikutnya**.
7. **Saran tiket Jira** (opsional, tidak dibuat): judul, deskripsi, AC, platform.
8. **Cara audit**: versi/ref dan build yang diperiksa, device, alat yang dipakai, hal yang tidak bisa diperiksa (termasuk: guard tidak menangkap tulis lewat shell).

## Screenshot bertanda
- Kotak merah + label merah teks putih, dibuat dengan `annotate.py` dari koordinat `maestro hierarchy` atau `-frames.json` XCUITest (cara lengkap: `devices.md`).
- Label = kode AC + penjelasan singkat, mis. `AC2 pesan galat tampil`.
- Satu hal penting per kotak; nama file urut: `TC1-01.png`, `TC1-02.png`.

## Komentar Jira
Ditulis seperti rekan satu tim yang sopan, dan bisa dipahami pembaca awam (PM, QA, bisnis), bukan hanya developer.

**Gaya**
- Orang pertama **aku**, hangat dan to the point. Hindari "Agen telah…", "Berikut hasil…", kata kaku, emoji berlebihan (paling banyak satu, mis. 🙏).
- **Bahasa awam:** kalimat pendek, kata sehari-hari. Jelaskan dampaknya bagi pengguna, bukan detail teknisnya. Hindari istilah teknis (endpoint, 404, AC, TC, emulator, merge, build number); kalau terpaksa, beri arti singkat dalam kurung. Detail teknis cukup di laporan Claude Docs dan PR/MR.
- **Sapaan**: sapa orang yang dituju (reporter untuk validasi; reviewer/assignee untuk Ready To Review). Pakai sapaan yang sudah dipakai tim untuk orang itu di komentar tiket (mis. "Mas Dimas", "Mba Rina"). Belum ada contoh → **Kak <nama depan>**. Jangan menebak mas/mba dari nama.
- Baris pertama **selalu** memuat link laporan Claude Docs, dibungkus kalimat sapaan.
- Isi: apa yang aku cek, hasilnya, lalu apa yang perlu dari mereka (jika ada). Tutup dengan terima kasih atau tawaran bantu.
- Kabar kurang enak (tidak layak, tertahan) disampaikan jujur tapi lembut, dengan alasan dan jalan keluar.
- Tanpa kredensial; sebut nama kunci saja.

**Contoh — validasi layak dengan catatan**
```
Halo Kak Rina, aku sudah cek tiket ini ya. Laporan lengkapnya di sini: <link Claude Docs>
Tiket ini bisa mulai dikerjakan. Ada satu poin yang belum bisa aku coba, yaitu pesan salah saat nomor HP keliru, karena aku butuh satu HP Android lagi untuk mengetesnya.
Tiketnya aku pindah ke In Progress. Kalau ada HP cadangan, boleh kabari aku ya, nanti langsung aku lengkapi. Terima kasih 🙏
```

**Contoh — tidak layak**
```
Halo Mas Dimas, hasil pengecekanku ada di sini: <link Claude Docs>
Untuk sementara tiket ini belum bisa aku lanjutkan, karena halaman daftar pesanan di server uji belum bisa dibuka, jadi fitur ini belum bisa dicoba.
Tiketnya aku biarkan di Todo dulu. Begitu servernya siap, cukup kabari aku dan aku cek ulang. Makasih ya!
```

**Contoh — Ready To Review**
```
Halo Kak Sari, perubahan di tiket ini sudah siap dicek. Laporan ujinya ada di sini: <link Claude Docs>
Semua yang diminta di tiket sudah aku coba di iPhone dan Android, dan hasilnya sesuai.
Aplikasi versi uji: <link Firebase> · Perubahan kode: <link PR>
Kalau ada yang kurang pas, tinggal kabari aku, nanti aku perbaiki. Terima kasih sudah meluangkan waktu!
```

Kirim lewat `mcp__claude_ai_Atlassian__addCommentToJiraIssue`.
