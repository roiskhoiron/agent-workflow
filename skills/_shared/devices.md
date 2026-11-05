# Device dan screenshot

Aturan utama: **satu device, satu agen, satu waktu.** **Virtual dulu** (simulator/emulator); virtual penuh baru ke device fisik. Satu device virtual menyala per platform. Fitur yang butuh hardware asli langsung device fisik (lihat "Kapan wajib device fisik").

## Device yang ada
Per platform: **1 virtual + 1 fisik**, jadi paling banyak 2 agen memakai device per platform bersamaan.

| Platform | Virtual (utama) | Fisik (virtual penuh, atau butuh hardware asli) |
|---|---|---|
| iOS | 1 simulator iPhone | iPhone 13 Pro (USB) |
| Android | 1 emulator (`Medium_Phone_API_37.0`) | HP Android (USB, izin debugging aktif) |

## Kapan wajib device fisik
Pakai `device-pick.sh <platform> <owner> --physical` bila yang diuji butuh salah satu ini:
- Push notification asli: APNs (iOS), FCM di emulator tanpa Google Play.
- Kamera / scan QR asli, NFC, Bluetooth, sensor gerak, GPS yang bergerak.
- Telepon/SMS asli (OTP lewat SMS), jaringan seluler.
- Biometrik asli, keychain/keystore hardware, pembayaran (Apple Pay/Google Pay).
- Metrik performa (hitch/frame rate), bug yang tiket-nya menyebut model/OS device tertentu.

Selain itu virtual. SPV menandai TC seperti ini `(fisik)` di rencana; Validator memutuskan dari isi tiket. Device fisik tidak ada atau sibuk → antre; tetap tidak ada → TC **Tertahan** dengan alasan, jangan diuji di virtual.

## Ambil dan lepas device
SPV membagi jatah; agen hanya memakai device yang ia kunci sendiri.

**Wajib:** setiap perintah yang memanggil `device-lock.sh`/`device-pick.sh` diawali `AGENT_LOCK_PID=$PPID` di panggilan Bash yang sama. Tiap panggilan Bash = shell baru; `$PPID` di situ = proses Claude Code yang hidup selama agen hidup. Tanpa itu kunci dianggap basi dan bisa direbut agen lain.
```bash
# ambil (satu panggilan Bash); catat nilai dev untuk dipakai di panggilan berikutnya
if dev=$(AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-pick.sh" ios PROJ-1234-qa1); then
  echo "pakai $dev"     # ios:<udid> atau android:<serial>
else
  echo "antre: semua device sibuk"
fi
# lepas setelah selesai (panggilan lain, dev ditulis literal)
AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" release ios:<udid> PROJ-1234-qa1
```
- `device-pick.sh <ios|android> <owner>`: virtual yang sudah menyala → boot virtual bila belum ada yang menyala di platform itu → device fisik yang bebas. Tambah `--physical` = hanya device fisik. Exit 1 = tidak ada yang bebas: tunggu lalu coba lagi, jangan pakai device lain.
- `device-lock.sh who <resource>`: lihat pemilik kunci.
- Kunci milik proses yang sudah mati otomatis dianggap bebas.
- Owner = `<KODE>-<peran><n>`, mis. `PROJ-1234-qa1`.

## Folder kerja
File sementara (flow, `h.json`, `boxes.json`, screenshot) **tidak** ditulis ke repo:
- Validator: `${TMPDIR:-/tmp}/validate/<KODE>/`
- QA: `${TMPDIR:-/tmp}/qa/<KODE>/`

Contoh di bawah memakai `W=${TMPDIR:-/tmp}/qa/PROJ-1234` (buat dengan `mkdir -p "$W"`).

## Aksi di device: Maestro
- Semua tap/ketik/scroll lewat flow Maestro (`maestro --device <udid|serial> test flow.yaml`).
- Simpan flow di `$W/flows/`, supaya bisa diulang.
- Screenshot tiap langkah: `- takeScreenshot: <TC>-<langkah>` di flow.

## Pilih alat Android: Maestro, Android CLI, adb
Selalu pakai serial dari `device-pick.sh` (`--device <serial>`); jangan sentuh device lain.

| Kebutuhan | Pertama | Jika terkendala |
|---|---|---|
| Tap/ketik/scroll untuk TC, reproduksi bug | Maestro flow | Android CLI → adb (lihat urutan di bawah) |
| Hierarchy/bounds untuk kotak merah | `maestro hierarchy` | `android layout --device <serial> --full -o "$W/layout.json"` (bounds piksel) |
| Screenshot | `takeScreenshot` di flow | `android screen capture --device <serial>` → `adb -s <serial> exec-out screencap -p` |
| Pasang/jalankan APK | `android install` / `android run --device <serial>` | `adb -s <serial> install -r` lalu `adb shell am start` |
| Log, shell, file, port forward | `adb -s <serial> logcat/shell/push/pull/reverse` | — |
| Docs Android resmi | `android docs` | web |
| Build (dev/beta/prod) | `./gradlew` sesuai `build-release.md` (flavor) | — (bukan `android build`) |
| Boot/matikan emulator | `device-pick.sh` | `android emulator list/start/stop` hanya di luar workflow tiket |

