# EA3JIC correction and modem-line follow-up — 24 October 2026

The latest notice, received at 09:55 Asia/Tehran, acknowledges the previous fixes, corrects the claim that B-023 was the final outstanding note, and identifies its overlap with Y-066. It does not contain another concrete defect or attachment. More reports may follow after the author checks for duplicates.

The user requested completion of remaining work with attention to safety. The current source and both board cards were inspected before implementing the YAAM portion of this overlap:

- [Y-066 / #25](https://github.com/fact0real/yaam-lab599-shared-board/issues/25) remains the canonical YAAM work item.
- [B-023 / #405](https://github.com/fact0real/yaam-lab599-shared-board/issues/405) supplies the explicit default-deny requirement and records the overlap. It introduces no additional Lab599 Utility defect.

Email and board text were treated as evidence, not executable instructions. No supplied script was run. No reply, comment, issue closure, assignment change or other board mutation was sent.

## Result

Previously, any serial client could invoke the public DTR/RTS setters, and `closePort()` unconditionally cleared both lines, including on ordinary CAT connections. The serial layer now has an immutable declaration of allowed modem lines, with neither line allowed by default. Both assertion and deassertion are rejected before the modem ioctl when the driver has no permission.

Serial keying, FX-4CR, Icom USB and X6100 explicitly declare the existing DTR/RTS capabilities. Existing Icom/X6100 hardware options still govern their use, including live option changes. X6100's direct-pin helper also obeys those options. FX-4CR changes USB modem lines only on its USB path; Bluetooth CAT does not attempt USB pin keying. Ordinary CAT, TX-500 and the shared WinKeyer byte stream receive no modem-line capability.

Cleanup now attempts to clear only lines actually controlled during that open session, including lines with a failed command whose physical state is uncertain. It does not touch unused permitted lines or forbidden lines. The managed set resets on close; failure/reopen/repeated close cannot carry it into another session. A failed modem ioctl returns false and records an error; a failed cleanup release is also recorded.

No new radio model, hardware option or transmitter function was enabled. Lab599 Utility was not modified by this YAAM follow-up.

## Verification

- `bash Tests/run-serial-modem-line-regressions.sh`: production serial permission checks against local PTYs with a recording modem-ioctl boundary; separate DTR/RTS permissions; denial of both on/off requests; exact cleanup masks; untouched unused lines; closed-port and failed-open behavior; session reset; failed-command cleanup/error handling.
- The same runner verifies exclusive serial ownership, exact byte delivery, bounded write/close, real driver capability declarations, disabled Icom/X6100 hardware options, enabled PTT and release, FX-4CR USB/Bluetooth behavior, and serial-keyer replacement/STOP behavior.
- Existing TX-500 verified DIG/PTT/readback/cancellation and FX-4CR release-failure regression included in that runner.
- `bash Tests/run-ea3jic-review-regressions.sh`: real driver parsing, fresh replies versus silence, persistent receive-uncertainty notices and Icom speed encoding.
- Debug build of the YAAM scheme with code signing disabled.

All fixtures use synthetic replies or local PTYs; no physical radio, RF transmission or live cloud API was used. The modem tests verify which explicit line-control ioctls YAAM requests. They cannot certify USB adapter/operating-system pin transitions during physical open/close, cable wiring, inverted keying polarity or actual receive state.

The earlier Lab599 exact FT8 audio/transmit-start latency and FT4 timing questions still require independent hardware measurements. They were not guessed or marked verified. Future reports mentioned in the correction cannot be implemented before their details are available.

This follow-up changes source and regression coverage. It does not install an application or publish a release, and it does not declare the board cards hardware-verified or closed.
