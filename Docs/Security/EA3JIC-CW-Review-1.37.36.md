# EA3JIC proposal review for YAAM 1.37.36

Reviewed on 2026-10-17 against public base aff7d82 and the local statistics performance fixes.
Input: EA3JIC's 16 proposed patches, numbered 45 through 60, dated 2026-10-15.

## Decision

The proposals address reproducible correctness and transmit-safety faults and merit integration.
The reviewed production changes add no upload destinations, credential access, shell execution,
permission expansion or external dependencies. This is a scoped source review, not a claim that
all of YAAM or any connected radio is free of vulnerabilities.

The original patches were reviewed before applying their source/test changes. Their supplied
shell scripts were read for context but not executed. Tests use YAAM's own reviewed runner and
recording stand-ins; validation does not key a physical radio.

| Proposals | Decision and resulting behavior |
| --- | --- |
| 45 | Accept WinKeyer clear/completion separation; additionally prevent idle/echo responses from an old message completing its replacement. |
| 46 | Accept decode identity and original receipt timestamps; additionally bound and expire stored history. |
| 47 | Accept spot identity/freshness and cluster-only candidate scoring. The thresholds remain a heuristic and QSY remains an explicit operator action. |
| 48-49 | Accept cancellable, word-aware CAT chunks and Morse pacing; additionally validate text at the driver boundary and invalidate callbacks by generation. Disconnect also sends a stop before closing. |
| 50 | Accept Hamlib's documented stop_morse command. Remote support and successful physical de-keying cannot be inferred solely from a successful socket write. |
| 51 | Accept STOP routing to the destination that took the message. Retain the selected transmission mode and order flrig stops before replacement sends. |
| 52 | Accept stop-on-normal-exit; add a bounded termination delay to allow asynchronous stops to execute. Force Quit, power loss and failed transports cannot guarantee a remote stop. |
| 53-54 | Accept offline/refusal reporting and flrig error handling; reject synchronous contest sends without marking the text sent. |
| 55 | Accept accent folding; strengthen it to an allowlist of supported Morse characters with whitespace normalization and a 1024-byte input limit. |
| 56 | Accept cancelled-task guards for UI and serial keying; additionally guard tasks before their first hardware write. |
| 57 | Accept a Morse-based clock; account for the scheduled gaps between CAT chunks when retaining ON AIR state. |
| 58-59 | Accept manual-send cancellation of Auto-CQ and termination after synchronous or asynchronous CQ refusal. |
| 60 | Accept manufacturer command/status corrections; additionally require revision confirmation, configure 8N2, honor XOFF, limit unacknowledged text to 32 bytes, and use an admin-echo barrier after clearing a message. |

## Security findings resolved during integration

1. **Command injection through CW text:** ASCII-only checks still allowed semicolons in Kenwood KY
   text, line delimiters in rigctld text, and control bytes in WinKeyer/cwdaemon text. Imported
   name/QTH values or pasted macros could cross the text/command boundary when an operator sent
   them. Validation now rejects command-bearing/unsupported text before a CW send, and the CAT,
   rigctld and WinKeyer entry points independently validate their inputs.
2. **Unconfirmed or overflowing WinKeyer sessions:** configuring after an arbitrary 150 ms delay
   and writing an entire long message did not establish protocol readiness or respect buffer
   capacity. The driver now waits for a revision response, times out without transmitting,
   separates old responses with an echo barrier and feeds text through a bounded echo window.
3. **Stale work after STOP/replacement:** cancelled timers and tasks must not re-key, release a
   replacement's PTT or clear its ON AIR state. Both task cancellation and message generations
   now protect the affected paths; flrig stop operations precede replacement CAT sends.
4. **Unbounded/replayed advisory input:** repeated recent-list publications inflated counts and
   old per-band history could persist. History is deduplicated, expired and bounded; future
   timestamps and unknown digital bands are excluded. Suggestions do not grant transmit authority.

## Protocol references and practical limits

- [K1EL WinKeyer3 IC manual, revision 1.3](https://www.k1elsystems.com/files/WK3_Datasheet_v1.3.pdf):
  Host Open/revision handshake, admin echo, command parameters, status bits, FIFO and serial framing.
- [Hamlib rigctl manual](https://hamlib.sourceforge.net/snapshots/man1/rigctl.1.html):
  send_morse and stop_morse are different commands.
- KY pacing remains a conservative estimate, not a radio acknowledgement. Actual keyer weighting,
  firmware behavior and transport failure can affect physical RF timing. STOP status on screen is
  a software action and must not be treated as proof of hardware de-keying.
- No physical TX-500, FX-4CR or WinKeyer was exercised on air for this release. Manufacturer
  protocol checks and recording/simulated transports establish software behavior only.
- The release retains existing callsign gates, transport destinations and credential storage.
  It does not enable automatic transmission or broaden application entitlements.

## Validation

- Twenty CW/advisor regression suites passed across the full run and focused reruns. Coverage
  includes command-bearing and oversized input, missing devices, message replacement, STOP,
  reconnects, normal-exit notification handling, flrig refusal, Auto-CQ cancellation, Morse
  timing, decode/spot deduplication, withdrawn QSY suggestions and WinKeyer protocol flow.
- The WinKeyer suite additionally checks two stop bits, the clear/echo barrier, XOFF, the
  32-character acknowledgement window, delayed idle/echo responses, WAIT/KEYDOWN handling,
  missing revision responses and text whose spaces are not echoed.
- Invalid cwdaemon ports are rejected before conversion to a 16-bit port, including on STOP
  during shutdown, so malformed local configuration cannot crash that path.
- Five statistics worker scenarios passed with Swift 6 concurrency checking and MainActor
  default isolation: burst coalescing, caching, non-cooperative cancellation, invalidation
  before execution, and cancellation of individual waiters.
- Reproduce the CW/advisor suites with `bash Tests/run-cw-safety-regressions.sh`. Use
  `--cat-only` for the two real-time CAT scheduling suites. The snapshot test's compile
  command is recorded at the top of `Tests/LatestSnapshotWorkerRegression.swift`.