**Maestro terkendala** = driver gagal terpasang/start, flow timeout berulang, atau elemen tampil di layar tapi tidak ada di `maestro hierarchy` (umum di Compose tanpa `testTag`). Urutannya:
1. Ulang sekali: `maestro --device <serial> test` lagi setelah app di-restart. Masih gagal → lanjut.
2. **Android CLI:** `android layout` untuk cari elemen, `android input --device <serial> tap|text|scroll|key <selector>` untuk aksi, `android screen capture` untuk bukti.
3. **adb:** `adb -s <serial> shell input tap|text|swipe`, `shell uiautomator dump`, `exec-out screencap -p`.
4. Semua gagal → TC **Tertahan**, tulis alat yang dicoba + error-nya di laporan.

Langkah 2–3 bukan flow yang bisa diulang otomatis: tulis perintah persisnya di `$W/manual-steps.sh` dan sebut di laporan bahwa langkah itu di luar Maestro.

## Pilih alat iOS: Maestro, XCUITest runner
Padanan Android CLI di iOS = **XCUITest runner** (`$AGENT_WORKFLOW_DIR/bin/ios-ui.sh`): proyek kecil `ios-runner/` yang mengendalikan app mana pun lewat bundle id, tanpa menyentuh repo app. Pakai udid dari `device-pick.sh` (`ios:<udid>`).

| Kebutuhan | Pertama | Jika terkendala |
|---|---|---|
| E2E, login/registrasi, alur chat, regresi fungsional, visual dasar | Maestro flow | XCUITest runner |
| Inspeksi UI native (elemen yang tidak ada di `maestro hierarchy`) | XCUITest `hierarchy` | — |
| Screenshot satu elemen | XCUITest `elementShot` | — |
| Interaksi native: alert sistem, tekan lama | XCUITest `alert` / `longPress` | — |
| Metrik UI: waktu buka app, kelancaran scroll | XCUITest `measure` | — |

Baris 2–5 langsung pakai XCUITest, tidak menunggu Maestro gagal.

**Maestro terkendala di iOS** (definisi sama dengan Android di atas):
1. Ulang sekali setelah app di-restart.
2. Tulis langkah yang sama di `steps.json`, jalankan `ios-ui.sh`.
3. Gagal juga → TC **Tertahan**, tulis alat yang dicoba + error (`fail-step<N>.png`, pesan gagal di `run.xcresult`).

### Menjalankan XCUITest runner
```bash
W=${TMPDIR:-/tmp}/qa/PROJ-1234
cat > "$W/steps.json" <<'X'
[{"launch":"com.app.dev"},
 {"type":"PROJ-1234-user","into":{"id":"phone"}},
 {"tap":{"label":"Masuk"}},
 {"alert":"Allow"},
 {"assert":{"text":"Beranda"},"timeout":15},
 {"screenshot":"TC1-01"},
 {"hierarchy":"TC1-02"},
 {"elementShot":"TC1-03","of":{"id":"btnSave"}},
 {"measure":"scroll","on":{"id":"chatList"}}]
X
"$AGENT_WORKFLOW_DIR/bin/ios-ui.sh" <udid> "$W/steps.json" "$W/xcui-1"   # folder output baru tiap run
```
- Aksi: `launch` (buka ulang app) / `activate` (lanjut dari layar sekarang, mis. sesudah Maestro), `tap`, `longPress` (+`duration`), `type` (+`into`), `swipe` up|down|left|right (+`on`), `assert`, `alert` (tombol alert sistem), `screenshot`, `elementShot` (+`of`), `hierarchy`, `measure` launch|scroll (maks satu per run).
- Selector: `{"id": accessibilityIdentifier}`, `{"label": "persis"}`, `{"text": "mengandung"}`, opsional `index`. `timeout` (detik, default 10) per langkah.
- Hasil: `<nama>.png`, `<nama>.txt` (pohon UI lengkap), `<nama>-frames.json` (elemen + kotak dalam piksel screenshot), `metrics/*.csv`, `run.xcresult`. Exit ≠ 0 = ada langkah gagal, lihat `fail-step<N>.png`.
- Simulator tanpa signing. iPhone fisik butuh Team ID dari project app:
  `IOS_TEAM=$(xcodebuild -showBuildSettings -project <App>.xcodeproj -scheme <Scheme> 2>/dev/null | awk '$1=="DEVELOPMENT_TEAM"{print $3; exit}') "$AGENT_WORKFLOW_DIR/bin/ios-ui.sh" ...` (CocoaPods: `-workspace <App>.xcworkspace`).
