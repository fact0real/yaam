# SKED countries, readiness and prepared contacts

Board: https://github.com/fact0real/yaam-lab599-shared-board/issues/394
Backend source: https://github.com/fact0real/qrz-rank/commit/1804b9f and https://github.com/fact0real/qrz-rank/commit/9c3fdb5 (preserves the legacy UK bucket in European division ranking queries).
YAAM release: 1.37.42 (192).

## Resolved defects

- The provider built countries from ranking rows, omitting countries without rows, and defaulted unknown regions to Europe. The server now supplies 248 named countries/territories (52 European), including zero-result countries. Liechtenstein is included. Bonaire and British Indian Ocean Territory are correctly outside Europe; South America's provider `sam` identifier now maps to the discovery `SA` filter.
- Shared country presentation uses English country names and validated flag codes in the discovery and main directory menus, previews and results. SM is San Marino's ISO code (Swedish callsigns with prefix SM belong to SE). Legacy ZE is the provider's UK/2E bucket; its contacts are combined into United Kingdom/GB, rather than shown as a duplicate country with an invalid flag.
- Every log mutation previously invalidated an open discovery sheet, including QSL and rank enrichment. Separate semantic revisions track contact display fields (including NAME/EMAIL) and country/band history (CALL, COUNTRY, BAND, FREQ, QSO_DATE, TIME_ON). Unrelated updates leave search ready; name/email enrichment refreshes displayed contacts without disabling search or clearing explicit choices. Actual log edits automatically rebuild contact/history snapshots off the UI actor, clear outdated choices, and reconcile targets without reopening. Station changes remain isolated and handoff still verifies the current revision.
- Find contacts lives in the fixed footer during criteria selection, including compact windows. After searching, Prepare invitations stays available for explicit valid selections while background data loads. Country and individual selection/Clear controls no longer wait for the entire search.
- Discovery uses one authenticated bounded `/api/v1/sked-ready` request for all three prepared rankings, followed by a single background merge of contacts. It avoids per-country QRZ scraping, repeated main-actor pool merges and old callbacks overwriting a newer search. Local email contacts remain immediately selectable, including during a server failure. Cancel/dismiss/criteria changes invalidate the generation.

## Server work

The deployed backend prepares QSO top 50 plus DXCC/band top 19 in its existing continuous worker, with seven-day negative caching for private/missing emails and targeted cache invalidation. Contact requests only read prepared profiles/cache. Login is required before cached contacts are read; no tokens, local QSO records, or account credentials are sent to new destinations. No email is automatically sent.

A separate server bug classified HB0 as Switzerland before checking Liechtenstein. Its rule was fixed and 100 affected ranking records (99 HB0-prefix plus one portable record) repaired after a restricted before-image backup. Rank scores, email profiles and QSO logs were not changed. Earlier unrelated live changes were preserved; the original dirty backend checkout was not reset or committed wholesale.

Seven backend tests passed in an isolated network-disabled container. Live checks verified the 248-country catalog, every European directory, bq1 compatibility, correct SM/GB names, invalid-input rejection and unauthenticated HTTP 401. Full-Europe processing: first cold read 1.859 s, cached 0.091 s. Removing repeated mail templates reduced payload from 2,140,762 to 448,581 bytes; compact cached reads measured 0.066–0.100 s. These are server processing timings, not guaranteed end-to-end latency.

At verification Liechtenstein had 100 ranked operators and three public emails in its QSO top 19. The app offers up to the requested count using available valid public addresses; it does not invent missing addresses or promise ten operators for every country.

## Validation

- `bash Tests/run-sked-discovery-regressions.sh`: six suites. New coverage checks metadata-only vs real log changes, LI/SM/ZE/DK names and flags, unknown flags, South America, batch authentication/header injection/size/input validation, complete and empty country data, mismatched/incomplete batches, and prepared-pool merging/history/source retention. Existing full-log history, unconfirmed/no-email QSOs, per-country limits, ranking/query, self-exclusion, cancellation, rate limits, CSV and mail planning regressions remain covered.
- `Tests/render-sked-discovery.py`: production SwiftUI view with offline example contacts, compact and normal widths, light/dark, initial/selected/loading/partial-failure/empty/refreshing-history/all-worked states. Fixed footer Find remains visible at 700x440; selection and Prepare remain enabled while loading. No real emails or credentials appear in fixtures.
- Debug and Release builds of the complete YAAM scheme, signing disabled for compilation; installed Release is separately signed with existing app entitlements and verified.
- Native computer-use capture was unavailable in this session (ScreenCaptureKit -3811); visual verification used rendered production SwiftUI fixtures. No RF/PTT or email-send operations were performed for verification.

Server deployment backups: `/opt/qrz-backups/sked-20261023T102117Z/`. Only the five full modules and HB0 insertion were deployed; web and existing enrichment worker restarted successfully. The worker was verified running and preparing profiles.

Installation verification and source revision are recorded in the local YAAM-Installer receipt after installing the Release build into `/Applications/YAAM.app` with a backup of the previous app. User logbook/settings are preserved.
