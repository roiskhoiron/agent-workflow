# Masalah umum

| Gejala | Artinya / yang dilakukan |
| --- | --- |
| "DIBLOKIR oleh guard: ..." | Perintah melanggar pagar. Agen melaporkan pesannya, tidak mencari jalan memutar. Baca pesannya; biasanya menyebut cara yang benar |
| "Teammate mode mati" / agen bertanya buka ulang sesi | Mode tim butuh teammate mode. Buka ulang Claude dengan `claude --teammate-mode auto` atau set `/config` → Teammate mode → `auto`, lalu ulangi perintah |
| "Jalankan dari workspace domain" | `/develop-tiket` dijalankan dari root project. Buka workspace domain di Orca lalu ulangi |
| "belum punya daftar transisi" | Project baru: agen menunjukkan daftar status, kamu pilih ID In Progress dan Ready To Review |
| `device-pick.sh` exit 1 | Semua device sedang dipakai; agen menunggu lalu mencoba lagi |
| "build:heavy sedang dipakai PROJ-1 — … Mana yang didahulukan?" | Mac hanya kuat satu build berat sekaligus. **Tunggu** = antre. **Dahulukan** = build tiket lain dihentikan dan diulang otomatis setelah build kita selesai (lebih cepat karena cache). Upload tidak pernah dihentikan |
| `build-number.sh` exit 3 | Sumber nomor build tidak sepakat; agen bertanya dengan saran `max+1` |
| TC **Tertahan** | Tidak bisa diuji (device kurang, spec tidak ada, semua alat gagal); alasannya tertulis di laporan |

---
[← kembali ke README](../README.md)