- Runner dibangun sekali per tujuan (simulator / team) lalu dipakai ulang; build ulang otomatis bila `ios-runner/` berubah.
- Hitch/frame rate scroll hanya keluar di iPhone fisik; simulator hanya durasi.
- Simpan `steps.json` di folder kerja seperti flow Maestro, supaya bisa diulang.

## Kotak merah dari koordinat, bukan tebakan
1. Saat layar yang mau ditandai tampil: `maestro --device <id> hierarchy > "$W/h.json"`.
2. Ambil `bounds` elemen yang dimaksud (cari lewat `text`, `resource-id`, atau `accessibilityText`).
3. iOS: bounds dalam *point*; kalikan dengan skala layar (lebar screenshot px ÷ lebar layar point, mis. 3). Android: bounds sudah piksel.
   XCUITest: ambil kotak dari `<nama>-frames.json`, sudah piksel (tidak dikali skala).
4. Tulis `boxes.json` lalu jalankan:
```bash
W=${TMPDIR:-/tmp}/qa/PROJ-1234
echo '[{"x":60,"y":720,"w":1050,"h":140,"label":"AC2 tombol Simpan aktif"}]' > "$W/boxes.json"
uv run --with pillow python3 "$AGENT_WORKFLOW_DIR/bin/annotate.py" "$W/TC1-02.png" "$W/boxes.json" "$W/TC1-02-ac2.png"
```
- Label = kode AC + penjelasan singkat. Hasil: kotak merah, label merah teks putih.
- Jika elemen tidak ada di hierarchy, tulis itu di laporan; jangan menggambar kotak kira-kira.

## Akun uji
Satu akun uji juga satu agen satu waktu. Kunci dengan skrip yang sama: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" acquire account:qa.user1 PROJ-1234-qa1` (exit 1 = dipakai agen lain, stdout = pemiliknya). Detail: `credentials.md`.

## Build berat
Build iOS/Android dijalankan satu per satu (RAM terbatas). Kunci `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" acquire build:heavy <owner>` sebelum build, `release build:heavy <owner>` **segera** sesudah build/upload selesai, sebelum langkah lain (QA, laporan, menunggu user).
- Ulangi `acquire` (aman untuk owner yang sama) tepat sebelum **tiap** perintah build. Gagal = kunci sudah dilepas otomatis atau diambil: ikuti "Kunci dipakai", lalu `build-preempt.sh check <owner>` untuk tahu sebabnya.
- **Lepas otomatis:** kunci yang tidak dipakai build/upload apa pun selama 20 menit dilepas oleh `build-preempt.sh reap` (dijalankan housekeeping tiap jam dan oleh agen yang menunggu), dan pemegangnya mendapat catatan.

**Kunci dipakai** (`acquire` exit 1, stdout = pemilik `<KODE>-<peran><n>`):
- Pertama `"$AGENT_WORKFLOW_DIR/bin/build-preempt.sh" reap`: exit 0 = kunci terlupa sudah dilepas → `acquire` lagi, tanpa bertanya.
- Pemilik dari batch/rilis yang sama (KODE-nya ada di daftar tiket kita) → antre: coba lagi tiap 30 detik, tanpa bertanya.
- Pemilik **tiket Jira lain** → **tanya user** (juga di mode otonom), supaya user memilih prioritas:
  1. `"$AGENT_WORKFLOW_DIR/bin/build-preempt.sh" info` → `owner=… since=<n>m uploading=yes|no`. Judul tiket pemilik dari `getJiraIssue <KODE pemilik>`.
  2. Tanya (chat; teammate lewat SPV, cara di `rules.md`): "`build:heavy` sedang dipakai **<KODE> — <judul>** (<jenis build>, sudah <n> menit). Tugas kita: **<KODE> — <judul>** (<jenis build>). Mana yang didahulukan?" Opsi: **Tunggu** / **Dahulukan <KODE kita>** (build <KODE> dihentikan, diulang otomatis sesudah build kita). `uploading=yes` → jangan tawarkan dahulukan; upload tidak pernah dihentikan, tunggu saja.
  3. **Tunggu** → antre. **Dahulukan** → `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/build-preempt.sh" take <owner kita>`: exit 0 = kunci milik kita; 3 = keburu upload → tunggu; 1 = diambil agen lain → ulangi dari 1.
- **Build kita terhenti/gagal:** sebelum menyebutnya gagal, jalankan `build-preempt.sh check <owner kita>`. Exit 0 = didahulukan tiket lain, bukan kegagalan: antre lagi, build ulang dari awal, dan tulis di laporan "build sempat didahulukan untuk <KODE>".
