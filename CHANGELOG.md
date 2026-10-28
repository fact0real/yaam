# Changelog

## 1.37.53 - 2026-10-28

- Show sent email history for each callsign in the Unconfirmed DXCC hover details and count only successful outgoing contact emails.
- Add an email button to each country card and contact preview so an email can be composed without navigating to the Log Table.
- Make hover-preview callsigns bold without link styling.
- Count confirmed DXCC entities by their ADIF DXCC code, merging alternate country labels for the same entity.

## 1.37.52 - 2026-10-28

- Delay unconfirmed-country hover details by 500 ms and cancel them when the pointer leaves before they appear.
- Make each callsign in the hover details open and select its exact QSO in the Log Table.

## 1.37.51 - 2026-10-28

- Restore hover details for unconfirmed DXCC country cards, including callsign, operator, name, QTH, grid, date/time, band, mode, frequency, and reports.
- Make unresolved or placeholder countries searchable and filterable as Unknown; resolve known callsigns even when the stored country is blank or marked Unknown.
- Apply the same country and frequency-derived band normalization to Log Table filters and the statistics cards that open them.

## 1.37.50 - 2026-10-28

- Add the FX-4CR digital audio and FT8 workflow, including connection controls, QSO logging, and configurable successful-contact log storage.
- Improve CW transmission safety, CAT connection recovery, FT8 timing and decoding, digital receive buffering, contest logging, QSO matching, and POTA/SOTA spot handling.
- Add a locally signed LoTW callsign proof flow for QRZ Rank. It is shown only when the service advertises support; the private key remains in memory and no QSO is uploaded as proof.
- Build version 200. See `Docs/Release/1.37.50-release-notes.md` for validation and known limitations.

## 1.37.44 - 2026-10-24

- Apply independently verified EA3JIC feedback across CW, radio link health, sleep handling, telemetry and ADIF export.
- Wait for asynchronous CW acceptance before ESM logs or advances; keep stop failures visible.
- Add configurable message and Auto-CQ limits, and an operator-inactivity limit for automatic FT8/FT4 transmission.
- Detect silent CAT/TCI links, bound recovery to the same destination, and request receive before retiring an uncertain connection.
- Make serial access exclusive, handle bounded write backpressure, and use the documented Icom keyer-speed encoding.
- Route hardware CW tests through the shared stoppable keyer; correct cwdaemon abort to ESC4.
- Show flrig meter percentages, correct rigctld power writes, send Wavelog changes with a heartbeat and omit unknown power.
- Export QRZ confirmations through APP_YAAM_QRZ_QSL_RCVD while retaining legacy import compatibility.

See `Reports/20261024-EA3JIC-email-batch-review.md` for scope, evidence, validation and hardware limitations.

## 1.37.37 - 2026-10-18

- Integrate reviewed EA3JIC upload privacy and open items with positive allowlists and enhanced transport safeguards.
- Enforce positive ADIF allowlist per upload service, stripping other stations' personal data (email, address, biography, exact coordinates) and local station street address/exact coordinates by default.
- Add three separate opt-in privacy controls in Data Safety for other stations' name/QTH, contact details plus precise positions, and comments/QSL messages.
- Restrict online uploads to the active station callsign, skipping historical or imported contacts made under other callsigns.
- Add non-mutating Wavelog connection and rights test (`check_auth`), distinguish read-only from read/write API keys, and update endpoints (`api/qso`, `get_contacts_adif`, `station_info`).
- Tighten TQSL verification to require exit code 0 for full batch acceptance; handle codes 8, 9, and 14 as non-success with diagnostic details.
- Prevent silent failures on automatic ADIF file save by surfacing I/O errors and serializing background writes.
- Guard digital audio transmissions against unconfigured audio output, preventing invalid RF keying.
- Require valid, finite, in-band frequencies in contest quick-logging instead of falling back to synthetic band defaults.
- Default CAT Morse rigctld client reference to shared instance before Operator Desk is presented.
- Fix PSK31 Varicode table to standard 128-character G3PLX mapping, correct Hellschreiber pixel clock rate, and buffer streamed digital callsigns.
- Detect serial/rig disconnects during CW keying and cancel active transmission within 200 ms.
- Remove debugger entitlement from Release builds, disable base entitlement injection, and document all application entitlements.
- Apply calibrated 0.66 s timing correction to FT8 decodes and normalize station weather coordinates to coarse 4-character grid squares.

## 1.37.36 - 2026-10-17

- Integrate reviewed EA3JIC CW and band-advisor fixes, with additional validation at radio transport boundaries.
- Reject CW command delimiters, unsupported characters and oversized messages; fold supported accents and normalize pasted whitespace.
- Cancel pending TX-500/FX-4CR CW chunks on STOP, replacement and disconnect; pace chunks using Morse timing and preserve the active transmit destination.
- Correct WinKeyer commands and status bits; require the Host Open response, use two serial stop bits, and bound transmission with echoed-character flow control.
- Prevent stale callbacks from ending replacement messages, stop Auto-CQ after manual sends or rejected CQs, and refuse sends without connected keying hardware.
- Send the correct Hamlib stop_morse command and give asynchronous CW stop operations a bounded opportunity to complete during normal application exit.
- Count FT8 decodes and cluster spots once at their original timestamps; bound activity history and allow cluster-based suggestions for bands not currently monitored.
- Coalesce log statistics work, discard stale snapshots, batch email-history row updates and avoid repeated date parsing during log sorting.
- Add simulated CW, protocol, text-validation and snapshot-scheduling regressions. Physical radio/keyer behavior remains subject to hardware verification.

## 1.37.35 — 2026-10-11

