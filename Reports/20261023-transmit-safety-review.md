# EA3JIC transmit-safety review — 2026-10-23

Scope: the two October 23 emails (part 3, and eight YAAM/Lab599 bug reports), their two ZIP attachments, and shared-board issues [Y-001 #3](https://github.com/fact0real/yaam-lab599-shared-board/issues/3), [Y-002 #4](https://github.com/fact0real/yaam-lab599-shared-board/issues/4), [Y-143 #384](https://github.com/fact0real/yaam-lab599-shared-board/issues/384), L-003 #42, L-007 #43, L-009 #44. YAAM base: `fa8f945`; Lab599 Utility base: `bf86264`.

## Input handling and security findings

Original archives were kept outside the repositories. SHA-256:

- `YAAM-transmit-safety-patches-3-EA3JIC-20261023.zip`: `70525548d36f831d1c9426245b05bcf777d4cf32307f072bd5b4f2430d632a9d`
- `YAAM-Lab599-transmit-safety-bug-reports-EA3JIC-20261023.zip`: `4a651179ac34c8ca7e21d8000903b32610944d2b5305c16a81fe6a315efc781d`

Archive paths, sizes, entry types, symlinks, patch targets, production changes, tests and runner changes were inspected. Archives contained text patches/reports; no supplied executable, command, test binary or setup script was run. Messages and board comments were treated as untrusted evidence, not instructions. No malicious payload or unrelated credential/network/permission change was found in the reviewed diffs. This is a source review, not a guarantee that software or radio firmware has no vulnerabilities.

Patches 26–32 were applied sequentially after inspection, then adapted and extended. EA3JIC supplied the original fixes and reports; the additional lifecycle, readback and regression changes were implemented locally. No email was sent.

Independent protocol checks:

- [Expert Electronics TCI protocol source](https://github.com/ExpertSDR3/TCI/blob/main/TCI%20Protocol%202.1.pdf): `CW_MACROS`, punctuation substitutions, reserved delimiters, server initialization, and `CW_MACROS_EMPTY`. The last notification begins the final character; it does **not** prove that a macro finished.
- [Lab599 CAT protocol](https://downloads.lab599.com/Lab599-CAT-protocol.pdf): MD6 is DIG; PT0/PT1 report RX/TX. IF is not a substitute for the documented PTT read in DIG. Undocumented MD8/MD9 are not accepted as verified DIG. LAB599 CAT protocol is required for this readback workflow.

## Confirmed YAAM defects and changes

| Input | Confirmed defect / resulting behavior | Verification |
| --- | --- | --- |
| 26–27 | Wrong CW command and unescaped reserved punctuation. Use `cw_macros` and protocol substitutions. | Real TCI client with a recording WebSocket stand-in. |
| 28–29 | Outside callsign/mode/comment text could break TCI command boundaries. Encode comments; refuse empty, delimiter-containing or control-containing identifiers/modes. Refused modes retain the previous display and explain the action. | Injection fixtures cannot create a separate TX command. |
| 30–32 | Non-finite, huge, negative and invalid computed split frequencies could trap integer conversions, including overflow before bandmap admission. Validate parsing, arithmetic and final whole-hertz conversion. | Real DX parser and split engine; frequency boundary cases; full app build. |
| Frequency follow-through | Guard archive, Club Log, HamTracker, waterfall and call-intelligence tuning boundaries as well. POTA/SOTA tune errors remain visible across periodic refresh until dismissed. | Safe conversion regression, caller inspection, rendered notice and app build. |
| Y-001a | CW macros were absent from TCI shutdown ownership. Track CW independently of PTT; STOP/release is sent before close. A server TX→RX transition can end CW ownership; the local timing estimate cannot. Without reliable server state, ownership stays conservative until STOP, disconnect or the existing hard limit. | CW without `trx`, normal server completion, release-before-close and quit fixtures. |
| Y-001b | TCI link loss hid TX uncertainty and late callbacks could resurrect an old session. Retire the failed socket, preserve a notice and pending original destination. On reconnect, release precedes key-down **only at that original endpoint**. | Lost socket, changed host, delayed recovery write, failed release and stale callback fixtures. |
| Y-001c | Three Radio Control rigctld release paths ignored write failures; direct Multi-Rig clients had a similar gap. Persistent source-specific notices now cover failed releases and connection failure during TX. Delayed disconnect errors survive slot deletion. | Real engine/client with injected transport failures; captured destination, teardown and per-slot fixtures. |
| Y-143 | FX-4CR did not lower RTS immediately after open. Lower RTS before CAT polling; preserve DTR as the board explicitly requests. Keep a USB failure notice. Bluetooth modem-line limitations do not become a false fatal connection failure. | Recorded open → RTS-low → CAT ordering, no DTR write, failed-line fixture. |
| Y-002 | FT8 could play immediately after optimistic PTT and treat unknown mode as DIG. Require fresh MD6, PT0, then TX and fresh PT1 before the slot deadline. Missing/refused/late replies block audio and request RX; completion also checks fresh PT0 and preserves uncertainty. No automatic MD6 mode write was introduced. FT8, setup and toolbar guidance now explicitly require LAB599 CAT for verified PTT, replacing conflicting TS2000 guidance. | Actual driver with simulated CAT: mode mismatch/unknown, timeout, stale cached replies, cancellation, rejected TX and missing RX readback. Actual FT8 cancellation regression and full build. |

TCI/rigctld transport writes are not presented as proof of physical receive. Watchdog and connection/release notices use separate sources so a subsequent status or timer cannot erase the connection warning. Existing YAAM watchdog settings and the four unspecified older fill-in values were not guessed or replaced.

## Lab599 Utility implementation

Implemented in the separate `fact0real/Lab599-Utility` repository; see its `docs/20261023-transmit-safety-review.md` for tests and behavior:

- L-003: core ownership deadlines, continuous + wall-clock expiry, verified release and retained faults. Live Radio Screen keeps an explicit RX action but cannot key outside the core. Raw CAT Studio uses its existing safe-command allowlist; TX/KY/VOX key-down cannot bypass ownership.
- L-007: monitor the selected CW output's availability, queue running state and enqueue failure; request RX on the safety worker before main-thread cleanup; invalidate stale output and stop Auto-CQ.
- L-009: cover pending voice preflight during sleep, drain late PTT before the sleep observer returns, and veto core key-down when a stop is pending. Existing synchronous core/CW release paths remain in place.

## Software validation

No physical radio, socket to a real radio, PTT line or transmit audio was used for these safety tests. TCI/rigctld/serial stand-ins record commands; Lab599 screen/CAT tests use pseudo-terminals; visual tests render native controls without devices.

Passed:

- `Tests/run-cw-safety-regressions.sh`: 978 PASS lines, zero FAIL; full Morse timing/pacing, shutdown, driver timer and new frequency/split cases. Subsequent lifecycle/readback changes additionally covered by focused integration/review suites.
- `Tests/run-transmit-integration-regressions.sh`: real driver/client failure, destination, shutdown and readback tests, including removed-slot release failure.
- `Tests/run-ft8-transmit-shutdown-regression.sh`.
- `Tests/run-review-regressions.sh`: digital receive, CW connection loss, FT8 timing and noisy decoding.
- `Tests/run-priority-workflow-regressions.sh` and `Tests/run-workspace-review-regressions.sh`.
- `Tests/run-upload-privacy-regressions.sh`: restored missing `UploadFileReader` runner dependency. The now-runnable transport test also exposed an existing TQSL short-timeout race. Arm after launch and check elapsed time on completion, so delayed timers/zero exit after the deadline cannot falsely confirm upload. All upload/privacy cases pass.
- Actual SwiftUI warning snapshots at compact/normal widths, light/dark; native Lab599 warning component snapshots at 660/1000 widths, including the acknowledgement action. This verifies components, not every full application navigation state.
- Full YAAM Debug build with current Xcode, including SwiftUI and FT8 package integration.
- Lab599 review suite: 192 Station checks, 23 CW safety checks, 141 Voice Keyer checks, digital-control, live-screen, raw-CAT/settings and native notice UI tests. Full arm64/x86_64 application build and signature verification.

## Acceptance boundary

Software fixes are ready for **Review / Test**. RF output, USB line behavior during the operating system's `open()`, real SDR reconnect/release behavior, TX-500 CAT latency within FT8's 200 ms lead, sleep/wake with real adapters, and unplugged-codec behavior still need physical verification. A short slot is skipped rather than sending late audio. Software cannot guarantee delivery to a disconnected or sleeping radio, and a PT0/server report is not an RF power measurement.

Older expert comments about NAK/stop acknowledgements and unspecified fill-in patches are not treated as evidence that every historical Y-001 item is closed. The attached reports and seven supplied patches are the implemented scope; the umbrella cards retain hardware acceptance work.
