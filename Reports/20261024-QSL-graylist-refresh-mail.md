# QSL Graylist refresh and confirmation email workflow

Tracking: [Y-163 / shared board #421](https://github.com/fact0real/yaam-lab599-shared-board/issues/421).
Date: 2026-10-24 (Asia/Tehran).

The owner requested a fix for the repeatedly refreshing Graylist screen and clarified that the email request was to add a button to the app, without sending any messages now. This follow-up publishes that source change; it does not install a new app, bump the release version, or send email.

## Changes

- Ignore identical Graylist evidence and unrelated email/name/history metadata changes. Keep existing rows and selection during real background calculations, suspend stale priority penalties immediately, and replace the index only when the result changes. Profile/workspace changes still invalidate the old evidence.
- Add **Request confirmations (N)…** to the displayed Graylist. Search narrows the recipient scope; clearing search includes the full list.
- Prepare one separately editable LoTW/QRZ request per exact callsign, including distinct canonical QSO details from the active station. Preserve portable callsigns and profile ownership. Missing email addresses remain visible for lookup or manual entry.
- Provide Select all, Not previously emailed and Clear selection. Previous QSL email recipients start unchecked. Use the existing SMTP delivery/history path only after the operator presses Send; show per-recipient results and stop after the current delivery when requested. Revalidate workspace and QSL evidence before each message, and stop on an email-history persistence failure.
- Update the English/Persian manuals and focused regression/native visual harness. The native selection check explicitly lays out its hosting view and settles initial selection before applying updates.

## Verification

- The isolated source snapshot excludes unrelated pending radio/serial/report changes. The YAAM scheme Debug build passes with signing disabled.
- `python3 Tests/run-qsl-graylist-regressions.py <visual-output-directory>` passes, covering Graylist/roster behavior, unchanged and in-flight metadata updates, retained rows with immediate penalty withdrawal, visible email scope, profile isolation, distinct-QSO grouping, portable callsigns, missing email addresses and invalid recipient headers. Operator Desk navigation regression passes.
- Native table selection survives both metadata and real sent-evidence changes. Actual SwiftUI screens are rendered at compact/normal widths in light/dark appearance, including the mail composer with ready/missing addresses and previous-email history.
- `git diff --cached --check` passes. Live SMTP delivery and provider email lookup are not exercised; no messages are sent by the inert fixtures. The installed app is unchanged.
