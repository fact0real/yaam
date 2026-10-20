# YAAM priority workflow verification — 20 October 2026

Owner: factoreal. Shared-board activities: #289, #87, #291, #84, #290.

## Implemented behavior

- **#289 — credentials:** a random 256-bit root is held in a device-local, non-synchronizing macOS login Keychain item. AES-GCM protects the v4 vault. Legacy decoding is migration-only; old sources are retired after verified persistence. Corrupt data or missing/denied keys preserve the existing file and fail closed. Touch ID is explicitly an application-session gate; failed/cancelled authentication cannot unlock it, and late authentication cannot override a newer lock. Lock clears cached credentials. Recovery and the protection boundary are documented in Help, the manual and PRIVACY.md.
- **#87 — Quick Log:** the recent-row action says New / Use as New QSO, asks before replacing the draft, creates fresh timestamps and excludes old identity, contest and confirmation/upload state. Existing-contact correction remains in the Log Table editor.
- **#291 — digital logging:** a typed completion captures observed exchange start/completion, FT8/FT4 identity, precise TX/RX RF frequencies, actual reports and station/grid. FT4 exports as MFSK/FT4. Unknown values are omitted. The saved session ID and canonical QSO identity prevent duplicate callbacks. Single-radio and Multi-Rig paths share synchronous persistence with rollback before upload dispatch.
- **#84 — upload boundaries:** Multi-Rig uses that shared dispatch path; explicit QRZ acceptance remains mandatory, including HTTP 2xx responses. Structured transport/HTTP outcomes replace English-message retry heuristics; uncertain requests need review. File signing uses scoped/coordinated reads, rejects iCloud placeholders and requests unavailable downloads. Upload status cards have independent accepted/waiting/attention semantics, icons and orderly retry/dismiss controls.
- **#290 — QRZ:** a trusted HTTPS host, authenticated account action, current session cookie, and absence of login/MFA/challenge are required before completion. A pre-auth cookie is insufficient. Navigation generations discard stale callbacks; cancellation and single-delivery behavior are explicit. Vault-save failures keep the sheet open. Retry, Verify & Save, and Cancel are consistently grouped with a readable status footer.

## Reproducible automated verification

Run `bash Tests/run-priority-workflow-regressions.sh` from the repository. Ten standalone suites pass:

1. ProtectedCredentialStorageRegression — legacy AES migration, random roots, migration retirement ordering, reopen, missing/denied key, corruption, concurrent reads, session cancellation/stale authentication, file permissions and no plaintext fallback.
2. SecureVaultRegression — legacy derivation compatibility only; isolated test preferences, redacted hardware identifier, biometric capability check without prompting.
3. QuickLogReuseRegression — fresh explicit draft, original preservation and no contest/status leakage.
4. DigitalContactCompletionRegression — FT8/FT4, UTC midnight, reports, RF precision/invalid numeric input, station/grid, actual ADIF writer/parser round trip and replay ID.
5. CompletedDigitalPersistenceRegression — actual shared AppState extension with isolated service/storage stand-ins: save-before-upload, Multi-Rig dispatch, rollback, station boundary and duplicate callbacks.
6. CloudUploadBoundaryRegression — typed outcomes, uncertain transport errors, HTTP status, Unicode/spaced paths, placeholders and original-file preservation.
7. CloudUploadProviderRegression — actual QRZ result parser, explicit acceptance/duplicate and partial notice states.
8. QRZAuthenticationRegression — logged-out/pre-auth/MFA/expired/trusted/hostile navigation, failed session persistence, stale callbacks, cancellation and single delivery.
9. PendingQueueCredentialRegression — queued payload excludes secrets; current profile/global credential resolution.
10. ADIFLengthRegression — existing Unicode and legacy ADIF interchange coverage.

Debug YAAM Xcode build passes with signing disabled. `git diff --check` passes.

## Visual verification

Run `python3 Tests/render-priority-workflows.py /tmp/yaam-priority-visual`. This renders the actual changed SwiftUI sections with inert fixtures; no production log, credentials or live web page is used. Security/recent-contact/upload surfaces were inspected at 760 and 1100 points, light and dark. QRZ chrome/MFA status was inspected at 540 and 760 points. Visual fixtures cover accepted, waiting, attention, unavailable key and MFA-pending states. The browser content in these fixtures is deliberately a local placeholder; this does not validate QRZ's live DOM or interactive behavior.

## Remaining external verification

Keep the cards in **Review / Test** until their external acceptance evidence is supplied. No production vault migration, live login-Keychain denial/reinstall, owner-operated QRZ MFA/session expiry, actual iCloud eviction/download, real-radio FT8/FT4 session, or provider upload was exercised. Dedicated tests prove the modeled boundaries, not these external systems. In particular, the conservative QRZ authenticated-page selector may require adaptation if the live site uses another account-action structure; it fails closed and leaves manual retry available.
