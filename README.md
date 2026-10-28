# agent-workflow

Workflow agen Claude Code + Orca untuk tiket Jira pada proyek mobile (native iOS/Android, KMP): dari validasi tiket sampai Ready To Review, dengan pagar keamanan dan pembersihan berkala.

| Perintah | Gunanya |
| --- | --- |
| `/validate-tiket KODE...` | Cek tiket layak dikerjakan, laporan bergambar di Claude Docs |
| `/develop-tiket KODE... [--solo\|--tim]` | Rencana, kode (TDD), uji, build, PR/MR |
| `/rilis-tiket KODE-RILIS` | Kumpulkan rilis/hotfix, cek manifest, satu MR ke upstream |

Status: **rancangan & rencana** — implementasi sedang berjalan.

- Rancangan: [docs/design-summary.md](docs/design-summary.md)
- Rencana implementasi: [docs/plans/2026-10-28-jira-agent-workflow.md](docs/plans/2026-10-28-jira-agent-workflow.md)
