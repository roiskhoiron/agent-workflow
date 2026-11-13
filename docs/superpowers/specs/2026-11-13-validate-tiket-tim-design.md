# /validate-tiket mode tim — rancangan

Status: draf, menunggu persetujuan user (2026-11-13).

## Tujuan
Validasi tiket dibagi per bobot kerja: bisnis, desain, teknis, dan ketergantungan dibaca paralel oleh agen khusus, lalu SPV memutuskan. Hasilnya satu laporan yang langsung bisa dipakai Planner dan Coder (AC, link mockup, endpoint, dampak blueprint, tiket yang bergantung).

Bukan tujuan: menguji penuh (tetap QA di `/develop-tiket`), menulis kode, menulis dokumen bisnis/desain.

## Pemanggilan
`/validate-tiket KODE... [--solo|--tim]`. Tanpa flag: SPV memilih (tiket kecil/jelas → solo). `--solo` = perilaku sekarang (sesi = Validator).

## Peran
Prinsip: model default mengikuti volume kerja, model mahal mengikuti tingkat kesulitan.

| Peran | Model default | Eskalasi | Tugas |
|---|---|---|---|
| SPV (orchestrator) | opus | — | Prasyarat, sinkron sumber, bagi tugas, gabungkan temuan jadi satu laporan Docs, putuskan Layak / Layak dengan catatan / Tidak layak, komentar Jira, transisi, memicu eskalasi |
| PdM (Product Manager) | sonnet | — | Pahami dokumen business discovery terkait tiket: tujuan, AC, aturan bisnis, celah/kontradiksi requirement |
| Product Designer | sonnet | opus (reproduksi bug UI rumit di device) | Baca desain/mockup: layar, state (kosong/loading/error), teks, dark mode; bandingkan dengan tampilan app; reproduksi bug UI |
| Contract Runner | sonnet | — | Jalankan Schemathesis (dev/staging) + Pact untuk endpoint tiket, diff spec vs kode, rangkum output untuk HoE |
| HoE (Head of Engineer) | opus | Spesialis eskalasi | Korelasi codebase dengan blueprint, nilai hasil Contract Runner, reproduksi bug logika/API |
| Spesialis eskalasi | `claude-fable-5-2`, hanya on-demand | — | Dipanggil SPV atau HoE saat ada pemicu; tidak jalan di setiap tiket |
| PjM (Project Manager) | sonnet | — | Progres tiket terkait/blocking/epic/sprint; branch, PR/MR terbuka (`gh`/`glab`), worktree batch lain; risiko bentrok dan saran urutan |

**Pemicu eskalasi ke Spesialis (fable)**, ditulis eksplisit di SOP:
- Bug logika gagal direproduksi HoE (opus) setelah satu putaran.
- Temuan HoE ambigu: SPV tidak yakin bug atau desain yang disengaja.
- Tiket berlabel high-risk: pembayaran, autentikasi, perubahan skema data.
- Konflik antar-agen yang tidak bisa diselesaikan SPV.

Eskalasi Product Designer ke opus: reproduksi bug UI yang gagal/rumit di sonnet setelah satu putaran.

Subagen hanya-baca: tidak menulis Jira/Docs, tidak push. Lapor ke SPV lewat pesan teammate (Contract Runner lapor ke HoE lewat SPV). Device lewat kunci dari SPV (`device-pick.sh`), sama seperti sekarang.

**Hipotesis yang divalidasi lewat pilot:** Product Designer di sonnet. Bila eskalasi ke opus sering terpicu (reproduksi bug UI sering), default-nya langsung opus.

## Alur
1. **Prasyarat** (sama dengan sekarang): Atlassian MCP, `jira-transitions.json`, akun uji.
2. **Sinkron sumber, sekali per sesi, oleh SPV:** `git fetch` remote sumber dokumen (atau `git pull` di checkout dokumen terpisah, bukan worktree primary), lalu `graphify update`. Lokasi diambil dari memory project (aturan `rules.md` → Lokasi); belum ada → tanya user, simpan.
3. **Per tiket:** SPV baca tiket, lalu kirim brief paralel ke PdM, Product Designer, Contract Runner, HoE, PjM (link tiket, lokasi dokumen, worktree, jatah device bila bug).
4. **Gabung:** SPV menyusun satu laporan Docs dengan bagian Bisnis / Desain / Teknis / Ketergantungan + keputusan. Tiket UI tanpa mockup → paling tinggi "Layak dengan catatan".
5. **Komentar Jira + transisi + lepas kunci**: sama dengan sekarang.

## Lokasi dokumen
Tidak pernah ditulis di konfigurasi global. Disimpan per project di memory project (tipe `reference`): path/remote dokumen business discovery, desain/mockup, kontrak API, blueprint.

## Yang berubah
- `skills/validate-tiket/SKILL.md`: flag, langkah sinkron, alur tim.
- Agen baru: `agents/pdm.md`, `agents/product-designer.md`, `agents/contract-runner.md`, `agents/hoe.md`, `agents/eskalasi.md`, `agents/pjm.md`; `agents/validator.md` tetap untuk solo.
- `rules.md`: tabel tim, nama agen, `subagent_type`.
- `report-format.md`: bagian laporan validasi tim.
- README, `tests/agents_test.sh`, halaman Claude Docs workflow.

## Keputusan builder
- Nama panggilan agen (tabel "Nama agen") dipilih builder, mengikuti gaya yang ada.
- Product Designer dan `analis` (/audit-issue) tetap terpisah dulu; penggabungan dibahas terpisah.
