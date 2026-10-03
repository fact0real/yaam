# Changelog

## 1.37.23 — 2026-10-03

- Add a manual WebSDR dial frequency field in MHz, with the receiver's listed bands and Utah antenna selection checked before tuning.
- Use the chosen dial frequency for receiver URLs, automatic FT8 decoding, and WebSDR reply setup; provide a one-click return to the band preset.

## 1.37.22 — 2026-10-03

- Keep the SKED email window's header and Close/Send controls visible when delivery errors or overlap warnings appear; scroll the changing content within the available screen height.
- Let operators choose FT8, FT4, or either mode from the email composer and include that choice in personalized messages and sent history.
- Allow Stop & close during delivery, stopping after the current email completes.

## 1.37.21 — 2026-10-03

- Keep a searchable local history of successfully sent SKED emails with recipient, exact subject and body, requested bands, sending time, and proposed daily schedule.
- Mark previously emailed operators in the directory and show their full sent history from the SKED page.
- Warn before repeat SKED requests for overlapping or unknown planned days; allow new nonoverlapping days and an explicit override after review.
- Preserve successful SKED history beyond the general recent-email limit and restrict local history file permissions.

## 1.37.20 — 2026-10-03

- Verify SMTP certificates, keep credentials out of process arguments and error logs, and reject unsafe mail headers.
- Distinguish SKED mail from QSL history, validate personalized template fields, and show delivery failures for individual and batch sends.
- Protect SKED and national leaderboard CSV exports from spreadsheet formulas.
- Keep WebSDR audio active with a nearly invisible on-screen browser, limit health checks, and clear stale decode warnings.
- Require an explicit LoTW station location for unattended uploads; improve country-band matching for Barbados and Trinidad and Tobago.
- Restore the SKED tab on relaunch and make the full Bandmap segment clickable.

## 1.37.19 — 2026-10-03

- Group SKED countries by the eight live QRZ Rank divisions, and add US state and territory selection with dedicated state SKED results.
- Scope country-band history and saved plans to the selected US state when applicable.
- Describe proposed SKED availability as a daily time window in UTC across the selected dates, including explicit daily windows when UTC dates or offsets differ.

## 1.37.18 — 2026-10-03

- Show each SKED operator's previous QSO count and worked or confirmed bands from the active station logbook directly in the directory and planning panel.
- Refresh per-operator history when the selected country, ranked operators, or logbook records change.

## 1.37.17 — 2026-10-03

- Make Select All reversible and add shared band controls for selected SKED operators on the directory and email screen.
- Refresh the SKED email copy, always sign with the sender's name and callsign, and use a four-character station grid.
- Add an optional local-time SKED window that is converted to explicit UTC dates and times in each personalized email.
- Close the composer and confirm success after every selected email is delivered; retain progress and retry controls for partial failures.

## 1.37.16 — 2026-10-02

- Show full country names in the SKED picker and focus SKED planning on 160m through 6m.
- Put Select All in the main SKED toolbar; it includes only operators with valid email addresses in the selected country.
- Stabilize the SKED email editor layout and avoid repeated settings lookups while composing. Show each recipient's name and callsign in the individual-delivery list.

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
