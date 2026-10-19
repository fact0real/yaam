# EA3JIC patch 61 email audit — 19 October 2026

Tracking: [#269](https://github.com/fact0real/yaam-lab599-shared-board/issues/269). Source baseline: `f0f4df5`, YAAM 1.37.39 (189). Delivery: YAAM 1.37.40 (190).

Reviewed the requested email and the locally available matching `EA3JIC-YAAM-61-open-items-20261017` attachment. Every supplied SHA-256 manifest entry matched. Attachment scripts and patch-application instructions were treated as proposals, not executed. No private message content, credentials or attachment archive is committed. The earlier [18 October review](EA3JIC-20261017-review.md) documents the original implementation decisions; the shared board already contains most of these activities.

## Item-by-item disposition

All links below refer to issues in `fact0real/yaam-lab599-shared-board`. Completed means the stated software scope, not certification against every radio/provider.

| Attachment item | Current source evidence and disposition | Board card |
| --- | --- | --- |
| Patch 61: upload privacy | Already implemented: `QSLUploadStatus.uploadFields` positive per-destination allowlists, three opt-ins default off, transport re-filtering, minimal LoTW projection and private TQSL copy. Local exports retain fields. Offline privacy suite re-run in this audit. | [#222](https://github.com/fact0real/yaam-lab599-shared-board/issues/222), [#255](https://github.com/fact0real/yaam-lab599-shared-board/issues/255), Done |
| 1.1 Active station uploads | Already implemented in cited Hub/full-sync paths: `UploadStationPolicy.matches`, re-checks after suspension and Wavelog own-log/remote-station checks. | [#223](https://github.com/fact0real/yaam-lab599-shared-board/issues/223), Done |
| 1.2 Wavelog key rights | Already implemented: non-mutating `check_auth`, `r`/`rw` distinction and refusal of read-only full sync. | [#226](https://github.com/fact0real/yaam-lab599-shared-board/issues/226), Done |
| 1.3 Entitlements | Release debugger access removed, entitlement purposes documented; Bluetooth removal remains unproven on hardware. New open follow-up separates that unfinished scope from the completed mitigation. | [#227](https://github.com/fact0real/yaam-lab599-shared-board/issues/227), partial; [#270](https://github.com/fact0real/yaam-lab599-shared-board/issues/270), Todo |
| 2.1 FT8 DT | Already implemented: `FT8StationDecoder.ft8EpochCorrection = 0.66`; FT4 unchanged. | [#237](https://github.com/fact0real/yaam-lab599-shared-board/issues/237), Done |
| 2.2 FT8 SNR ceiling | Still open in pinned ft8-808. No arbitrary offset or unreviewed dependency update. | [#80](https://github.com/fact0real/yaam-lab599-shared-board/issues/80), Todo |
| 2.3 RR73 bits | Still open in pinned ft8-808; requires independent 77-bit/interoperability fixtures. | [#81](https://github.com/fact0real/yaam-lab599-shared-board/issues/81), Todo |
| 3.1 Wavelog routes | Already implemented: `qso`, `get_contacts_adif`, keyed `station_info`, pagination/error handling, no credential redirects. | [#231](https://github.com/fact0real/yaam-lab599-shared-board/issues/231), [#232](https://github.com/fact0real/yaam-lab599-shared-board/issues/232), Done |
| 3.2 TQSL status | Already implemented: only exit 0 succeeds; 8/9/14 leave the batch unmarked. Offline real-process stand-in re-tested. | [#233](https://github.com/fact0real/yaam-lab599-shared-board/issues/233), Done |
| 4.1 Automatic ADIF save | Already implemented: main-actor snapshot, serialized writes and visible failure reporting. | [#225](https://github.com/fact0real/yaam-lab599-shared-board/issues/225), Done |
| 4.2 Silent digital TX | Refusal before PTT is implemented; actual native playback/protocol completion remains unfinished. New follow-up preserves this distinction. | [#238](https://github.com/fact0real/yaam-lab599-shared-board/issues/238), partial; [#271](https://github.com/fact0real/yaam-lab599-shared-board/issues/271), Todo |
| 4.3 Contest frequency | Already implemented: actual finite, valid, band-matching input required; no inferred frequency. | [#239](https://github.com/fact0real/yaam-lab599-shared-board/issues/239), Done for this item |
| 4.4 rigctld client reference | Already implemented: keyer defaults to `RigControlClient.shared`, independent of opening Operator Desk. | [#240](https://github.com/fact0real/yaam-lab599-shared-board/issues/240), Done |
| 5.1 Varicode | Already implemented: standard 128 unique entries and independent problem-character anchors. | [#235](https://github.com/fact0real/yaam-lab599-shared-board/issues/235), Done |
| 5.2 PSK symbol clock | Still open. Requires timing/carrier recovery and independent offset/rate/noise fixtures. | [#79](https://github.com/fact0real/yaam-lab599-shared-board/issues/79), Todo |
| 5.3 Hell pixel rate | Already implemented: fractional intervals and buffer tails preserved. | [#236](https://github.com/fact0real/yaam-lab599-shared-board/issues/236), Done |
| 5.4 Streamed callsigns | Already implemented: bounded pending-word state across decoder fragments. | [#234](https://github.com/fact0real/yaam-lab599-shared-board/issues/234), Done |
| 6.1 Radio refusals | Still open: serial reply correlation and rigctld capability/refusal handling require transport-specific evidence. | [#6](https://github.com/fact0real/yaam-lab599-shared-board/issues/6), [#5](https://github.com/fact0real/yaam-lab599-shared-board/issues/5), Todo |
| 6.2 Disconnect during CW | Implemented destination-specific 200 ms connection watcher; cable-loss physical behavior still needs hardware testing. | [#230](https://github.com/fact0real/yaam-lab599-shared-board/issues/230), Done for mitigation; [#12](https://github.com/fact0real/yaam-lab599-shared-board/issues/12), [#90](https://github.com/fact0real/yaam-lab599-shared-board/issues/90), open hardware checks |
| 6.3 TX-500 framing/SM | Documentation corrected; saved/default port choices preserved pending hardware validation. | [#77](https://github.com/fact0real/yaam-lab599-shared-board/issues/77), Todo |

## Section 7 coordination

The attachment reserves these projects to its author. Existing board cards already track them, so no duplicate cards were created and no message was sent to the author.

| Reserved activity | Existing card |
| --- | --- |
| Late flrig refusal must not count as sent | [#7](https://github.com/fact0real/yaam-lab599-shared-board/issues/7) |
| rigctld STOP capability and replies | [#5](https://github.com/fact0real/yaam-lab599-shared-board/issues/5) |
| Slow-keyer pacing | [#11](https://github.com/fact0real/yaam-lab599-shared-board/issues/11) |
| Universal PTT watchdog | [#3](https://github.com/fact0real/yaam-lab599-shared-board/issues/3) |
| Monotonic telemetry watchdog/reconnect | [#8](https://github.com/fact0real/yaam-lab599-shared-board/issues/8) |
| rigctld emulator resource limits | [#9](https://github.com/fact0real/yaam-lab599-shared-board/issues/9), implemented in this audit under the repository owner's explicit request |
| Radio ownership/keep-alive/auto-information | [#10](https://github.com/fact0real/yaam-lab599-shared-board/issues/10) |
| TX-500 PTT acknowledgement/FT8 audio/MD0 | [#4](https://github.com/fact0real/yaam-lab599-shared-board/issues/4) |
| Conditional RTS/DTR PTT | [#25](https://github.com/fact0real/yaam-lab599-shared-board/issues/25) |

## Priority security delivery

`HamlibRigctldServer` remains loopback-only. Defaults now cap accepted clients at 8, command-line bytes at 4096, pending response bytes per client at 65536, and non-empty commands per client at 256 per monotonic second. Excess connections are closed; oversized/invalid UTF-8/NUL-containing input, output backlog and command floods close the offending session without executing its remaining packet. Input is framed before decoding and memory does not grow with an unterminated line.

Server and session state is confined to one queue. Accept batches yield after 16 sockets. Partial writes remain queued and resume on writability; slow consumers cannot create an unbounded response buffer. Stop cancels both socket sources, releases their descriptor only after cancellation handlers finish, and avoids the old weak-capture descriptor leak. No transmit interlock or physical radio path is enabled by this change.

The high-priority FT8/PSK issues are still open because a cosmetic offset, guessed protocol bit change or merely starting an incomplete waveform would not satisfy their acceptance criteria. Their existing cards remain open rather than being marked Done by this audit.

## Verification

- `RigctldServerSecurityRegression`: real loopback connections and socket pairs; excess clients, exact/over-limit fragmented frames, invalid UTF-8, CRLF/batched normal commands, command floods, discarded trailing PTT commands, stop/restart, lossless partial writes, slow-consumer closure and exactly-once session close. Callbacks are stand-ins; no radio/audio engine is constructed.
- `run-upload-privacy-regressions.sh`: passed 19 allowlist + 52 switches + 100 sync checks, plus transport/privacy, station identity, Wavelog rights/routes/pagination and real TQSL stand-in process checks. No provider upload was performed.
- `run-review-regressions.sh`: passed standard Varicode, fragmented callsigns, safe unavailable TX, Hell pixel rate, CW disconnect/replacement, FT8 DT calibration and expanded/noise-only decoding checks.
- `run-workspace-review-regressions.sh`: passed visible ADIF write failures, serialized snapshots, local-field preservation and contest-frequency admission checks.
- `ReleaseEntitlementsRegression`: source checks passed for all nine documented entitlements, sandbox enabled and debugger privilege excluded. Bluetooth hardware validation remains #270; no new signed Release entitlement certification is claimed.
- YAAM Debug scheme build with signing disabled succeeded; no UI layout change was introduced. Production logbooks, provider accounts, radio hardware and transmit audio were not used in these tests.

The local build is not a public release binary. Publication status and commit links are recorded in #269 and #9 after push. Open hardware/dependency work remains on the board and is not closed by this audit.
