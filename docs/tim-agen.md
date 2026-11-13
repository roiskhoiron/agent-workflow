# Tim agen

| Agen | Nama | Model | Tugas | Tidak boleh |
| --- | --- | --- | --- | --- |
| SPV | Pak Darmo | opus | bagi tugas, jatah device, putuskan selesai, publikasi laporan | menulis kode produk |
| Planner | Pak Sastro | `claude-fable-5-2` (Fable 5.2) | rencana kerja + test case tiket mode tim, analisis saat pengerjaan macet; hanya atas panggilan SPV | kode produk, Jira, device, memerintah agen lain |
| Validator | Kang Jajang | opus | `/validate-tiket`; mode tim = SPV validasi | menulis kode produk |
| Coder | Maman, Ujang, Tarjo, Asep, Parmin | sonnet | kode + tes (TDD) di branch tiket; tugas UI: tanya mockup ke SPV dulu, tambahkan micro-interaction + animasi sederhana | Jira, push, upload |
| Reviewer | Mbah Karto | opus | review performa & risiko crash | review kode sendiri |
| QA | Paijo, Euis, Ningsih | sonnet | uji di device (Maestro, XCUITest), API (Schemathesis), kontrak (Pact) | Jira, push, upload |
| Release | Sutini | haiku | nomor build, build + upload, push, PR/MR, komentar & geser tiket | Done, upload prod tanpa izin |
| Auditor | Cecep, Dadang, Sarip | opus | `/audit-issue`: kode, log, reproduksi | menulis repo/Jira |
| Analis | Bu Lastri | opus | `/audit-issue`: lampiran | menulis repo/Jira |
| PdM | Bu Ratmi | sonnet | `/validate-tiket --tim`: dokumen business discovery | menulis repo/Jira/Docs |
| Product Designer | Neng Lilis | sonnet (eskalasi opus) | `/validate-tiket --tim`: mockup, state layar, reproduksi bug UI | menulis repo/Jira/Docs |
| Contract Runner | Kang Ohim | sonnet | `/validate-tiket --tim`: Schemathesis + Pact endpoint tiket | uji ke prod, menulis repo/Jira/Docs |
| HoE | Pak Harjo | opus | `/validate-tiket --tim`: codebase vs blueprint, kontrak API, bug logika | menulis repo/Jira/Docs |
| Spesialis eskalasi | Eyang Wiryo | `claude-fable-5-2` (Fable 5.2), on-demand | `/validate-tiket --tim`: hanya saat pemicu eskalasi | menulis repo/Jira/Docs |
| PjM | Bu Sumi | sonnet | `/validate-tiket --tim`: tiket terkait, PR/MR terbuka, risiko bentrok | menulis Jira/PR/Docs |

Di mode tim, tiap agen adalah **teammate** Claude Code (fitur *agent teams*). Orca menampilkannya sebagai **panel split** di workspace yang sama (bukan tab baru), dengan label seperti `@Maman-Programmer1` tepat di atas kolom input panel itu. Panel muncul sendiri saat SPV memanggil agen, dan tertutup sendiri saat agen dihentikan. Agen yang dapat tugas lanjutan dikirimi pesan, tidak dipanggil dua kali. Model tiap peran diubah di `agents/<peran>.md`.

> **Syarat mode tim:** sesi utama harus jalan dengan teammate mode. Pilih salah satu: jalankan `claude --teammate-mode auto`, atau sekali saja di Claude Code ketik `/config` → **Teammate mode** → `auto`. Tanpa itu agen bertanya: buka ulang sesi, atau lanjut solo.

---
[← kembali ke README](../README.md)
