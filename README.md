# YAAM (Yet Another ADIF Manager)

[![macOS](https://img.shields.io/badge/macOS-14.0%2B%20%7C%2015.0%2B-blue?logo=apple&style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&style=flat-square)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20Native-indigo?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![SQLite](https://img.shields.io/badge/Storage-SQLite%203%20%28WAL%29-003B57?logo=sqlite&style=flat-square)](https://sqlite.org)
[![ADIF](https://img.shields.io/badge/Format-ADIF%203.1.4-green?style=flat-square)](https://adif.org)

**YAAM** is a modern, high-performance, native macOS amateur-radio logbook and operating workstation designed from the ground up for serious DXers, contesters, and everyday operators. Built purely in SwiftUI and Swift concurrency, YAAM unifies log management, QSL synchronization, radio CAT/DSP control, award tracking, contest execution, and operator outreach into a responsive desktop experience.

---

## Table of Contents

- [Key Highlights](#key-highlights)
- [Feature Breakdown](#feature-breakdown)
  - [1. High-Performance Logbook & Filtering](#1-high-performance-logbook--filtering)
  - [2. Bulk Email Outreach & Template Engine](#2-bulk-email-outreach--template-engine)
  - [3. QRZ Rank Intelligence & Rival Tracking](#3-qrz-rank-intelligence--rival-tracking)
  - [4. Confirmation Opportunity & Award Intelligence](#4-confirmation-opportunity--award-intelligence)
  - [5. Unified QSL Hub (LoTW, QRZ, eQSL, Club Log)](#5-unified-qsl-hub-lotw-qrz-eqsl-club-log)
  - [6. Operator Desk (6 Specialized Workspaces)](#6-operator-desk-6-specialized-workspaces)
  - [7. Radio Bridge & Built-In FT8 Modem](#7-radio-bridge--built-in-ft8-modem)
  - [8. Network-Attached Transceiver Emulator (NTE)](#8-network-attached-transceiver-emulator-nte)
  - [9. Hardware-Bound Secure Vault & Data Safety](#9-hardware-bound-secure-vault--data-safety)
- [Operator Desk Workspaces](#operator-desk-workspaces)
- [Architecture & Tech Stack](#architecture--tech-stack)
- [Getting Started & Build Instructions](#getting-started--build-instructions)
- [Documentation & User Guides](#documentation--user-guides)
- [Privacy & Security](#privacy--security)

---

## Key Highlights

- **Blazing Fast Local Database**: Backed by a multithreaded SQLite engine with Write-Ahead Logging (WAL) and memory caching, effortlessly handling 50,000+ QSOs with sub-millisecond search and instant sorting.
- **Smart Filtering & Tagging**: Multi-criteria search with real-time tags, including **Has Email** (with format validation) and **New Band Tag** (contacts that grant new country-band confirmation credits).
- **Custom Bulk Email Outreach**: Filter targeted operators (e.g. unconfirmed states or new bands), compose messages with dynamic tags (`{CALL}`, `{NAME}`, `{STATE}`), manage reusable named templates, and dispatch safely via SMTP with rate-limiting and instant stop control.
- **QRZ Rank Intelligence**: Track personal standings across QSO, Bands, and DXCC leaderboards; monitor up to 8 rivals with multi-week trend charts; and backfill historical rank standings.
- **Operator Desk Ecosystem**: Six dedicated workspaces covering Quick Log, DX Clusters, CW Workstation with Koch pileup trainer, Bandmap, 6m Magic Band watch, and Contest operations.
- **Rig Integration & Software Defined Radio**: Native Hamlib `rigctld`, FLRig, and TCI protocol client support; built-in FT8 modem with multi-rig reception; and a comprehensive Icom IC-705/7300/7610 hardware emulator.
- **Hardware-Bound AES-256-GCM Vault**: Eliminates macOS Keychain prompts by deriving machine-tied 256-bit encryption keys with automatic App Sandbox cross-container migration.

---

## Feature Breakdown

### 1. High-Performance Logbook & Filtering

- **Full ADIF 3.1.4 Compliance**: Import and export standard ADIF files, SmartSDR exports, and WSJT-X logs with conflict detection, duplicate resolution, and field-level preservation.
- **Multi-Station Profiles**: Manage distinct profiles for Home, Rover, Club, Portable, and Contest setups, each maintaining unique callsigns, grids, DXCC codes, and equipment details.
- **Advanced Query Engine**:
  - Live full-text search across Call, Operator Name, QTH, State, County, Grid, and Notes.
  - Multi-select filters for Band, Mode, DXCC Entity, Continent, and Custom Date ranges.
  - Dedicated boolean toggles: **Has Email**, **New Band Only**, **Unconfirmed Only**, and **Confirmed (LoTW / QRZ / eQSL / Card)**.
  - One-click toolbar pill buttons for rapid toggling without opening modal sheets.
- **Bulk Operations**: Bulk edit, delete, re-enrich via QRZ XML, export selections, or send targeted emails.

### 2. Bulk Email Outreach & Template Engine

Designed specifically for award hunting (such as ARRL Worked All States or DXCC band filling) and scheduling skeds:

- **Saved Bulk Email Templates**:
  - Save complete email drafts with a custom title, subject line, body text, and embedded filter criteria.
  - Quick action toolbar: **Save As...**, **Update**, **Duplicate**, and **Delete**.
  - **⚡️ Apply Filter**: Instantly reapplies the template's saved filter criteria to the main logbook table with a single click.
  - Access saved template filters directly from within the main Log Filter dialog.
- **Dynamic Variable Interpolation**: Use `{CALL}`, `{NAME}`, `{COUNTRY}`, `{STATE}`, `{BAND}`, `{MODE}`, `{FREQ}`, `{DATE}`, and `{TIME}` tags for personalized messaging.
- **Safe SMTP Dispatcher**:
  - Supports Secure SMTP (SSL/TLS on port 465 and STARTTLS on port 587).
  - Configurable dispatch delay between messages (throttle control to respect provider rate limits).
  - Prominent emergency **[ 🛑 Stop Dispatch ]** button for immediate pause/cancellation.
  - Non-blocking asynchronous dispatch: UI remains 60fps fluid, and database saves occur in a single batch upon completion.

### 3. QRZ Rank Intelligence & Rival Tracking

- **Real-Time Standings**: Direct API integration with `qrz-rank.asis.sh` to retrieve national and worldwide rankings in **QSO Rank**, **Bands Rank**, and **DXCC Rank**.
- **Head-to-Head Rival Tracking**: Track up to 8 customizable competitor callsigns simultaneously.
- **Historical Trend Charting**: Continuous daily rank trajectory with multi-week trend visualization, zoom controls, and momentum metrics (daily delta, positions gained/lost).
- **Daily Rank Backfill Engine**: Automatically scans unchecked contacts in the log and enriches them with QRZ rank snapshots in background batches without exceeding API rate limits.
- **Cross-Environment Sync**: Automatically bridges and preserves daily snapshot history across macOS sandboxed containers and host environments.

### 4. Confirmation Opportunity & Award Intelligence

- **Confirmation Opportunity Index**: Continuously analyzes unconfirmed QSOs and highlights those that would yield:
  - A brand-new DXCC entity confirmation.
  - A new Band credit for an existing country (5B-DXCC progress).
  - A new 4-character Maidenhead grid square.
- **Awards Tracking Engine**:
  - **DXCC**: Mixed, CW, Phone, Digital, and per-band breakdown (160m through 6m).
  - **WAS**: Worked All States tracking with confirmed vs. worked matrix.
  - **VHF/UHF & 6m Magic Band**: Grid locators worked and confirmed.
  - **Club Memberships**: Track eligibility and member numbers for FOC, CWops, SKCC, etc.
- **Country-by-Band Matrix**: Visual heatmap in Statistics showing which bands are worked, confirmed, or needed per DXCC entity.

### 5. Unified QSL Hub (LoTW, QRZ, eQSL, Club Log)

- **ARRL Logbook of the World (LoTW)**: Seamless digital signing using local `tqsl` binaries, automatic `.tq8` generation, secure upload, and automated download of confirmation reports.
- **QRZ Logbook**: Direct API integration for bidirectional sync of QSO records and confirmation statuses.
- **eQSL.cc & Club Log**: Automated logbook upload, confirmation fetching, and Club Log OQRS spot tracking.
- **QSL Printing & Label Studio**: Design custom printable QSL cards and label sheets (standard Avery formats) with customizable typography, layouts, and compact QSO tables.

### 6. Operator Desk (6 Specialized Workspaces)

The Operator Desk provides six dedicated workspaces with persistent layout memory and quick switcher shortcuts (**⌘1** through **⌘6**):

| Workspace | Included Tools & Modules |
| :--- | :--- |
| **1. Operating** | **Quick Log HUD** (instant QSO logging with auto-lookup), **Shack Clock** (multi-zone UTC/Local with Solar Grayline), **Tactical Rover** (GPS grid calculation, field day operation). |
| **2. DX Activity** | **Telnet DX Cluster** (auto-reconnect, spot filtering), **Club Log Live Spots**, **Spectrum Bandmap** (spot decay, mode filters), **3D Globe & Grids**, **6m Magic Band Watch** (PSK Reporter live opening analysis), **DX News Feed**, **ON4KST Chat**. |
| **3. Radio & Digital** | **Radio Bridge** (Hamlib `rigctld`, FLRig, TCI for Expert SDRs), **Antenna Rotator Control** (gs-232, rotctld), **FT8 Station & Multi-Rig**, **Digital Suite**, **NTE Hardware Emulator**. |
| **4. CW Workstation** | **WinKeyer Hardware Support** (K1EL WK2/WK3), **Keyer Macros & Memories**, **CW Academy** (Koch method trainer with Farnsworth timing), **Audio CW Decoder** (FFT peak tracking), **Pileup Simulator**. |
| **5. Contest & Awards** | **Contest Engine** (ESM mode, automatic serials, multiplier tracking, Cabrillo 3.0 export), **WA7BNM Live Contest Calendar**, **Awards Progress & Claims Manager**. |
| **6. QSL & Data** | **QSL Hub** (LoTW/QRZ/eQSL/Club Log), **Labels & Printing Studio**, **External Log Sync** (SDR-Control, Wavelog, folder watcher), **Cloud Sync & Mobile Companion**. |

### 7. Radio Bridge & Built-In FT8 Modem

- **Universal CAT Control**: Integrates directly with transceivers via Hamlib (`rigctld`), FLRig, or TCI protocol, providing real-time VFO frequency tracking, mode synchronization, and PTT control.
- **Native FT8/FT4 DSP Modem**: Integrated DSP soundcard modem (via `ft8-808` engine) enabling decoding and encoding directly within the app without requiring third-party software.
- **Multi-Rig Reception**: Monitor multiple receivers or digital slices simultaneously across different bands.

### 8. Network-Attached Transceiver Emulator (NTE)

For software testing, demonstrations, or operating without physical hardware:

- **Complete Icom Transceiver Emulation**: Emulates IC-705, IC-7300, IC-7610, and IC-9700 over UDP/IP with CI-V MK2 registers, LAN broadcast discovery, and full command response fidelity.
- **Real-Time 48 kHz Audio Streaming**: Low-latency bi-directional LPCM16 audio streaming matching real Icom network behavior.
- **Synthetic RF Channel Simulator**: Generates realistic digital signals (FT8, FT4, CW) with configurable channel impairments: Additive White Gaussian Noise (AWGN), Rayleigh and Rician ionospheric fading, Doppler shift, and atmospheric QRN bursts.

### 9. Hardware-Bound Secure Vault & Data Safety

- **No More Keychain Popups**: Uses an AES-256-GCM cryptographic vault keyed directly to local hardware (`IOPlatformUUID` + HKDF-SHA256), eliminating macOS Keychain authorization dialogs.
- **Sandbox-Aware Vault Synchronization**: Automatically detects whether the application is running inside the macOS App Sandbox container or on the host filesystem, migrating and synchronizing credentials seamlessly with timestamp-aware updates.
- **Automated SQLite Backups**: Automatic checkpointing and timestamped SQLite database backups before major sync or import operations.

---

## Operator Desk Workspaces

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              YAAM OPERATOR DESK                                 │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────┤
│ 1. OPERATING │ 2. DX ACTIVE │ 3. RADIO/DIG │ 4. CW WORKST │ 5. CONTEST   │6. QSL│
├──────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────┤
│ • Quick Log  │ • DX Cluster │ • Radio CAT  │ • WinKeyer   │ • Contest Ops│• QSL │
│ • Shack Clock│ • Club Log   │ • TCI / FLRig│ • Keyer Macro│ • Cabrillo   │  Hub │
│ • Rover GPS  │ • Bandmap    │ • Native FT8 │ • CW Academy │ • Calendar   │• Print│
│              │ • 6m Watch   │ • Emulator   │ • Pileup Sim │ • Awards     │• Sync│
└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────┘
```

---

## Architecture & Tech Stack

- **Language**: Swift 6.0 with strict concurrency checks (`Sendable`, `@MainActor`, Task groups).
- **UI Framework**: SwiftUI (100% native declarative UI).
- **Persistence**: SQLite 3 with WAL (Write-Ahead Logging), multi-reader concurrency, and foreign-key constraints.
- **Audio & DSP**: Apple `AVAudioEngine`, `Accelerate` framework (vDSP for FFT and spectral rendering).
- **Networking**: `URLSession` with HTTP/2 and modern `NWConnection` / `NWListener` (Network framework) for low-latency UDP/TCP streams.
- **Security**: Apple `CryptoKit` (AES-GCM, HKDF, SHA-256).

---

## Getting Started & Build Instructions

### Prerequisites

- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
- Xcode 16.0+ with Command Line Tools installed.
- *(Optional)* [ARRL TQSL](https://www.arrl.org/tqsl-download) for LoTW digital signing.

### Building from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/fact0real/yaam.git
   cd yaam
   ```

2. **Open the project in Xcode**:
   ```bash
   open YAAM.xcodeproj
   ```

3. **Build the Release binary via Terminal**:
   ```bash
   xcodebuild -project YAAM.xcodeproj \
              -scheme YAAM \
              -configuration Release \
              -derivedDataPath build/DerivedData \
              build
   ```

4. **Sign with App Sandbox entitlements**:
   ```bash
   codesign --force --deep --sign - \
            --entitlements YAAM/YAAM.entitlements \
            ./build/DerivedData/Build/Products/Release/YAAM.app
   ```

5. **Install to `/Applications`**:
   ```bash
   rm -rf /Applications/YAAM.app
   cp -R ./build/DerivedData/Build/Products/Release/YAAM.app /Applications/YAAM.app
   xattr -cr /Applications/YAAM.app
   ```

---

## Documentation & User Guides

Comprehensive manuals and developer documentation are included in the repository:

- 📖 **[English Comprehensive User Manual](USER_MANUAL.md)**: Detailed operational guide covering all 17 chapters (Station profiles, TQSL, QSL Card studio, Digital modes, and Contests).
- 📖 **[Persian Comprehensive User Manual (راهنمای جامع کاربری فارسی)](USER_MANUAL_FA.md)**: راهنمای کامل گام‌به‌گام برای کاربران به زبان فارسی شامل مدهای مورس، امضای لاگ با TQSL، و تنظیمات کامل ایستگاه.
- 🛠 **[English Developer & Architecture Guide](DEVELOPER_DOCUMENTATION.md)**: Technical breakdown of internal modules, CI-V protocol handling, SQLite schema migrations, and concurrency architecture.
- 🛠 **[Persian Developer Guide (راهنمای معماری و توسعه به فارسی)](DEVELOPER_GUIDE_FA.md)**: مستندات فنی و ساختار معماری نرم‌افزار برای توسعه‌دهندگان.
- 📊 **[Competitive Analysis](COMPETITIVE_ANALYSIS_FA.md)**: تحلیل جامع و مقایسه امکانات YAAM با نرم‌افزارهای نام‌آشنای لاگینگ بین‌المللی.

---

## Privacy & Security

- **Local-First Architecture**: Your logbook data, station notes, and database reside strictly on your local Mac.
- **Secure Credential Storage**: All passwords, API keys (QRZ, LoTW, eQSL, Club Log, SMTP), and tokens are encrypted with hardware-bound AES-256-GCM. No credentials are ever sent to third parties other than the explicitly configured ham radio services.
- **Full Offline Operation**: YAAM functions fully offline. Internet access is only utilized when you explicitly trigger cloud QSL synchronization, QRZ lookups, cluster connects, or bulk email dispatch.

---

## License & Credits

Developed with passion for the amateur radio community by **EP2AES**.  
All rights reserved. Released under the project's designated open/source-available licensing terms.
