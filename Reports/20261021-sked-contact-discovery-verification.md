# SKED contact discovery — 2026-10-21

Shared board: https://github.com/fact0real/yaam-lab599-shared-board/issues/382

## Delivered behavior

- SKED → Find contacts opens a native, scrollable search surface with a fixed header and invitation action.
- Seven continents, one country or all countries within a continent; the provider's Middle East belongs to Asia here.
- Multiple invitation bands from 160m through 6m, searchable contact results and optional previously-worked-on-any-selected-band filtering.
- All valid email contacts in the active logbook are combined with the provider's top 19 for each country in each of three rankings. Callsigns are normalized and deduplicated. Band history is retained even when the log has no email and the directory supplies it later.
- Most recent usable logged email is preferred within the log; directory contact details take precedence when available. Blank BAND falls back to recorded frequency. The active station's own callsign is excluded.
- Sequential cancellable requests, incremental results, explicit partial-failure reporting, and early stop for missing/malformed credentials, HTTP 401/403 and rate limiting (429). A stopped search preserves results already loaded.
- Country choices can fall back to the countries recorded in the active log if the online catalog is unavailable.
- Search settings collapse after searching to leave contacts visible at compact sizes. Selected bands transfer into the existing reviewed, personalized SMTP composer. Recipient country metadata and persisted band plans remain scoped to each country and station.
- Default invitation asks whether requested bands work for the recipient; it does not claim verified propagation or antenna capability. Custom mail templates remain intact.
- English and Persian manuals updated.

## Verification

`bash Tests/run-sked-discovery-regressions.sh` passed all four suites:

1. SKEDContactDiscoveryRegression: continent mapping; malformed/multiple-recipient/header-injection email rejection; callsign normalization; observed band union; source merge; text and band filtering; latest log email; frequency fallback; self exclusion; history without email; station/country plan isolation and preservation; partial category failures; auth/rate-limit stop; cancellation during a pending request; empty success; invitation band rendering.
2. SKEDDirectoryContractRegression: existing provider request/decode/export contracts.
3. SKEDGeographyContractRegression: existing catalog contract.
4. SKEDPlanningRegression: existing per-contact band history and personalized daily UTC invitation behavior, updated for the revised default wording.

Debug YAAM scheme build passed with signing disabled. `git diff --check` passed.

`python3 Tests/render-sked-discovery.py` renders the actual discovery view with offline fixture state, without constructing AppState or accessing production credentials/logbooks. Inspected light/dark, 700-point compact and 1000-point normal surfaces: initial, selected results, empty results, loading and partial failure. Header and preparation action remain fixed; changing content scrolls. Images are generated under `/tmp/yaam-sked-discovery-visual` and can be reproduced with the script.

## Practical limits

The existing service contract is bounded to 19 operators per country/ranking. This feature does not establish an exhaustive worldwide directory, a recipient's current band capabilities, propagation or availability. Those limitations are stated in the interface and manuals.

No authenticated production provider request, SMTP delivery, end-to-end production sheet interaction or pointer hover was exercised. Online orchestration was verified with injected asynchronous fixtures; production app was compiled. No email was sent and no production logbook was modified during verification.
