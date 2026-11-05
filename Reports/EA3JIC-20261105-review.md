# EA3JIC follow-up review — 5 November 2026

## Scope and evidence

Received-mail search for 30 October–5 November (including Spam/Trash and a broader sender/callsign search) returned one message, dated 4 November, without attachments. It thanked the maintainer for earlier work and referred to the new inventory/design comment on shared-board B-018 (#339). The email does not itself contain a patch. The complete B-018 design and its older comments were read; inventory counts supplied there are the contributor's source-review estimates, not reproduced runtime measurements.

The shared board snapshot contains 625 cards: 474 Todo, 10 In Progress, 63 Review / Test, 76 Done, 2 Blocked. During this interval, the updated-issue/comment queries found B-018 as the new contributor activity. The older email's reference to 65 cards, 19 comments and 18 completed items describes earlier work and is not counted as this run's output.

## Verified defects and changes

YAAM 1.37.55 (205):
- Activity text and persistent audit fields are sanitized before display/storage. URL queries/fragments, URL user information, credential-shaped fields, XML session/token fields, authentication and cookie headers are withheld. Control characters cannot forge additional log lines; oversized diagnostic messages are omitted.
- Audit timestamp formatting now runs on the audit queue to avoid concurrent use of its DateFormatter.
- HRDLog and HamQTH upload rejections no longer expose raw server response text. Transport failures use a numeric error code rather than credential-bearing error descriptions.
- JS8, Olivia, RTTY/PSK, Hellschreiber and SSTV receive-start failures now appear in their owning screen with a cause category and recovery steps. Failed audio-start attempts release their tap/player; successful retry clears the error. No transmit routing or safety interlock was changed.

Lab599 Utility 2.289.3 (298):
- Activity and diagnostic-session entries share the same sanitization boundary.
- QRZ XML and HamQTH credential checks no longer display partial session identifiers.
- Cloud upload errors and TQSL failure statuses withhold raw provider/process output; network failures use error codes.
- Built in a separate maintenance checkout from d50f362 because the owner's main checkout contains unrelated, uncommitted telemetry/power-calibration work. Those changes were preserved and excluded from this release.

## Verification and release limits

Synthetic secrets, JSON/plain headers, URL user information, encoded query keys, XML tokens, control characters and oversized input are covered by focused Swift and Objective-C regression programs. The existing YAAM live upload-preference test and Lab599 logbook/cloud regression suite are also run without real uploads or radio transmission. Complete app builds and signature verification are required before publication.

Redaction is defense in depth, not a guarantee that arbitrary prose cannot contain secrets. Raw replies are withheld at the reviewed call sites for that reason. Historical log files are not rewritten. The existing TQSL command-line certificate-password exposure is documented rather than claiming an unsupported password transport. No real-radio, live-provider credential, or interactive audio-device acceptance test was performed.

## B-018 remains open

This release addresses confirmed privacy defects and a bounded set of silent audio failures. It does not complete the proposed migration of all message sites, a shared service registry/reachability supervisor, global offline deduplication, or the new Connection Status interface. Remaining callbook failure propagation, database-save reporting, feed stale-state reporting and the rest of the silent-drop inventory require separate service-specific verification. No existing card is marked Done on the strength of the contributor's static inventory or these focused fixes.
