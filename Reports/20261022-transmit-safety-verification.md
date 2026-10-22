# EA3JIC transmit-safety series 17–25: reviewed integration

Baseline: `8180d53`. Coordination: [Y-001 / shared-board #3](https://github.com/fact0real/yaam-lab599-shared-board/issues/3).

The supplied patch series contains genuine bug fixes. It was reviewed as untrusted input and integrated against the current source, with the corrections below. This is an adapted implementation, not a claim that the missing 01–16 series has been applied in full.

## Input and security review

- Inspected all nine unified diffs, including test and runner changes, as text. Only relative `YAAM/` and `Tests/` paths occur; the two paths on each diff agree. No traversal paths, symlinks, executable payloads, binary hunks, credential reads, added external endpoints, shell execution from app code, or instructions to override the user's request were found.
- No command from the email or patch commentary was executed. Git's patch parser was used after path review; prerequisite-dependent hunks and runners were adapted explicitly. Attached scripts were not run directly. The submitted test runners compile reviewed source with recording stand-ins.
- Current source lacks `TXLimits` and several changes assumed by patches 01–16. The integration supplies the necessary finite timing policy and transport cleanup against actual current code. The old N-07/N-11/N-12/N-13 fill-in patches were not provided and were not applied.
- Existing driver defaults are retained: TX-500/FX-4CR/rigctld 14 seconds, Xiegu 15, Icom USB/LAN 16, flrig 120. Requests are clamped to 1–120 seconds; NaN and infinity fail safely to one second. These are application timers, not hardware guarantees.
- Refusal messages do not append arbitrary previous driver output, which could reveal private information. No credential or contact logging was added.

Input SHA-256 hashes are recorded in `20261022-transmit-safety/input-sha256.json`; the original files were left untouched.

## Fixes and deliberate differences

| Patch | Confirmed problem and resulting behavior | Main regression evidence |
| --- | --- | --- |
| 17 | Macros recopied the entire TX box, replaying earlier characters; typed text did not populate the queue correctly. The consumed prefix is tracked. The editor changes only pending text; sent/dropped history is separate, avoiding the supplied patch's ambiguous repeated-text edit heuristic. Abort drops the remainder; idle stop preserves pending text; Clear TX starts a fresh buffer. | `DigitalModemResendRegression`: macros, type ahead, typed start, repeated AAAA/ABAB, Unicode, abort, clear, idle stop. |
| 18 | Quit had no inventory of non-CW transmit owners. Four serial drivers, direct rigctld clients, Icom LAN instances, Radio Control, TCI, FT8/FT4, PSK/RTTY and audio-only producers register weak ownership. Dead entries are pruned. | `TransmitShutdownRegression`, `TransmitShutdownRegistryRegression`, `FT8TransmitShutdownRegression`, audio-only and network integration checks. |
| 19 | Quit stopped only CW. A shutdown latch now refuses new TX, synchronously quiesces CW, stops scheduled/audio producers before transports, requests all releases, and allows up to two seconds for queued network work. | `QuitReleasesTransmitRegression`; actual FT8 scheduler, TCI, Icom LAN and Radio Control checks. |
| 20 | Timer messages hid the source, elapsed time and uncertainty. UTC date/time, monotonic elapsed time, configured limit, action and receive/logging availability are now explicit. Repeated key-down cannot renew a deadline; stale callbacks cannot release a later serial/client session. Removed the supplied message's unsafe assertion that playing audio cannot still transmit. | Four real serial drivers with stand-in ports, actual rigctld and Icom LAN PTT bodies, finite-limit and stepped-clock checks. |
| 21 | Disconnected serial PTT requests silently disappeared; Icom USB could also mark itself transmitting without a connection. They now refuse with source/time/action. Release still cleans up state/RTS safely. | `DriverNotConnectedMessageRegression`: no port writes or key-down; bounded repeated refusal; private previous output excluded. |
| 22 | PSK/RTTY could play audio while selected Radio Control was disconnected. The start and macro paths now refuse clearly and preserve typed text. Disabled allows VOX/external PTT; one direct TX-500/X6100 fallback remains supported. An ambiguous pair of fallback radios is refused. One selected route is keyed, rather than all connected panels. | `DigitalModemRadioControlRegression`: refusal, macro duplication prevention, direct fallback, disabled, selected route and corresponding release. |
| 23 | Ordinary status updates erased safety warnings; the supplied patch also silently cleared them on re-key. Notices now remain until operator acknowledgment. Each radio instance has its own identity, and rigctld/Icom LAN show endpoint labels. | Per-instance rigctld, Icom LAN and four serial driver notice tests; re-key retains notices; dismissing one leaves others. |
| 24 | Warnings were absent from the transmitting screens. FT8, digital modes and Radio Control show an explicit receive-check acknowledgment, red rail and warning symbol; the toolbar retains an indicator. Text wraps and multiple notices scroll at compact widths. | Actual SwiftUI build, model/source integration regression, rendered fixtures in light/dark at 340/760/1000 points and empty state. |
| 25 | Olivia/MFSK, Hellschreiber and SSTV could look as though CAT PTT was being keyed. While sending audio with a radio connected, they now explain VOX/external PTT, UTC time and what still works. No automatic PTT behavior was added. | `AudioOnlyTransmitRegression`, receive regression suite and full app build. |

Native JS8 TX was confirmed to generate 79 random tones instead of encoding its message. The random-tone implementation is removed, the TX button is visibly unavailable with an explanation, and the engine refuses calls too. Composer text and message history are preserved. Receive/simulation and external JS8Call transmission remain available. A test verifies the refusal occurs without audio or a false outgoing message.

Additional transport corrections required by the actual baseline: TCI releases all tracked receivers' PTT/tune before closing; rigctld disconnect retains its old connection until the release write completes or times out. Retired TCI/Radio Control callbacks cannot publish into replacements. A PSK/RTTY transmission captures its release destination so a settings change cannot redirect its release to a new radio. Cancellation checks prevent an old audio task from completing or scheduling tones into a later session.

## Verification completed

- `bash Tests/run-cw-safety-regressions.sh` — passed, **937 PASS checks**, zero FAIL checks. Includes existing CW/identity/band-advisor cases and the new buffer, gating, quit, notice and serial-driver cases.
- `bash Tests/run-transmit-integration-regressions.sh` — passed: real four-driver release, TCI multi-receiver release-before-close, stale callbacks, real Icom LAN PTT/timer/disarm code, registry ordering/cleanup, actual Radio Control captured destinations and release-before-disconnect.
- `bash Tests/run-ft8-transmit-shutdown-regression.sh` — passed: actual FT8 engine cancels a scheduled MainActor task synchronously before yielding, disarms automatic modes and refuses new slots. No waveform/output is constructed.
- `bash Tests/run-review-regressions.sh` — passed: receive decoding/Varicode/Hell timing, CW connection-loss behavior, FT8 timing/calibration and expanded/noise decoding.
- Full Debug YAAM scheme build with code signing disabled — **BUILD SUCCEEDED** after final app-source edits, including all SwiftUI changes.
- `TransmitNoticesRender.swift` — actual native notice component rendered and inspected in normal/compact, light/dark and empty states. PNG fixtures are in `20261022-transmit-safety/`.
- `git diff --check` — passed.

The Icom LAN behavior fixture appends a same-file extension to a temporary copy of the unchanged production source. It primes only connection/arming state and asserts all three sockets remain nil; no handshake, credentials or real radio is involved. TCI and rigctld tests use in-process transport stand-ins; serial tests use a recording port. No test transmits RF or starts transmit audio. The production app was not launched, installed or interrupted for this work.

## Remaining acceptance boundary

Network write completion and local flags do not confirm physical receive. The two-second quit budget may expire before a failed or stalled network delivers a release. Main-actor application timers cannot execute during a process/main-thread stall. Physical PTT, RTS, VOX, on-radio CW buffering, cable loss and actual receive state still require a controlled hardware test. Full-station/popover interactive layouts were built but only the shared notice component was rendered here. Existing unrelated project warnings remain.

The software integration is complete. Keep the broader Y-001 card in **Review / Test**, with hardware acceptance and the separately supplied prerequisite/fill-in work explicitly outside this verification, rather than claiming the whole watchdog initiative is finished.

Credit: EA3JIC supplied patches 17–25 and their regression ideas; this integration adds baseline adaptation and the safety corrections described above.
