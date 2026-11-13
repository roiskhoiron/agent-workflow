# Pasang di komputer lain (macOS)

1. Prasyarat:
   ```bash
   brew install jq gh glab maestro firebase-cli cocoapods uv
   uv tool install schemathesis
   brew tap pact-foundation/pact-ruby-standalone && brew install pact-legacy
   ```
   Plus: Xcode (juga untuk XCUITest runner), Android SDK (`adb`, emulator, `android`), Claude Code, Orca. Untuk mode tim: `/config` → Teammate mode → `auto` (lihat [Tim agen](tim-agen.md)).
2. Plugin Claude Code: `superpowers` dan `ponytail` (lewat `/plugin`); `kotlin-agent-skills` opsional untuk project Kotlin/KMP. Skill pendukung lain ([daftar](alat.md#skill-pendukung)) ada di `~/.claude/skills`: `orca-cli`, `orca-computer-use`, `orchestration` (symlink ke `~/.agents/skills`, dari Orca), `android-cli` (`android init` memasang skill default), `graphify` (`uv tool install graphifyy && graphify install --platform claude`).
3. Konektor claude.ai: **Atlassian** (Jira) dan **Claude Docs**.
4. Login CLI: `gh auth login`, `glab auth login`, `firebase login`.
5. Pasang dan cek:
   ```bash
   git clone https://github.com/roiskhoiron/agent-workflow ~/agent-workflow
   bash ~/agent-workflow/install.sh && bash ~/agent-workflow/tests/run.sh   # harus "ALL PASS"
   ```
   Installer membuat symlink skill & agen ke `~/.claude`, memasang hook guard (backup `settings.json.bak-agent-workflow`), job launchd housekeeping, dan bagian CLAUDE.md global (sekali saja). Karena symlink, perubahan di repo langsung berlaku tanpa pasang ulang; pasang ulang hanya bila ada skill/agen/hook baru.

Tidak ikut repo (per komputer):
- `~/.agent-workflow/jira-transitions.json`: agen menanyakan ID transisi In Progress / Ready To Review saat pertama jalan di project baru.
- `~/.agent-workflow/build-roots.txt` (opsional): folder project, satu per baris. Dipakai housekeeping dan guard (agen boleh menghapus artefak build di folder ini).
- Kredensial `qa.local.properties` per project, kunci App Store Connect.

---
[← kembali ke README](../README.md)