- Add bidirectional Sync All and Sync Selected for online QSL services (LoTW, QRZ, eQSL, Club Log) on active station logs.
- Protect privacy and security by stripping local file paths, usernames, and internal metadata from online ADIF uploads.
- Prevent duplicate uploads by marking QSOs accepted by Zero-Click daemon and treating QRZ duplicate responses as accepted.
- Preserve QSL upload status during ADIF imports and merges (upload status only upgrades, never downgrades).
- Log Digital Suite QSOs with connected radio frequency and band, with operator confirmation safeguards.
- Require explicit confirmation (Record QSO / Discard QSO) with valid RSV reports before logging SSTV contacts.
- Isolate Olivia and SSTV practice/simulation text from CALL auto-population; decode complete callsigns on word boundaries.
- Correct DXCC entity mapping for maritime (/MM) and aeronautical (/AM) mobile stations and preserve visited DXCC prefixes.
- Restore Quick Log grid support for both GRIDSQUARE and GRID fields, and default CW/RTTY contest signal reports to 599.

## 1.37.34 — 2026-10-09

- Require the operator's own callsign before CW and digital transmissions, including JS8 and SSTV audio; require a valid locator for FT8/FT4 standard messages.
- Remove built-in station, park, and locator defaults from entry screens and previews.
- Correct flrig XML-RPC parameter types, command ordering, CW commands, connection reporting, and PTT release verification with a visible warning and a 120-second watchdog.
- Correct TX-500 S-meter requests and scaling, and keep stored and exchanged dates Gregorian with Latin digits across Mac calendar settings.
- Add Catalan and Spanish translations for selected interface text.
- Bind the built-in radio emulator servers to loopback and reject unknown rigctld commands.

## 1.37.33 — 2026-10-09

- Unify FT8 Station ribbon heights, keep SNR on one line, and show the newest RX stream entries first.
- Add cycle separators, retention of 1–3 previous cycles, and a 24-cycle decode-count history.
- Cache waterfall images and color lookup, filter Icom LAN audio to 12 kHz, and remove unused per-slot spectrum processing.
- Add optional expanded decoding with three bounded timing alignments; this is not WSJT-X AP or successive signal cancellation.
- Restore Icom TX audio gain control (remove the unintended 95% minimum), and add optional SWR protection using two distinct, fresh loaded readings above 2.5.
- Clear worked-contact opportunities after logging; correct the overly broad SV2A/Mount Athos rule, resolve received calls through CTY, and display logged state/province where known.
- Add current-band DX Cluster/Club Log reports with freshness filtering, and an operator-applied quiet TX offset suggestion from recent received spectrum energy.

## 1.37.32 — 2026-10-08

- Reorganize FT8 Station controls into receive and transmit groups that wrap to fit the window.
- Keep radio connection settings scrollable on short displays and adapt Icom LAN/USB setup to narrow windows.
- Resize the spectrum with the window, stack decode streams on narrow displays, and show an IC-7300MK2 receive check sequence.

## 1.37.31 — 2026-10-05

- Reduce WebSDR audio bridge traffic and retire obsolete browser audio taps after reconnects.
- Reuse the detected FT8 timing phase and bound fallback scans to keep long receive sessions responsive.
- Limit oversized or stale browser audio messages before decoding them on the app's main thread.

## 1.37.30 — 2026-10-05

- Fit Activity Matrix into the available Statistics window height, and make its five insight cards equal sized.
- Keep Country Bands details visible while the country list scrolls independently.
- Compare today's QSOs with the average of the previous seven days up to the same local time in Visual Analytics.

## 1.37.29 — 2026-10-05

- Reject self-contact QSOs at logging and edit entry points, and filter incoming or merged records before they reach log views and statistics.

## 1.37.28 — 2026-10-05

- Remove a recursive log change observer that could crash the app during startup.

## 1.37.27 — 2026-10-05

- Repair QRZ Awards navigation, report QRZ refresh failures promptly, and keep saved results clearly labeled until refreshed.
- Show an award as received only when QRZ reports it as issued; label combined logbook progress as a local estimate.
- Back up the active database before removing self-contact QSOs from every station profile; reject future self-contact entries while preserving contacts made under a different station callsign.

## 1.37.26 — 2026-10-05

- Bound FT8 decoding to the codec's 50-message table to prevent a busy WebSDR window from stalling reception.
- Restrict WebSDR replies to the active station callsign, configured grid, and standard FT8 dial; clear prepared replies after retuning.
- Correct QRZ award analysis and WAS state counting, secure QRZ credential entry to HTTPS QRZ pages, and improve QRZ bulk email greetings.
- Accept Persian and Arabic-Indic digits in the WebSDR dial, preserve the LoTW activity cache on invalid or truncated updates, and show update errors.
- Show single-receiver status, make consensus tie votes deterministic, improve WebSDR search, and remove unused network clock checks.

## 1.37.25 — 2026-10-03

- Add 17 user-supplied receivers in Russia, South Korea, Saudi Arabia, Israel, and the United Kingdom to the WebSDR picker; place the Cherepovets receiver under Russia.
- Open WebSDR and KiwiSDR pages with the selected frequency using each page's query format, while keeping new receivers on manual system audio until automatic recording is validated.
- Check KiwiSDR availability through its status endpoint so private receivers are shown as unavailable; limit receivers with unverified coverage to 20 m.

## 1.37.24 — 2026-10-03

- Select all or individual unmatched QRZ Incoming requests and compose one personalized message per callsign, including all selected request dates.
- Resolve missing recipient addresses from QRZ/HAMQTH, allow manual correction, preview each message, and send separate SMTP emails with per-recipient progress and stop control.
- Skip previously emailed QRZ Incoming operators by default and keep these detail requests distinct from QSL delivery in email history.

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
