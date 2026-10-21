# SKED: unworked countries and operators per country — 2026-10-21

Board: https://github.com/fact0real/yaam-lab599-shared-board/issues/383

## Behavior

SKED → Find contacts defaults to Europe, all countries, 10m, unworked-country filtering, and 10 operators per country. A matching-country count and expandable country preview are available before network activity. Counts can be changed from 1 to 50.

Eligibility uses every QSO in the active log, independently of operator email and confirmation. It aggregates each record's resolved country and normalized band, falling back to frequency when BAND is blank. It does not collapse a callsign's historical country changes into its most recent country. Multiple selected bands mean no recorded QSO on any selected band. Countries never worked at all come from the complete geography catalog. Missing-band QSOs and unresolved country records are explicitly identified as incomplete history.

Country cards show operator suggestions, requested count, directory coverage and missing-band history. Countries remain visible without returned email contacts, during queued/loading work, on partial failures, and after stopping. A full empty result is distinct from a failed or unperformed request. The local-only geography fallback explicitly says that it cannot discover countries absent from the log.

Operator suggestions are normalized and deduplicated, prefer ranking order, exclude the station itself, and are bounded separately by country. Text searches preserve explicit selections, including choices outside the initial recommendation list. Bulk selection preserves those choices and cannot exceed each country's selected limit. Shrinking the limit trims selections deterministically. A separate Clear action remains available. The existing operator-history filter is retained when unworked-country filtering is off; its search scans all rankings rather than stopping on unrelated operators.

The directory loader requests rankings sequentially and stops additional rankings for a country once enough eligible email contacts are available. Partial/failed/check-complete/suggestion-target-reached states remain distinct. Existing cancellation, auth failure and rate-limit handling are retained. No directory lookup is made for a country excluded by log history.

Invitations continue through the existing reviewed composer with recipient-specific country metadata and requested bands. A changed active log invalidates preparation until the search is reopened; the parent also checks the revision at the handoff. Active station changes close and discard the discovery selection.

## Verification

`bash Tests/run-sked-discovery-regressions.sh` passed five suites:

- SKEDCountryDiscoveryRegression: unconfirmed/no-email QSOs; normalization; frequency fallback; same-callsign country changes; unknown band/country accounting; never-worked countries; single/multiple-band eligibility; empty selection/empty log; ranking and per-country limits; empty country preservation; text search before capping; self and duplicate exclusion; selection preservation and limit reduction; fetching only eligible countries; complete-empty versus partial/failed coverage; early ranking-stop once enough emails exist; flag rendering.
- SKEDContactDiscoveryRegression: contact merge, email validation, local log extraction, station/country plan isolation, asynchronous failures and cancellation, invitation rendering.
- SKEDDirectoryContractRegression: provider request/decode/export compatibility.
- SKEDGeographyContractRegression: geography catalog compatibility.
- SKEDPlanningRegression: per-contact history and personalized daily UTC invitations.

Debug build of the YAAM scheme passed with signing disabled. Whitespace verification passed. Release build and installation are verified separately at completion on the board card.

`python3 Tests/render-sked-discovery.py /tmp/yaam-country-sked-visual` renders the actual production discovery view with offline fixture state, without AppState, credentials or a production logbook. Inspected compact (700-point) and normal (1000-point), light/dark views covering initial criteria, selected grouped countries, zero email contacts, all countries already worked, loading, partial failure and stale log. Country flags and semantic text remain visible; header and preparation actions stay fixed while content scrolls.

## Limits

Country coverage follows the geography catalog and its country identifiers. The operator service supplies bounded top-19 rankings, not a worldwide directory. A requested count is a maximum and cannot create missing email contacts. Band history only describes recorded QSOs, not current capabilities, propagation or availability. Historical records with missing band or unresolved country data need user review.

Authenticated production directory calls, real SMTP delivery, production sheet interactions and pointer hover were not exercised. Service behavior was tested using asynchronous injected fixtures. No email was sent and no production log was modified by the verification fixtures.
