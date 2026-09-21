# YAAM

YAAM, short for Yet Another ADIF Manager, is a native macOS amateur-radio logbook for operators who want one place to manage ADIF records, confirmations, contest sessions, award progress, and operating intelligence.

## Highlights

- Native SwiftUI macOS app with fast ADIF table browsing, search, filters, sorting, duplicate review, and protected imports.
- Station profiles for home, portable, remote, club, and historical operating locations.
- QRZ, LoTW, eQSL, Club Log, HAMQTH, SMTP, WSJT-X/JTDX, Hamlib rigctld, DX Cluster, and external ADIF workflow support.
- QSL Hub for durable upload queues, retry handling, and confirmation downloads from LoTW and QRZ Logbook.
- Awards dashboard combining QRZ achievements, LoTW confirmations, local progress, and continent-focused visuals.
- LoTW-confirmed local award progress for DXCC-style entity count, WAS-style state count, and 6m grid progress.
- Confirmation Credit Intelligence identifies unconfirmed QSOs that would add a new confirmed country-band or four-character grid, with a country-by-band planning matrix in Statistics.
- QRZ Rank leaderboard with rival tracking, daily history, rank-gap trends, and performance momentum feedback.
- Contest workspace with UTC session tracking, serial/exchange support, dupe checks, and Cabrillo 3.0 export.
- Contest Calendar and 6m Watch panel with WA7BNM calendar access, PSK Reporter reception evidence, and Magic Band opening assessment around the Middle East.
- Propagation dashboard using solar/VHF context plus live reception reports to help decide when to operate.
- Network-Attached Transceiver Emulator (NTE): Full hardware emulation of Icom IC-705/7300/7610/9700 (CI-V over IP, 48 kHz LPCM16 audio streaming, LAN auto-discovery) and built-in Hamlib rigctld server with synthetic RF digital mode generation (FT8, FT4, CW) and physical channel simulation (AWGN, Rayleigh/Rician fading, Doppler, QRN).
- Data safety tools with SQLite-backed storage, restore points, backup/restore, and macOS Keychain credential storage.

## Core Workflows

1. Create a station profile with callsign, grid locator, QTH, zones, radio, antenna, and service-specific settings.
2. Import ADIF or SmartSDR logs, review duplicates and confirmation updates, then merge only the records you trust.
3. Use Operator Desk for Quick Log, DX Cluster spots, radio/WSJT-X integration, contest operation, QSL Hub, awards, portable activity, connectivity, and 6m monitoring.
4. Sync LoTW and QRZ confirmations to keep local counts aligned with cloud logbooks.
5. Track QRZ Rank competitors and use the leaderboard recommendation to decide whether to invest in QSO volume, band coverage, DXCC reach, or 6m opportunities.

## Operator Desk Workspaces

The desk uses six workspaces with a contextual tool strip. Each workspace remembers its last tool. **All tools** searches tool names, services, and earlier names such as Sync Center and Connect. The macOS Tools menu follows the same structure.

| Workspace | Tools |
| --- | --- |
| Operating | Quick Log, Shack Clock, Portable |
| DX Activity | DX Cluster, Club Log Spots, Bandmap, Call Roster, Globe & Grids, 6m Watch, DX News, ON4KST Chat |
| Radio & Digital | Radio Bridge, FLRig, TCI SDR, Rotator, FT8 Station, Multi-Rig FT8, Digital Suite, Emulator |
| CW Workstation | Keyer & Memories, Academy, Q-Codes & Prosigns, Audio Decoder, Pileup Trainer, WinKeyer & Hardware |
| Contest & Awards | Contest Operations, Contest Calendar, Awards, Club Memberships |
| QSL & Data | QSL Hub, Labels & Printing, Log Sources & Automation, Cloud & Companion |

**QSL Hub → Sync Confirmations** handles LoTW, QRZ, eQSL, and Club Log. **Log Sources & Automation → Sync Local Logs** imports External ADIF and SDR-Control updates; Wavelog has its own button. The existing automatic schedule continues to cover External ADIF, SDR-Control, LoTW, and QRZ. Cloud folder synchronization and the phone companion remain under Cloud & Companion.

Existing destination IDs and operating shortcuts are retained. Log Sources & Automation uses **⌘⌥⇧S**, resolving the previous conflict with **File → Save As (⌘⇧S)**. Detached Shack Clock, emulator, and Multi-Rig windows remain available under **Tools → Open in Separate Window**.

## Developer & User Documentation Guides

Comprehensive user manuals and architectural blueprints are available:
- [English Comprehensive User Manual](USER_MANUAL.md): Step-by-step user guide covering all 17 operational chapters including LoTW TQSL digital signing, Default Station Location, Tactical Rover Mode, Spectrum Bandmap & Waterfall Studio, QSL Card Label Studio, International Club Memberships, and Club Log Live Spots.
- [Persian Comprehensive User Manual (راهنمای جامع کاربری نرم‌افزار YAAM به زبان فارسی)](USER_MANUAL_FA.md): راهنمای گام به گام تمام قابلیت‌های جدید، امضای دیجیتال لاگ‌ها با TQSL برای LoTW و مفهوم Default Station Location، مدهای مورس، ساعت شَک، رادار هواشناسی و مدهای دیجیتال.
- [English Developer & Architecture Guide](DEVELOPER_DOCUMENTATION.md): Deep-dive into system layers, Icom UDP protocols (CI-V MK2 registers, audio jitter avoidance), SQLite persistence, ESM contest engines, FT8 modems, and 11-band calculations.
- [Persian Developer Guide (راهنمای جامع معماری و توسعه به فارسی)](DEVELOPER_GUIDE_FA.md): تفکیک کامل لایه‌ها، پروتکل‌های شبکه رادیویی، ساختار لاگ‌بوک و نکات کلیدی برای توسعه‌دهندگان بعدی.

## Product Position

A detailed, source-linked comparison with established amateur-radio loggers is available in [COMPETITIVE_ANALYSIS_FA.md](COMPETITIVE_ANALYSIS_FA.md).

## Privacy

YAAM stores saved passwords and API secrets in macOS Keychain. Log data remains local unless you explicitly import, export, upload, sync, or enable a network-facing companion feature.

## Requirements

- macOS with SwiftUI support.
- Xcode for building from source.
- Optional accounts or tools for QRZ, LoTW/TQSL, eQSL, Club Log, HAMQTH, PSK Reporter lookup, WSJT-X/JTDX, Hamlib rigctld, and DX Cluster nodes.
