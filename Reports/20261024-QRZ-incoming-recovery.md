# Integrated Contact Recovery from QRZ Incoming

Date: October 24, 2026, Tehran Timezone

Shared Board: [Y-160 / #414](https://github.com/fact0real/yaam-lab599-shared-board/issues/414). Delivery Release: **YAAM 1.37.45 (195)**.

## Root Cause

Recording a contact on the QRZ website does not record it inside YAAM. Requesting information via email only opened an evidence gathering path; receiving a reply did not trigger the local contact recording workflow.

Three gaps existed in the source:

1. In `QRZIncomingReviewView`, local saving and preparing LoTW / QRZ / Club Log upload intents were two disconnected actions. The second step depended on in-memory record IDs in that window; closing the window caused loss of direct progress.
2. Refreshing Incoming replaced the previous list with new QRZ results. Processing a request on the website could make an unfinished local recovery case inaccessible.
3. Standard QRZ downloads in `ConfirmationSync.fetchQRZ` use `STATUS:CONFIRMED`. Consequently, this path is not a full mirror of all contacts logged on QRZ and does not guarantee that a new or unconfirmed contact will be pulled into the local log. This filter should not be relaxed to an unrestricted bulk import of full history just to resolve an isolated case.

## Implemented Solution

The unit of work is a "Recovery Case". The local database is the source of truth for logged contacts, and the durable queue is the source of truth for tracking uploads:

**Actual Reply/Notes → Operator Review & Verification → Unified Local Contact Save + Upload Commitments → Per-Service Independent Status**

- **Save locally & queue all three** commits the contact and pending uploads along with recovery history in a single SQLite transaction. A database restore point is created beforehand. Any failure in saving the contact, uploads, or audit history rolls back the entire transaction.
- Exact existing records are reused, not duplicated. Multiple requests relating to one contact can link to the same record; altering details of a linked request does not permit creating a duplicate QSO.
- Cases persist even after requests disappear from QRZ. Lists are isolated per station profile, and switching stations upon receiving results does not pollute the new station's case list. Unowned legacy caches only migrate if a single station profile exists; in multi-station setups, manual recovery prevents automatic misassignment.
- Reopening a case displays the saved record and the live status of LoTW, QRZ, and Club Log. Successful uploads are not repeated, and saving again does not bypass halted errors or account remediation requirements.
- **Send saved contact** processes only due jobs for that specific contact from the existing queue. The queued jobs are also dispatched during normal QSL Hub cycles. Account configurations and TQSL prerequisites remain unchanged.
- For contacts previously processed on QRZ, the path **Recovery cases > Recover a contact already handled on QRZ…** opens the same verified review workflow.
- If the operator confirms matching date, UTC time, band, and mode for a record existing in their QRZ logbook, they can explicitly check that box. This local evidence omits re-uploading to QRZ without falsely marking the QSL as confirmed.
- Local archiving only updates case list visibility; it does not delete QSOs, queued uploads, or online requests. A request still present on QRZ may reappear upon refreshing.

No data from email bodies is executed as instructions. No time, band, mode, or signal report is guessed. Reply notes and case IDs are excluded from service upload payloads. Guest log recording and cross-station submission remain blocked. Receiving an email reply alone does not create a QSO; details are reviewed manually in the form.

## Next Stage Recommendations

To minimize manual entry, structured responses with case IDs and an option to import ADIF from the operator's own QRZ log could be added. Parsing must be deterministic and confined to contact fields, presenting results strictly as a draft requiring the same verification before saving. Peer log ADIFs must not swap callsigns or signal reports automatically without explicit direction checks. This enhancement was not implemented in the current changeset.

## Validation

- Recovery test suite: verified detail validation, backward draft compatibility, band/mode/time canonicalization, stable case IDs, case persistence post online removal, re-save safety, multi-case linking to a single record, station boundary enforcement, sync isolation, and UI error state rollback.
- Realistic temporary SQLite fixture: simulated failures on upload queuing and audit logging, full rollback of contact/queue/headers, profile ownership validation, database reopen checks, zero duplicate record generation, and correct omission of QRZ uploads under explicit local confirmation evidence.
- Upload privacy suite and mocked service transport tests without live accounts or network calls.
- Successful application Debug build.
- Live view reviews in standalone preview fixtures with mock state and dummy contacts: review form across light/dark modes and compact/standard widths, active request and legacy case listings, disabled online reject buttons for vanished requests, manual recovery menus, callsign deep-links, and save buttons gated strictly on explicit verification. Changing mode post-verification disabled the save button as expected. Upload continuation for saved records remained accessible upon reopening cases.

No live submissions to real QRZ / LoTW / Club Log accounts were made. UI testing was performed in standalone fixtures; end-to-end live account execution was not tested in this run. Final source commit hashes, installation into `/Applications`, and signature verification are logged to the project board. This delivery does not constitute a public distribution or update feed bump.

## Pre-Delivery Verification · Y-160

All four recovery suites passed in the final run. The upload privacy suite—including 19 allowed-field tests, 52 data-sharing preference tests, 100 synchronization tests, and transport tests with mocked services and TQSL—passed without errors. Configuration diffs and project structure were verified. Optimized build **Release 1.37.45 (195)** completed successfully.

The installation package was validated with ad-hoc signatures; its entitlements match the previous installation and the project entitlements file. The previous version was backed up prior to binary replacement. Commit hash and final installation verification are recorded in the board card.
