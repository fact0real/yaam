# Selected YAAM Notes priorities — validation, 2026-10-19

Scope: shared-board #295, #296, #292, #293, #297, #298. No live email was sent and no radio was keyed.

## Result

- Unconfirmed recorded QSOs can open the QSL delivery workflow. The composer prepares a PDF before enabling Send, exposes that exact attachment for preview, refuses missing/failed generation and rejects a station-profile switch. Only successful delivery marks QSL_SENT; confirmation fields are untouched.
- Rank email subjects follow available evidence. Unknown, zero, negative and malformed ranks are omitted. Missing ranks no longer produce fabricated standings or congratulations about nonexistent figures. Available observations are explicitly described as potentially older.
- Digital waterfall conversion now runs on a serial actor. Rolling history colorizes only a newly appended row; reset, dimension changes and skipped revisions rebuild safely. Decoder samples, passes, slot scheduling and TX interlocks are unchanged.
- Log pinning uses the compositor rather than quantized horizontal-offset state passed through the entire row tree. Both pinned header and body use the same modifier. Rank-history series are cached by their actual inputs; growth analyses no longer sort/rebuild during every chart hover or unrelated view update.
- Bandmap labels explicitly identify spot-derived illustration. CAT connection does not claim RF measurement, S-meter units were removed from the illustrated graph, fake noise animation was removed from the upper graph, empty input is explicit and simulated spot sources are labeled. Persisted mode raw values remain unchanged.
- Next Credit is available above the Log Table. It operates on the active station's records, deduplicates QSO identities, excludes confirmed records, scores marginal country-band/grid/award milestones and exposes configurable weights plus reasons. A credit cannot be claimed again later in the same queue. Likelihood uses disclosed route/prior-confirmation evidence, never a percentage. Work is background/cancellable and refreshes with log/profile/weight changes. Review opens an editable reminder or the existing callsign inspector when no address is available.

## Checks executed

Debug YAAM scheme build with code signing disabled: **passed**.

```sh
swiftc -O -parse-as-library YAAM/QSLMailPolicy.swift Tests/QRZEmailTemplateRegression.swift -o /tmp/yaam-mail-policy
/tmp/yaam-mail-policy
swiftc -O -parse-as-library YAAM/NextCreditEngine.swift Tests/NextCreditRegression.swift -o /tmp/yaam-next-credit
/tmp/yaam-next-credit
swiftc -O -parse-as-library YAAM/FT8WaterfallRasterizer.swift Tests/FT8WaterfallRasterRegression.swift -o /tmp/yaam-waterfall-raster
/tmp/yaam-waterfall-raster
swiftc -parse-as-library Tests/RankGrowthRegression.swift YAAM/RankGrowthAnalysis.swift YAAM/RankHistory.swift YAAM/QRZRankAPIContract.swift YAAM/QRZRankService.swift -o /tmp/yaam-selected-rank-growth
/tmp/yaam-selected-rank-growth
swiftc -parse-as-library YAAM/BandmapProvenanceNotice.swift Tests/BandmapProvenanceRegression.swift -o /tmp/yaam-provenance
/tmp/yaam-provenance
```

All four passed. `BandmapProvenanceRegression` also passed for Demo, Manual Sim, synthetic/emulator and live sources. Next Credit additionally excludes stale unconfirmed copies of already-confirmed QSO identities. Also ran `StationPrivacyRegression` with its documented standalone compile command: passed, including profile/empty-station PNG and two-page PDF exports.

Measured workload (same Mac, optimized standalone binaries):

- 400-row × 512-bin waterfall, 100 appended frames: approximately **9 ms incremental versus 44 ms full conversion**, identical output pixels; **500 versus 40,400 colorized rows** including initial history. This measures raster preparation, not whole-application CPU or decoder sensitivity.
- 10,000 candidate contacts, top 100 marginal-credit suggestions: approximately **125 ms**. Includes deterministic tests for shared credit, duplicate identity, missing evidence, invalid weights and US state eligibility (including Alaska/Hawaii).

## Visual review

Rendered the production `NextCreditContent`, `BandmapProvenanceNotice` and `PinnedLogColumns` in an isolated NSHostingView harness, with no account/database startup. Inspected 28 images covering light/dark, 620/960 widths, queue loading/empty/ranked/expanded priorities, offline/CAT/demo notices and simultaneous horizontal/vertical scroll. Pinned callsigns remained at the left while the trailing columns scrolled.

Native full-app capture failed with ScreenCaptureKit error -3811; the isolated production-component renders do not certify every full-window overlay or hover state. The new features still need an interactive pass in the user's normal log, and sustained busy FT8/FT4 reception profiling on representative hardware. No claim is made that the historical >90% whole-app CPU symptom or all large-log frame stalls are fully eliminated. Keep these cards in Review / Test until that acceptance pass.
