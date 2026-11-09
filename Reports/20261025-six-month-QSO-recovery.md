# Contact Recovery Report from Prior Six Months Email Audit

Primary Date Range: April 25 to October 25, 2026. Search scope covered archive, trash, quoted replies, and attachments, with a 1-day margin for timezone differences. Primary subject keywords, missing recovery/log terms, and alternate QSO/QSL subjects were audited. Routine confirmation requests, newsletters, release announcements, and future SKED planning were segregated from genuine past contact recovery.

165 email threads were inspected. Associated evidence and attachments are maintained locally.

## Current Results

- 71 documented contacts reconciled: 9 new contacts and 62 existing contacts.
- Total contacts for station profile EP2AES increased from 21,742 to 21,751.
- 15 existing records updated or corrected; four instances of transposed sent/received signal reports fixed. Default "59" placeholders in digital modes were not accepted as recovery grounds.
- New submissions from this audit: 27 contacts submitted to LoTW; TQSL returned Success(0) and "File queued for processing" across all three batches. Acceptance for processing is distinct from final peer confirmation.

| Service | Valid Presence or Accepted Submission (of 71) | Remaining |
|---|---:|---:|
| QRZ | 71 | 0 |
| LoTW | 71 | 0 |
| Club Log | 71 | 0 |

All required submissions in this batch were accepted: 14 to QRZ and 63 to Club Log. All other contacts were already recorded in the corresponding services.

## New Contacts

| Callsign | UTC Date | UTC Time | Band | Mode |
|---|---|---|---|---|
| CT1FMX | 20260426 | 0019 | 40M | FT8 |
| JK1NIU | 20260719 | 2023 | 20M | FT8 |
| HB9FMN | 20260723 | 0653 | 6M | FT8 |
| I2FAK | 20260723 | 0727 | 6M | FT8 |
| LU8EKC | 20260723 | 1932 | 20M | FT4 |
| TB2AYE | 20260808 | 1350 | 20M | FT8 |
| M7AHO | 20261018 | 1727 | 20M | FT4 |
| DL9GCG | 20261022 | 2059 | 40M | FT8 |
| SP5GMM | 20261022 | 211915 | 60M | FT8 |

For I2FAK, the 07:27 contact with complete RR73/73 exchange in email was recovered; the legacy local 07:13:29 record was also preserved. For the two new October 22 contacts, station grid LM47 from same-day records was preserved; other new contacts were documented with 4-character grid LM55. FT4 mode was explicit in two attachments and was not downgraded to FT8.

## Items Requiring Further Evidence

24 requests still lack sufficient documentation for valid recording. The complete list, date discrepancies, and rejected items are documented in the audit directory. Until supplementary evidence is received, absence of further missing contacts cannot be definitively claimed.

## Protection and Verification

- Consistent database backups taken prior to writing with YAAM closed. Temporary tools utilized project-native `LogbookDatabase.saveWorkspace` and `QSLSyncAll/QSOIdentity`; no raw SQL edits performed.
- Contact entry and upload queuing executed in a single transaction with profile scoping, record ID matching, duplicate prevention, and zero deletion of unrelated records.
- Workflow tested first on an isolated database; all 21,728 initial records outside first-stage modifications were preserved intact. Incoming Recovery Regression suite (rollback, restart, ownership, privacy, duplicate replay) passed.
- Final database integrity check: `ok`. No received confirmation was fabricated due to upload; status was recorded strictly as "submission accepted".
- No unsolicited outreach emails dispatched. Keys and credentials were excluded from reports, ADIF, and queues. Attachments and email explanations were not uploaded to external services.

## Evidence Artifacts

- [Audit Directory](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit)
- [Records Status](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/records-status.json)
- [Primary Evidence](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/mail-evidence.json)
- [Late Evidence](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/late-evidence.json)
- [LoTW Receipt, 19-QSO Batch](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/lotw-result.txt)
- [LoTW Receipt, 7-QSO Batch](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/supplement/lotw-result.txt)
- [LoTW Receipt, UR5KAN Contact](/Users/factoreal/Downloads/QSO-Recovery-2026-10-25/six-month-audit/forward/lotw-result.txt)

This report accounts for six-month review phase counts and does not re-count the three contacts logged in the earlier session.

## Club Log Retry Remediation

- In `QSLSyncAll.swift`, missing credential, Touch ID, and network errors no longer fragment batch Club Log uploads into single requests on subsequent retry attempts. Counters and retry histories are preserved; HTTP 400 error record isolation remains active.
- Focused regression test: 101 passed, 0 failed. Debug and Release builds succeeded; corrected Release build installed to `/Applications/YAAM.app` with previous version archived.
- Official Club Log guidance prohibits rapid sequential individual uploads via `putlogs.php` and notes 403 responses do not strictly indicate invalid passwords: [Batch Upload Guide](https://clublog.org/support/fd/54905). No service passwords or keys were modified during this task.
- Final reconciliation: all 21,742 initial primary profile record IDs preserved, and 11,506 records across other station profiles remained completely untouched.
