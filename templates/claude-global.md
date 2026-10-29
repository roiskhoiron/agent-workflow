# Workflow choice
- Fitur besar / pekerjaan multi-langkah (fitur baru, refactor, perubahan lintas modul): pakai superpowers (brainstorming → writing-plans → TDD → review → verification).
- Fix kecil (bug lokal, typo, config, perubahan beberapa baris): pakai ponytail; lewati brainstorming dan plan formal.
- Ragu ukurannya: anggap kecil dulu; naik ke superpowers bila ternyata menyentuh banyak file atau butuh keputusan desain.

# Jira agent workflow
- Perintah: `/validate-tiket`, `/develop-tiket`, `/rilis-tiket`. Aturan bersama: `~/.claude/skills/_agent-workflow-shared/rules.md`.
- Workspace Orca: root project hanya untuk audit, tanya, dan `/rilis-tiket`; kerja kode di workspace domain yang dibuka user (id `$ORCA_WORKTREE_ID`). Multi-agent = panel split di workspace itu, bukan tab, workspace, worktree, atau project baru; tidak aman dibagi → solo.
- Keputusan per project tidak ditulis agen ke CLAUDE.md project: agen memberi blok `## Catatan agen` untuk di-commit user.
