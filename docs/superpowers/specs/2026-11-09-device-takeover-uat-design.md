# Ambil alih device + slot UAT untuk manusia: desain

Tanggal: 2026-11-09. Status: draf, menunggu persetujuan user.

## Maksud dan alasannya

Agen QA/Validator sering harus `adb uninstall` (atau padanannya di iOS) supaya yang diuji benar-benar build tiket yang ia garap: setelah dicek di HP, yang terpasang ternyata versi lain, atau pasang di atasnya gagal (signature beda, versi lebih rendah). Sekarang `adb uninstall` dan `adb shell pm clear` masuk `autoMode.soft_deny` di `~/.claude/settings.json`, jadi agen tertahan untuk aksi yang sebenarnya wajar.

Uninstall hanya berbahaya bila HP sedang dipakai sesi agen lain untuk menguji app yang terpasang. Kunci device (`bin/device-lock.sh`) sudah menandai siapa yang memakai HP; yang kurang adalah (1) izin uninstall yang terikat ke kunci itu, (2) cara ambil alih HP yang dipakai agen lain, dan (3) cara user memesan HP untuk uji manual (UAT) tanpa diganggu agen.

## Tujuan
1. Agen boleh `adb uninstall` / `pm clear` (dan padanan iOS) tanpa bertanya, **asal** device itu sedang dikunci olehnya sendiri.
2. Device dikunci agen lain → agen bertanya ke user: **Tunggu** atau **Ambil alih**, seperti pola `build:heavy` di `devices.md`. Pemilik batch/rilis yang sama → antre tanpa bertanya (sama seperti build).
3. Ambil alih → kunci pindah; agen lama otomatis tahu ia harus berhenti memakai device itu dan antre lagi sampai device dilepas, lalu melanjutkan uji dari awal di sesi berikutnya.
4. Flag baru `--uat` di `/develop-tiket`: setelah QA agen selesai dan sebelum Release, build tiket dipasang di HP fisik, kunci device dialihkan ke user (owner `human-<KODE>`), build tiket tetap terpasang, agen memantau log app selama sesi UAT.
5. Sesi UAT berakhir saat user bilang selesai, atau otomatis setelah **3 menit tanpa aktivitas di log app tiket itu** (dihitung dari aktivitas terakhir). Lalu kunci dilepas dan agen yang antre boleh masuk.
6. Crash/error yang tercatat di log selama UAT masuk ke laporan uji dan komentar Jira tiket itu.

## Bukan tujuan
- Melindungi HP dari uninstall saat user mengetes manual di luar `--uat`. Keputusan user: ia akan mencari agennya dan memberi perintah langsung, jadi tidak perlu dilindungi.
- `--uat` di `/validate-tiket` atau `/rilis-tiket` (hanya `/develop-tiket` untuk sekarang).
- Mengubah urutan pilihan device di `device-pick.sh`.

## Anti-tujuan (gagal walau "jalan")
- Agen meng-uninstall app di HP yang dikunci agen lain atau slot `human-*` tanpa user memilih "Ambil alih".
- Slot UAT tidak pernah lepas (agen yang memantau mati atau user lupa) sehingga semua agen lain macet.
- Agen lama terus menjalankan Maestro/adb di HP yang sudah diambil alih, lalu melaporkan hasilnya sebagai gagal tiket.
- Slot `human-*` ikut diambil alih diam-diam oleh agen lain: ambil alih slot manusia selalu lewat pertanyaan ke user, dan hanya bila user memilihnya.

## Batasan
- Kunci tetap pakai `device-lock.sh` (mkdir-atomic, pid+owner, kunci milik pid mati = bebas). Resource device: `android:<serial>`, `ios:<udid>`.
- Agen bisa ada di sesi Claude Code berbeda (SPV lain, workspace Orca lain), jadi pemberitahuan ke agen lama **tidak boleh** bergantung pada SendMessage. Saluran yang selalu sampai: guard (`hooks/guard.sh`, PreToolUse) dan catatan file seperti `build-preempt.sh` (`~/.agent-workflow/preempted/<owner>`).
- Aturan `rules.md`: teammate bertanya lewat SPV; SPV yang bertanya ke user. Mode otonom tetap bertanya untuk ambil alih (seperti build).
- Bash 3.2 macOS, `stat -f`, tes di `tests/*_test.sh` dengan `tests/lib.sh`.
- README pemula wajib ikut diperbarui (flag baru, perilaku uninstall, slot UAT).

## Keputusan yang sudah diambil user
- Uninstall boleh bila tidak ada sesi agen lain yang menguji di device itu; bila ada, tunggu atau tanya untuk ambil alih; bila ambil alih, agen pemilik diberi tahu untuk berhenti dan menunggu sesi berikutnya.
- `--uat` di `/develop-tiket`: tanpa flag tidak ada pendaftaran manusia; dengan flag agen mendaftarkan user untuk sesi uji berikutnya.
- Selama UAT agen memantau log Android/iOS; toleransi 3 menit tanpa aktivitas lalu slot berakhir.
- Log UAT dipakai juga untuk mencatat crash/error ke laporan/Jira.
- UAT menahan alur: PR/MR, komentar Jira, dan Ready To Review menunggu UAT selesai; crash saat UAT mengembalikan tiket ke Coder.
- UAT selalu di HP fisik; bila QA di virtual, build dipasang ulang ke HP fisik.

