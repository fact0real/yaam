# QSO recovery and import freeze — 2026-10-25

## Outcome

Reviewed all six incoming responses matching `Could you help me recover our QSO details?` returned for the preceding two days. Three missing QSOs were imported through YAAM's reviewed import workflow. The existing DK2SW contact was retained and uploaded. R9FEB and DJ6JZ already had recovered entries and successful jobs at all three requested services; they were not uploaded again.

| Call | UTC date | Logged UTC time | Band / mode | Action |
| --- | --- | --- | --- | --- |
| BH4HTD | 2026-06-19 | 13:47 | 15m FT8 | Added; QRZ and Club Log accepted; LoTW upload accepted |
| CT7BHW | 2026-10-15 | 23:34 | 40m FT8 | Added; QRZ and Club Log accepted; LoTW upload accepted |
| IS0LJG | 2026-08-30 | 19:22 | 15m FT8 | Added; QRZ and Club Log accepted; LoTW upload accepted |
| DK2SW | 2026-10-22 | 09:41:29 | 20m FT8 | Existing log agrees with supplied FT8 exchange; QRZ and LoTW uploaded; Club Log already sent |
| R9FEB | 2026-07-21 | 05:09 | 15m FT8 | Existing recovered entry; all three previous upload jobs succeeded |
| DJ6JZ | 2026-09-23 | 14:52 | 15m FT8 | Existing recovered and confirmed entry; all three previous upload jobs succeeded |

The DJ6JZ screenshot reports start 14:51 and end 14:52; the existing confirmed 14:52 record was preserved. Separate older local entries for IS0LJG (18:34:59), BH4HTD (13:01:59), and R9FEB (04:26:44) were retained rather than silently overwritten. No unprovided reports were invented for CT7BHW.

Three new contacts raised the primary station count from 21,739 to 21,742. Final SQLite `quick_check` returned `ok`.

## LoTW evidence

YAAM's selected upload run accepted seven new QRZ/Club Log jobs and found one Club Log contact already sent. It skipped LoTW because the station location preference was empty.

The existing TQSL location `EP2AES-Home` and certificate were used to submit the four contacts directly through installed TQSL 2.8.6. `-f update` retained each record's logged `MY_GRIDSQUARE`, including DK2SW's LM47, rather than applying the Home locator to all contacts. This behavior is documented in the [TrustedQSL project command-line documentation](https://sourceforge.net/p/trustedqsl/tqsl/ci/master/tree/).

TQSL reported `Attempting to upload 4 QSOs`, `File queued for processing`, and `Final Status: Success(0)`. This proves successful submission, not subsequent matching or QSL confirmation. Four `LOTW_QSL_SENT=Y` / `LOTW_QSLSDATE=20261025` updates were then imported through YAAM's normal review: zero new QSOs and four status updates. No received-confirmation flags were created. TQSL's saved station configuration was byte-identical before and after submission.

The temporary eQSL exclusion for the selected upload was restored; the user's provider preference remains `clubLog,eqsl,lotw,qrz`. No email replies were sent.

## Import freeze correction

The initial three-record import hung on the main thread in `AppState.commitPendingImport()` while renumbering the entire published `qsoRecords` array. Each individual index change ran the full-array observer, including QSL graylist evidence comparison. A process sample confirmed this path; no new recovered records had reached SQLite.

A verified SQLite backup was saved before stopping that process. `commitPendingImport()` now prepares additions, updates, and indices in a local array, then publishes `qsoRecords` once. Existing import review, restore point, profile checks, self-contact guards, merge policy, and persistence remain in use.

Validation:

- Import upload-status regression: 17 passed, zero failed (the standalone compile also needs current `FrequencyBounds.swift`).
- Debug build: succeeded.
- Release build: succeeded.
- Live three-QSO import on the 21,739-contact workspace completed in under five seconds.
- Live four-record upload-status update completed in about four seconds, adding no contacts.
- Installed the optimized corrected Release in `/Applications/YAAM.app` using the existing ad-hoc signing and entitlements. Previous app copies are preserved.

## Recovery files

Evidence, source ADIF, TQSL result, final field-status snapshot, and pre-restart database backup are under:

`/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/`

Important files: `recovered.adif`, `email-evidence.json`, `BH4HTD.png`, `CT7BHW.jpg`, `DJ6JZ.png`, `lotw-four-contacts.adif`, `lotw-upload-result.txt`, `lotw-accepted-status.adif`, `final-record-status.json`, and `before-recovery-restart.sqlite`.
