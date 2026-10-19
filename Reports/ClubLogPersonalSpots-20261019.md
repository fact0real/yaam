# Club Log Personal Spots — 19 October 2026

Tracking: https://github.com/fact0real/yaam-lab599-shared-board/issues/272

## Reproduction and fix

Inspected the authenticated Personal Spots page in the existing browser session and the installed YAAM UI. Club Log groups spots in separate tables under band headings. The old WebKit extractor stopped after the first nonempty table: YAAM displayed only two 160M spots while the browser also contained 80M through 6M tables.

WebKit now passes the complete rendered HTML to the same production parser used by the HTTP fallback. All band tables are processed. Rows locate their DXCC cell using the Club Log most-wanted link; empty or omitted comment cells do not shift the entity/time mapping. Entity/status text is decoded and whitespace normalized. Invalid frequencies, calls and timestamps are rejected. Frequency formatting uses a fixed decimal locale. Mode inference remains heuristic when Club Log supplies no explicit mode.

A refresh only replaces the list and timestamp after successful parsing. Login pages, HTTP failures and unknown layouts cannot become a successful empty list. A recognized heading plus an explicit no-spots message is accepted as empty. Empty-message and error variants are reconstructed regression fixtures, not claims that these live provider states were induced.

## Verification

- Debug build: `xcodebuild -project YAAM.xcodeproj -scheme YAAM -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build` — succeeded.
- Production-parser regression: `swiftc -parse-as-library Tests/ClubLogPersonalSpotsRegression.swift YAAM/ClubLogSpotsService.swift -o /tmp/yaam-clublog-regression` and its executable — passed. Covers multiple band tables, omitted/empty comments, legacy rows, entities/status, times, frequency formatting, malformed rows, login, empty and unknown pages.
- Existing `LogSearchEngineRegression.swift`, compiled with `LogSearchEngine.swift`, the production spots service and the same inert session stand-ins — passed, including all three legacy Club Log fixture rows.
- Quit the installed app, launched the newly built Debug app, and opened Operator Desk → DX Activity → Club Log Spots using the existing saved session. It displayed **100 spots in nine bands**: 160M 2, 80M 8, 40M 34, 30M 17, 20M 8, 17M 9, 12M 14, 10M 7, 6M 1. Counts sum to 100.
- Verified the last-band 6M spot TG9AJR / PY2MR at 50.313 MHz, FT8, LoTW, 00:55 UTC (04:25 local), and 17M H49A / EA8DOX at 18.072 MHz, CW, Most-Wanted #84, 03:43 UTC against the browser page. Restored the All Bands filter.
- Local screenshot: `build/ClubLogSpots-20261019.png` (not committed). No session cookies, passwords or raw authenticated HTML were exported or committed.

The Debug app was run for verification; `/Applications/YAAM.app` was not replaced and no public release was made. The authenticated WebKit path was exercised live; HTTP fallback failure states were not induced against the provider. No Tune/PTT/QSO upload action was used.
