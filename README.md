# YAAM

YAAM, short for Yet Another ADIF Manager, is a native macOS amateur-radio logbook for operators who want one place to manage ADIF records, confirmations, contest sessions, award progress, and operating intelligence.

## Highlights

- Native SwiftUI macOS app with fast ADIF table browsing, search, filters, sorting, duplicate review, and protected imports.
- Station profiles for home, portable, remote, club, and historical operating locations.
- QRZ, LoTW, eQSL, Club Log, HAMQTH, SMTP, WSJT-X/JTDX, Hamlib rigctld, DX Cluster, and external ADIF workflow support.
- QSL Hub for durable upload queues, retry handling, and confirmation downloads from LoTW and QRZ Logbook.
- QRZ Awards dashboard with progress cards and continent-focused award visuals.
- LoTW-confirmed local award progress for DXCC-style entity count, WAS-style state count, and 6m grid progress.
- QRZ Rank leaderboard with rival tracking, daily history, rank-gap trends, and performance momentum feedback.
- Contest workspace with UTC session tracking, serial/exchange support, dupe checks, and Cabrillo 3.0 export.
- Contest Calendar and 6m Watch panel with WA7BNM calendar access, PSK Reporter reception evidence, and Magic Band opening assessment around the Middle East.
- Propagation dashboard using solar/VHF context plus live reception reports to help decide when to operate.
- Data safety tools with SQLite-backed storage, restore points, backup/restore, and macOS Keychain credential storage.

## Core Workflows

1. Create a station profile with callsign, grid locator, QTH, zones, radio, antenna, and service-specific settings.
2. Import ADIF or SmartSDR logs, review duplicates and confirmation updates, then merge only the records you trust.
3. Use Operator Desk for Quick Log, DX Cluster spots, radio/WSJT-X integration, contest operation, QSL Hub, awards, portable activity, connectivity, and 6m monitoring.
4. Sync LoTW and QRZ confirmations to keep local counts aligned with cloud logbooks.
5. Track QRZ Rank competitors and use the leaderboard recommendation to decide whether to invest in QSO volume, band coverage, DXCC reach, or 6m opportunities.

## Privacy

YAAM stores saved passwords and API secrets in macOS Keychain. Log data remains local unless you explicitly import, export, upload, sync, or enable a network-facing companion feature.

## Requirements

- macOS with SwiftUI support.
- Xcode for building from source.
- Optional accounts or tools for QRZ, LoTW/TQSL, eQSL, Club Log, HAMQTH, PSK Reporter lookup, WSJT-X/JTDX, Hamlib rigctld, and DX Cluster nodes.
