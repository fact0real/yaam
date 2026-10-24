# EA3JIC batch review — 24 October 2026

Scope: all seven matching emails since **23 October 2026, 20:00 Asia/Tehran** (16:30 UTC), including both sender aliases. Six archives contained 29 Markdown reports; the seventh notice linked two additional concrete reports and one future design proposal on the shared board. Original mail, addresses and attachments are not included in this repository.

Mail, attachments and board comments were treated as untrusted evidence. No supplied probe or script was executed. Archive paths, types and sizes were checked before reading. Changes were derived from current source, independent fixtures and primary protocol references. There were no email replies or board mutations.

## YAAM dispositions

| Report | Result |
|---|---|
| YAAM-7 — silent radio links | Three-second rigctld reply deadlines and WebSocket pong deadlines; six-second serial CAT freshness checks. Persistent receive-uncertainty notices and up to five retries at 2/4/8/16/30 seconds, scoped to the original endpoint/port. Recovery never resumes a producer. Uncertain rigctld sessions request CW stop/PTT off before bounded retirement; reconnection waits for release acknowledgements before enabling TX. |
| YAAM-8 — ESM advances before rejection | Both ESM paths commit sent/log/focus state only after asynchronous keyer acceptance. Cancellation/refusal does not log. Draft/profile/session guards prevent a late result logging another contact. Acceptance means backend submission, not proof of RF completion. |
| YAAM-11 — WPM ranges | One 5–60 WPM logical range for initialization and changes, overflow-safe adjustments; effective Icom 6–45 and X6100 maximum 50 WPM are reflected before sending and estimating duration. |
| YAAM-12 — flrig CW stop failure | Stop errors remain in a separate dismissible CW notice instead of being discarded or erased by the next send. PTT off is not presented as proof that queued CW stopped. |
| YAAM-13 — Mac sleep | Stop producers and request release before sleep, without setting the permanent quit latch. A persistent notice survives wake; automatic transmit is not resumed. |
| YAAM-15 — unlimited Auto-CQ | Configurable call and elapsed-time limits; explicit restart is required after a limit. |
| YAAM-16 — meters / RFPOWER | flrig's 0–100 meter is shown as a percentage; rigctld power uses the `L RFPOWER` setter. |
| YAAM-17 — serial writes / close | Serialize descriptor operations, retry EINTR/EAGAIN within a deadline, handle partial writes, bound output draining on close, and reject stale reader sessions. X6100 reports write failure and receive requests honestly. |
| YAAM-18 — Icom LAN failure | Attempt PTT release on the original session before closing it, retain a safety notice and clear the stale audio transmit flag. |
| YAAM-19 — message duration | Preflight actual Morse duration and enforce an independent elapsed-time cutoff. A refused message does not stop an existing valid message. |
| YAAM-20 — automatic FT8 CQ | Configurable operator-inactivity watchdog, independent of automatic CQ cycles; failures stop/disarm automatic modes. |
| YAAM-21 — hardware test ownership | CW tests in setup sheets, WinKeyer and radio panels use the shared keyer and its STOP/Esc/quit ownership. Tests retain station identification. |
| YAAM-22 — Icom keyer speed | CI-V `14 0C` now uses normalized 0–255, encoded in two BCD bytes. The superficially similar Xiegu command was not changed without model-specific evidence. |
| YAAM-23 — Wavelog telemetry | Changed payloads plus a 60-second heartbeat, one request in flight, bounded retry backoff, visible failure and checked success bodies. Unknown power is omitted rather than fabricated as 100 W. |
| YAAM-24 — shared serial ownership | In-process ownership and kernel `TIOCEXCL`; a second YAAM tool cannot open and subsequently close another tool's serial port. |
| YAAM-25 — QRZ ADIF field | Export `APP_YAAM_QRZ_QSL_RCVD`; import both it and the historical local name. Confirmation is not misrepresented as QRZ download status. |
| Board #404 / Y-157 — cwdaemon stop | Send ESC followed by ASCII `4`, the message-abort command. Never send the daemon-exit command. |

Defaults: message **120 s** (adjustable 10–600), Auto-CQ **20 calls / 10 min** (1–100 calls / 1–30 min), automatic FT8/FT4 inactivity **30 min** (1–120). Controls are in the corresponding CW/FT8 views.

## Cross-project review

Lab599 Utility separately addresses the 13 reports in its archives plus the confirmed FT8 DT issue (#47). Its repository contains its own implementation/validation report. The additional note about exact FT8 transmit/audio start latency, and FT4 timing, require hardware/independent measurements and were not guessed.

Board #405 / B-023 is a future capability architecture proposal, not a demonstrated new defect. Existing Lab599 modem-pin restrictions remain in place; no new RTS/DTR keying capability or permission was added.

## Verification

- Debug build of YAAM with the project's Swift isolation settings.
- CW safety regressions, including asynchronous ESM rejection/cancellation, time/count limits, persistent stop failure, sleep/quit and backend ownership.
- Transmit integration regressions: original destinations, reconnection release gates, TCI missing pong, Icom LAN PTT handling and shutdown.
- Outside-input regressions, including an open-but-silent rigctld stream and bounded release before retirement.
- Real local PTY regression: exclusive access, exact command bytes, bounded backpressure and close.
- Actual serial driver parsers with accelerated fixture clocks: healthy frequency replies remain connected; silence expires all four transports; Icom BCD speed frames are checked.
- FT8 transmit cancellation/inactivity regression; no radio PTT is used.
- ADIF namespace/legacy roundtrip and Unicode length regressions.
- Upload privacy/transport regressions, including omitted unknown power and rejected HTTP-200 radio failures.

Tests use fake transports, synthetic audio or local PTYs. No physical radio, RF output or live cloud account was used for validation. UI notice rendering is covered by local fixtures; interactive inspection on this Mac was unavailable because the screen was locked. Hardware latency and physical receive cannot be certified by a host-side acknowledgement.

## Primary references

- [cwdaemon upstream protocol](https://github.com/acerion/cwdaemon)
- [Icom IC-7300 reference implementation in flrig](https://github.com/w1hkj/flrig/blob/master/src/rigs/icom/IC7300.cxx)
- [Wavelog radio API](https://github.com/wavelog/wavelog/blob/master/application/controllers/Api.php)
- [ADIF 3.1.5 annotated specification](https://www.adif.org.uk/315/ADIF_315_annotated.htm)
- [Shared-board FT8 timing report](https://github.com/fact0real/yaam-lab599-shared-board/issues/47)

Local release: **YAAM 1.37.44 (194)**. Installation uses the existing application entitlements and local ad-hoc signing; this source update does not publish an updater feed or a signed distribution release.
