# Changelog

## 1.37.15 — 2026-10-02

- Redesign SKED as a country band planning workspace with worked and confirmed bands from the active station logbook.
- Save requested bands separately for each operator and provide personalized, editable SKED email templates with individual previews.
- Send selected operators separate messages through YAAM's configured SMTP account, with progress, stop, retry, and prior email reminders.

## 1.37.14 — 2026-10-02

- Require and verify the QRZ Rank token for SKED, show callsign details, and include amateur prefixes in the country picker.
- Start WebSDR reception only on request, hide its background browser, show receiver reachability, keep regional selection open, and warn when no FT8 messages decode after 90 seconds.
- Expand the receiver directory and restrict frequency choices to each receiver's listed FT8 bands.

## 1.37.13 — 2026-10-02

- Add a SKED directory for the top 19 operators by country and ranking category, with QRZ contact sync, mail links, email copying, and Excel-compatible CSV export. Add country leaderboard CSV export.

## 1.37.12 — 2026-10-02

- Simplify the HamTracker WebSDR message row so Swift 6.4 can type-check it.
- Send and queue new QSOs only for enabled cloud services with available settings. Check uploads deferred by Touch ID after unlock, while retaining older pending requests for manual retry.

## 1.37.11 — 2026-10-01

- Add the Digital Callsign Monitor (HamTracker), WebSDR FT8 receive, multi-receiver consensus, and guided FT8 reply planning. Package the optional Python diagnostic script with the app.
- Keep pending cloud uploads while Touch ID is locked. Preserve rejected and seven-day-old uploads for manual retry, and report when the 500-request outbox displaces an older request.
- Make selected QSO deletion persist in the protected logbook, fix RR73 parsing, and encode plus signs and reserved characters in cloud requests.
- Correct microwave MHz entry, Cabrillo band designators from 50 MHz upward, and Icom network meter commands.

Thanks to **EA3JIC** for the careful review, reproducible findings, and patch proposals that informed the reliability fixes.
