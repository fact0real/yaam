# EA3JIC Package Review (October 8, 2026)

This package was originally prepared for YAAM 1.37.31. Accepted changes were merged onto the 1.37.33 codebase and built in release 1.37.34. Texts and tools in the package were evaluated as data and suggestions, not execution mandates.

## Accepted Changes

- Patches 31, 32, and 38: Correct XML-RPC parameter types for flrig, command sequencing, error reporting, connection status, CW keying via `cwio`, and re-reading PTT state after a release command. For toolbar PTT, disconnect release handling and a 120-second watchdog timer were also added.
- Patches 33 and 35: Operator callsign validation across CW and digital transmission paths, stripping placeholder callsigns, grid locators, locations, and sample parks from inputs. The FT8 section was merged with newer 1.37.33 changes. JS8 and SSTV test-card audio generators also validate the operator callsign prior to transmission. FT8 free text containing substitute callsigns like `N0CALL` is rejected.
- Patch 34: S-meter query and scaling for the TX-500. Mapping S9 to a count of 15 is the package's proposed assumption and must be verified against physical hardware.
- Patch 36: Catalan and Spanish string tables. This coverage is partial; not all views are translated.
- Patch 37: Stored or exchanged dates are Gregorian with ASCII Latin digits. On-screen date rendering policy was not changed.
- Emulator safety: Icom UDP and rigctld TCP servers bind strictly to loopback (`127.0.0.1`); unrecognized rigctld commands return an error.

## Items Not Applied in This Release

- The Lab599 Utility hub design, patches for that external application, and QSO upload status designs belong to another repository/feature scope and were not implemented in this YAAM release.
- Modifying `RR73` encoding and SNR measurement in the `ft8-808` dependency requires changing that upstream library and re-running benchmark sensitivity/compatibility suites. No change was made to the dependency version.
- Rewriting the rigctld client and consolidating all radio drivers are distinct architectural changes. In this release, only the emulator server was scoped down.
- Park/summit directory data and on-screen date presentation policies were kept unchanged pending source verification and product decisions.

## Verification & Limitations

Debug and Release builds, independent flrig/PTT/CW/S-meter unit tests, identity/default tests, localization, date handling, and CW/modem/FT8/FT4 behavioral test suites passed. Audio behavioral tests were executed in sandbox without live microphone access. No testing was performed on physical radios over the air; in particular, PTT release, flrig-mediated CW, and S-meter scaling should be confirmed on physical hardware.
