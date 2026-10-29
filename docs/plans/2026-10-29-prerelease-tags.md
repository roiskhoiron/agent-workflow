# Rencana (belum dikerjakan): tahap pra-rilis & tag

Status: **diskusi** — diuji manual 2–3 rilis dulu, baru diterapkan ke `/rilis-tiket` + guard.

## Usulan user
`release/*` (downstream, kloter N) → `X.Y.Z-rc.devN` · MR ke `develop` upstream → `X.Y.Z-rc.betaN` · `develop` → `master` → `X.Y.Z-rc` · store → `X.Y.Z`. Di industri lain ada istilah *nightly*.

## Saran Claude
- Satu tag = satu build yang benar-benar diuji orang (bukan per merge/branch).
- Nama yang urutan SemVer-nya benar: `X.Y.Z-alpha.N` (dev/kloter) < `-beta.N` (QA/stakeholder) < `-rc.N` (build ke review store; N naik jika ditolak) < `X.Y.Z`.
  `rc.devN`/`rc.betaN`/`rc` berurutan terbalik bila disortir (`beta` < `dev`, `rc` < `rc.dev1`, `dev10` < `dev2`).
- Arah `release/*` → `develop` → `master` sah bila `develop` = staging; hotfix dari `master` wajib merge balik ke `develop`.
- iOS `CFBundleShortVersionString` hanya angka: label pra-rilis hanya di tag git + catatan rilis; build dibedakan nomor build (naik terus).
- Nightly = build terjadwal dari `develop`, tanpa tag.

## Yang harus diubah saat diterapkan
- `/rilis-tiket`: tujuan MR `release/*` → `develop`, tahap tag per build, nomor kloter.
- `hooks/guard.sh`: `VTAG` izinkan `-(alpha|beta|rc)\.N` + tes.
- `build-number.sh`: abaikan tag pra-rilis saat mencari versi live.

## Pertanyaan terbuka
- Tag `alpha`/`beta` di-push ke downstream saja atau juga upstream?
- Ada CI/alat yang membaca tag otomatis?
- Siapa penguji tahap beta (QA internal / klien)?
