# Daily rank history — 18 October 2026

## Cause

The old monitor only captured a rank when its page appeared, Track was clicked,
or Refresh was clicked. Closing YAAM stopped collection. Its horizontal axis
contained observed dates only, so a ten-day gap looked like one step. Movement
between the two most recent samples was called “today” or “24h” even when those
samples were several days apart. The rank service had no historical table/API.

## Result

- Rank Service now keeps an authenticated account watchlist (station plus up to
  eight rivals) and a separate UTC daily observation table.
- A Docker Compose collector runs independently of YAAM, checks every 15 minutes,
  skips calls already successfully observed that UTC day, and retries failures.
- Only live leaderboard responses with a matching callsign and a positive rank
  become observations. Cached, estimated, failed or empty replies do not create
  dates. The current-rank endpoint no longer creates undated history in YAAM.
- YAAM synchronizes up to 366 days on launch, wake, every 15 minutes while running,
  on Track/untrack, and on Refresh. Overlapping requests are coalesced. If the
  station or watchlist changes during a request, its result is discarded and
  another sync runs. Existing observations remain available offline.
- The chart offers Daily rank (default), Daily change and Since baseline. Its
  90-day axis includes calendar gaps through today; lines break at missing days.
  A daily change needs consecutive UTC dates. The today banner additionally needs
  current observations. Comparisons require owner/rival observations on matching
  dates; an older matched gap is not displayed as the latest gap.
- Each row shows its observation date. Sync status and pending calls appear above
  the chart, including at compact widths.
- Preferences and an atomic JSON cache both retain local history. Legacy local
  calendar-day buckets are preserved during migration; new observations use UTC.
  File saves run on a serial background queue. No credentials enter history files.

## Data recovery on this Mac

Only rank-related data was read from the user and sandbox preference files.
There were 298 and 282 observations respectively; merging the latest observation
per callsign/calendar day recovered **306** actual observations. Both original
history arrays and the merged recovery JSON are retained in
`build/rank-history-review/`. The merged cache was placed in both existing YAAM
Application Support locations; the new app merges it on launch. The preference
files and other app settings were not rewritten during recovery.

Between 8 and 18 October, records exist for **8, 15, 16, 17 and 18 October**.
There are no recovered observations for **9–14 October**. No values were invented,
interpolated, copied backward or uploaded as historical server observations.

## Server activation and live check

The service was deployed to the existing QRZ Rank server after backing up its
application files and database in `/opt/qrz-project-backups/rank-history-20261018`.
The new collector and existing web service are running. The site returned 200;
the history endpoint returned 401 without authentication. YAAM's existing Rank
Service credential was accessed through CredentialVault without printing it and
used to register EP2AES and the seven requested rivals.

The first independent collection stored seven live observations for 18 October:
EP2AES, EP2LMA, EP4HR, EP5APP, EP5MMS, EP6DSP and G0JHC. An authenticated desktop
sync then retrieved and validated those seven observations over HTTPS.
EP2DES's indexed record has an empty logbook ID (`bid`); its previously stored
rank therefore was not copied into today's server history. It remains pending
and is retried. An attempt to inspect its public QRZ profile timed out.

The watchlist is shared by clients using the same API account; the last accepted
complete replacement controls collection. Revoked tokens or inactive accounts
are excluded by the collector. History retrieval does not consume live lookup
quota. Removing a watch stops future collection for that account; past local
observations remain available.

## Verification

- Focused Swift history regression: calendar gaps, daily/stale comparisons,
  deduplication, chart modes, legacy decoding, cache save order/corruption recovery,
  authenticated request encoding and response validation.
- Existing QRZ Rank API contract regression passed with its source compiled
  directly (only the module import was removed in a temporary test copy).
- Eleven Python regressions: request/account boundaries, watch limits, UTC days,
  failed-source handling, row identity, read bounds and collector behavior.
- A disposable MariaDB database in the deployed runtime verified schema creation,
  actual bearer authentication, registration/history reads, daily deduplication,
  chronological upserts, worker behavior and untracking; it was dropped afterward.
- Isolated native SwiftUI render harness uses the actual monitor/chart code,
  synthetic observations and a temporary preference suite, without AppState or
  radio startup. Light/dark, 760×500 and 1620×940, all three display modes, empty,
  loading and error states were rendered. Selected-point/hover interactions were
  not exercised in a running full YAAM window.
- Debug and Release builds and artifact signature checks are recorded with the
  local output. The review build is for Apple Silicon and has a local ad hoc
  signature with the existing sandbox entitlements; it is not notarized or
  published as an update.

Daily collection depends on server availability, a valid QRZ session and a live
leaderboard entry. A missed day without a genuine observation remains a gap;
neither the current-rank API nor the new collector can reconstruct unrecorded past
QRZ rankings.

## Follow-up: operator growth dashboard (#267)

The later October 18 redesign replaces the all-stations absolute-rank monitor
with a focused owner journey and a selectable two-station growth race. Periods
are 7/30/90 days or all recorded history. Comparative growth uses identical
observed UTC days for both stations; percentages use their respective ranks
on the same first shared day. Rival cards report the change in their rank gap,
with the shared date range shown explicitly. Existing collection, cache and API
behavior are unchanged. Missing observations remain gaps, and a single point
never becomes a growth estimate. The original chart modes described above refer
to the earlier implementation; the current operator guide is in USER_MANUAL.md.

Verification: RankGrowthRegression, the existing RankHistoryRegression, isolated
light/dark dashboard renders at 760×500 and 1620×940 plus comparison, empty,
one-day, loading and error states, and the YAAM Debug build. Render fixtures are
synthetic and start no AppState or network client. No live service or installed
application state is modified by those visual tests.