## Keputusan yang saya ambil sendiri (mohon dicek)
- Device yang tidak dikunci siapa pun: uninstall/`pm clear` diizinkan (draf sebelumnya memblokir).
- "Dikunci diri sendiri" = pid di kunci adalah leluhur proses hook.
- Catatan ambil alih disimpan per pid/sesi, bukan per nama owner, supaya agen lain yang kebetulan bernama sama tidak ikut terblokir.
- Agen yang punya catatan ambil alih untuk sebuah device diblokir untuk **semua** perintah ke device itu (adb/Maestro/xcrun), bukan hanya uninstall, sampai ia mengunci ulang lewat `device-pick`.
- Slot `human-<KODE>` dipegang pid SPV (bukan proses pemantau log) dan dilepas oleh pemantau idle; hitungan 3 menit dimulai sejak serah terima ke user, lalu direset tiap ada baris log app.
- Pertanyaan "Tunggu / Ambil alih" muncul saat `device-pick` gagal (exit 1) karena semua device yang cocok dikunci pihak lain.

## Bentuk solusi (arah, detail ke builder)

**A. Izin uninstall.** Hapus `Bash(adb:* uninstall *)` dan `Bash(adb:* shell pm clear *)` dari `autoMode.soft_deny`. Gantinya di `guard.sh`: perintah `adb … uninstall …`, `adb … shell pm clear …`, `adb … install …`, dan padanan iOS (`xcrun simctl uninstall`, `xcrun devicectl device uninstall app`, `ios-ui.sh` bila ia memasang/menghapus app) diperiksa terhadap kunci device target:
- device target dikunci owner lain yang masih hidup (termasuk `human-*`) → blokir dengan pesan berisi owner dan langkah "Device dipakai" di `devices.md`;
- device tidak dikunci siapa pun → lolos (keputusan saya: tidak ada sesi lain yang bisa terganggu, dan uji manual di luar `--uat` memang tidak dilindungi);
- dikunci oleh diri sendiri → lolos. "Diri sendiri" = pid di kunci adalah leluhur proses hook (keputusan saya; guard tidak tahu nama owner, jadi pakai pohon proses).
Serial/udid target diambil dari `-s <serial>` / `ANDROID_SERIAL` / argumen udid; bila tidak tertulis dan lebih dari satu device tersambung, blokir minta `-s` eksplisit.

**B. Ambil alih (`bin/device-preempt.sh`, meniru `build-preempt.sh`).** Subperintah kira-kira: `info <res>` (owner, sudah berapa menit, sedang menjalankan Maestro/instrumentasi atau tidak), `take <res> <owner baru>` (hentikan proses uji milik pemilik lama di device itu: Maestro, `adb shell am instrument`, XCUITest; tulis catatan; pindahkan kunci), `check <owner>` (cetak catatan sekali). Ambil alih slot `human-*` hanya lewat pilihan user dan tidak menghentikan apa pun di HP.

**C. Agen lama tahu ia harus berhenti.** Dua lapis: (1) proses uji yang sedang jalan dihentikan oleh `take`; (2) perintah adb/Maestro/xcrun berikutnya dari agen lama ke device itu ditolak guard dengan pesan "device <res> diambil alih oleh <owner>: berhenti, antre dengan device-pick, ulangi uji dari awal" (dari catatan preempt). `devices.md` mengatur: uji yang terhenti karena ambil alih bukan kegagalan tiket; laporan menyebut "uji sempat didahulukan untuk <KODE>".

**D. Slot UAT (`--uat`).** UAT selalu di HP fisik. Posisinya di alur `/develop-tiket`: sesudah QA lulus, **sebelum** langkah Release (build distribusi, push, PR/MR, komentar Jira, Ready To Review). Bila QA berjalan di virtual, build tiket dipasang ulang ke HP fisik (kunci HP fisik lewat `device-pick`, antre bila dipakai). Crash/error fatal selama UAT → tiket kembali ke Coder (perbaikan → Reviewer → QA → UAT lagi), seperti QA gagal; tanpa crash → lanjut Release. Setelah QA, agen: pastikan build tiket terpasang, alihkan kunci ke `human-<KODE>` dengan pid agen pemantau (supaya mati = slot lepas), beri tahu user lewat chat (device, app, cara bilang selesai), lalu pantau log app (`adb logcat --pid`/filter package; iOS `log stream`/`devicectl` dengan filter bundle). Tidak ada baris log app selama 3 menit → lepas slot, tulis ringkasan. Crash/ANR/error fatal → kumpulkan potongan log dan masukkan ke laporan uji + komentar Jira. Di `--batch` satu slot UAT untuk satu build batch (semua tiket batch), bukan per tiket; di `--separate` per tiket.

**E. Antrean.** Agen yang mendapati device dikunci `human-*`: antre (coba lagi tiap 30 detik) atau tanya user bila ingin ambil alih; tidak pernah ambil alih otomatis. `housekeeping.sh` ikut membersihkan slot `human-*` yang pid pemantaunya sudah mati (sudah tercakup oleh aturan pid mati di `device-lock.sh`).

## Diserahkan ke builder
- Nama dan bentuk persis subperintah skrip, format catatan, nama konstanta (`UAT_IDLE_MIN=3`).
- Cara mendeteksi "proses uji milik pemilik lama" (pohon proses dari pid kunci, seperti `build-preempt.sh`).
- Cara deteksi aktivitas log per platform dan filter app (package dari project, bundle id dari Xcode project).
- Penempatan teks di `devices.md`, `develop-tiket/SKILL.md` (argument-hint, alur), `agents/qa.md`, README; tes baru di `tests/`.
