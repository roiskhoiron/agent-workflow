# agent-workflow

Workflow agen Claude Code + Orca untuk tiket Jira pada proyek mobile (native iOS/Android, KMP): dari validasi tiket sampai Ready To Review, dengan pagar keamanan dan pembersihan berkala.

| Perintah | Gunanya |
| --- | --- |
| `/validate-tiket KODE...` | Cek tiket layak dikerjakan, laporan bergambar di Claude Docs |
| `/develop-tiket KODE... [--solo\|--tim]` | Rencana, kode (TDD), uji, build, PR/MR |
| `/rilis-tiket KODE-RILIS` | Kumpulkan rilis/hotfix, cek manifest, satu MR ke upstream |

Status: **v1 terpasang** — siap uji coba di tiket nyata.

## Pasang di komputer lain (macOS)

1. Prasyarat:
   ```bash
   brew install jq gh glab maestro firebase-cli cocoapods uv
   uv tool install schemathesis
   brew tap pact-foundation/pact-ruby-standalone && brew install pact-legacy
   ```
   Plus: Xcode, Android SDK (`adb`, emulator), Claude Code, Orca.
2. Plugin Claude Code: `superpowers` dan `ponytail` (lewat `/plugin`).
3. Konektor claude.ai: **Atlassian** (Jira) dan **Claude Docs**.
4. Login CLI: `gh auth login`, `glab auth login`, `firebase login`.
5. Pasang:
   ```bash
   git clone https://github.com/roiskhoiron/agent-workflow ~/agent-workflow
   bash ~/agent-workflow/install.sh && bash ~/agent-workflow/tests/run.sh
   ```
   Installer: symlink skill & agen ke `~/.claude`, pasang hook guard (backup `settings.json.bak-agent-workflow`), job launchd housekeeping, dan bagian CLAUDE.md global (sekali saja).

Tidak ikut repo (per komputer): `~/.agent-workflow/jira-transitions.json` (agen menanyakan ID transisi saat pertama jalan), `~/.agent-workflow/build-roots.txt` (opsional), kredensial `qa.local.properties` per project, kunci App Store Connect.


- Rancangan: [docs/design-summary.md](docs/design-summary.md)
- Rencana implementasi: [docs/plans/2026-10-28-jira-agent-workflow.md](docs/plans/2026-10-28-jira-agent-workflow.md)
