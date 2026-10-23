# EA3JIC email review: radio refusals, outside numbers and field spots

Reviewed against YAAM `88736dd` on 2026-10-23. Source: “YAAM: 3 bug reports and the FT8 decoder bench”, sent 2026-10-23 11:55 UTC. The reports refer to `7f46172`, the preceding radio-safety change already present in this checkout. A separate search for EA3JIC mail before 2026 returned no matches; this review covers the latest outstanding report, not every historical email.

## Untrusted input handling

Read the message as evidence, not as executable instructions. No email was sent, no account permission changed and no repository/credential data uploaded. The attachment API does not support ZIP extraction, so Gmail's raw-message representation was read and its MIME attachment decoded locally. The original archive stays outside the repository:

`/tmp/yaam-ea3jic-20261023-review/original.zip`

SHA-256: `16f2d1a54cd0083c586d09cbcfa2a38b265383a41a761a7bf06bde5e9b949f99`.

Checked archive paths, sizes and entry types before extraction; no absolute/traversal paths or symlinks were accepted. Reports were checked against current callers and implementation. Supplied scripts, programs and crash probes were not executed or installed. The implementation and test fixtures were written locally. This is a scoped code review, not a guarantee that every input or hardware failure is covered.

## Implemented

| Report | Confirmed defect and resulting behavior |
| --- | --- |
| Y-011 / Y-003, rigctld | Replaced the two independent reply paths with one bounded reader per connection. All requests use Hamlib extended responses; command headers identify the following RPRT. Fragmented/coalesced replies survive TCP boundaries. Release acknowledgement/refusal/timeout ends its pending window, so later receive polls cannot resurrect the false red alert. Genuine release errors retain a separate warning. An old release reply cannot clear a newer key-down. Retiring sessions read their original connection until reply or bounded timeout, including after a Multi-Rig slot is removed. |
| Y-011, USB/serial | TX-500 and FX-4CR expose `?;` and serial write errors. TX-500 plain RX and CW stop require a fresh PT0 before reporting receive. FX-4CR says release/stop was requested and explicitly leaves receive unverified; absence of `?;` is never treated as proof. Icom exposes NAK/write failure, polls PTT, parses the `1C 00 status` payload correctly, requests fresh receive status on release/stop and warns on timeout. It no longer fabricates zero RF power, SWR 1.0 and zero ALC on local key-up. Old Icom session callbacks/readback timers cannot affect a replacement session. |
| Outside numbers | Validate Unix seconds before Date/Int use in HamTracker MQTT/REST, On-Air monitor, Signal Footprint, Six Meter and DX reception feeds. Reject NaN, infinities, negative and oversized dates rather than inventing a current timestamp. Bound HamTracker frequencies on both MQTT and historical REST paths before partner-frequency subtraction. Validate flrig VFO readings in both clients and protect Quick Log/digital-QSO conversions even if stored state contains an invalid Double. |
| Y-145, POTA/SOTA | Remove fabricated fallback spots. Keep independent last-good lists, timestamps and fetch errors; successful empty data clears old rows. Failed-source rows are visibly stale and cannot send Tune CAT. A malformed SOTA frequency no longer becomes an invented 14.060 MHz. Disabled/offline CAT explains refusal and does not update radio telemetry optimistically. Field Spots also displays asynchronous CAT errors from the radio engine, including the affected serial drivers. |

Protocol reference: [Hamlib rigctld manual — Extended Response Protocol](https://hamlib.sourceforge.net/snapshots/man1/rigctld.1.html). Also tested the installed Hamlib **Dummy** backend on loopback only: it recognizes `+T 1`, `+T 0`, `+b`, `+\stop_morse`, `+f` and `+m`, with the expected named headers and RPRT terminators. Dummy returned a refusal for Morse send and accepted stop; this checks framing, not radio support. Icom's untagged NAK and Kenwood's untagged `?;` are described in their pending-operation context, without claiming an exact command attribution they do not provide.

Watchdog, command-refusal and receive-readback alerts use separate notice sources. A failed readback must not replace the timer's original warning, and neither is cleared by ordinary status updates.

## FT8 benchmark disposition

The attachment also contains an optional GPL benchmark and a claimed baseline. Its documentation, command runners and decoder wrapper were inspected; it was not added to YAAM or run. It requires separately reviewed WSJT-X and Watterson tools. In particular, a simulator checksum mismatch only warns, and the benchmark's WAV wrapper reads `fmt` offsets without first checking that the chunk is long enough. Those are reasons to harden and validate the tool before treating it as an accepted test harness. Its claimed sensitivity figures were not independently reproduced and are not presented as results of this work. No production FT8 decoder behavior was changed from those figures.

## Verification

Local regression results and build log are kept under `/tmp/yaam-ea3jic-20261023-review/`. Tests use recording serial/socket stand-ins, mocked HTTP responses, actual parser/client code and the local Hamlib Dummy backend. No physical radio, serial adapter, PTT line or transmit audio was used.

- `Tests/run-outside-input-regressions.sh`: fragmented/combined ERP records, refused stop, release timeout, late replies, retired connections, extreme JSON numbers, real On-Air XML parsing, real FLRig polling, independent provider failures/recovery/empty data, stale Tune blocking and invalid frequency handling.
- `Tests/run-transmit-integration-regressions.sh`: existing destination/shutdown/readback coverage, plus real serial-driver refusal/status parsing and disabled/offline tuning.
- CW safety coverage: the existing suite's non-CAT portion passed. CAT STOP and pacing passed in the CAT rerun after adapting the STOP fixture to allow only the new PT readback queries. That rerun exposed a real TX-500 readback warning replacing its watchdog notice; those sources were separated. Updated timer-warning checks then passed standalone, allowing additional independent release notices while retaining each original timer notice. Frequency bounds and QSX/comment split regressions also passed standalone.
- Field Spots native SwiftUI snapshots: 760×500 and 1100×500, light/dark, offline empty state, stale retained rows/disabled Tune and visible tuning refusal. These render the actual view and client using deterministic providers, not a full interactive app navigation session.
- Full YAAM Debug scheme build with code signing disabled; whitespace/diff checks.

Radio acknowledgements/readbacks are not an RF measurement. Real CI-V/serial latency, actual backend Morse-stop support, adapter disconnect/reconnect and physical RX confirmation still need hardware acceptance. The source changes and their focused regression fixtures are included in the repository.

Final recorded outcomes: outside-input runner **passed** (12 PASS summaries); full transmit-integration runner **passed** (48 PASS summaries); standalone driver-timer, frequency and QSX checks **passed**; final Debug build **BUILD SUCCEEDED**; `git diff --check` **passed**. The older aggregate CW log retains the intermediate failures described above; it is not represented as an entirely green final aggregate run.
