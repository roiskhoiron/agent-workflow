# Device dan screenshot

Aturan utama: **satu device, satu agen, satu waktu.** Device fisik dulu, lalu virtual. Maks 3 device virtual menyala bersamaan; sisanya antre.

## Device yang ada
| Device | Prioritas |
|---|---|
| iPhone fisik (USB) | utama untuk iOS |
| HP Android fisik (USB, izin debugging aktif) | utama untuk Android |
| Simulator iPhone | cadangan iOS |
| Emulator Android | cadangan Android |

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
- `device-pick.sh <ios|android> <owner>`: fisik → virtual yang sudah menyala → boot virtual baru (jika < 3). Exit 1 = tidak ada yang bebas: tunggu lalu coba lagi, jangan pakai device lain.
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

## Kotak merah dari koordinat, bukan tebakan
1. Saat layar yang mau ditandai tampil: `maestro --device <id> hierarchy > "$W/h.json"`.
2. Ambil `bounds` elemen yang dimaksud (cari lewat `text`, `resource-id`, atau `accessibilityText`).
3. iOS: bounds dalam *point*; kalikan dengan skala layar (lebar screenshot px ÷ lebar layar point, mis. 3). Android: bounds sudah piksel.
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
Build iOS/Android dijalankan satu per satu (RAM terbatas). Kunci `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/device-lock.sh" acquire build:heavy <owner>` sebelum build, `release build:heavy <owner>` sesudahnya.
