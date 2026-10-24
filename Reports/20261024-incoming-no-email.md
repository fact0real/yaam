# QRZ Incoming: reject when no profile email is published

The Incoming list now checks the official QRZ profile email field without opening an external browser. It reuses the saved QRZ session in a dedicated WebView, independently of local/HAMQTH contacts and the shared enrichment scraper.

## Behavior and boundaries

- **QRZ Login** opens the existing in-app authenticator. A trusted HTTPS profile, matching profile callsign, authenticated page and valid session cookie are required before declaring an email absent.
- **Check QRZ email** distinguishes available, explicitly not published, sign-in required, unavailable, unchecked and checking. Blank/unknown/reveal-only fields, malformed encoded mail, missing profiles, HTTP errors, expired sessions and challenges never mean no email.
- A confirmed missing email changes **Reject** to **Reject · no email**. The review sheet selects **Other** and an editable note about inability to request details. It does not assert that the QSO is missing from the local log.
- Rejection stays explicit and submits only the current numeric request ID. Comments are serialized as JSON, not interpreted as JavaScript. Local QSOs are not deleted. Login/error pages cannot count as successful rejection merely because a request node is absent.
- Evidence is temporary and cleared on refresh, dismissal, login completion or station change. Late lookup results cannot repopulate another station's state.
- The rejection sheet uses one item containing request/profile/evidence context. This also fixes the empty sheet seen on its first presentation during visual QA.

## Validation

- `python3 Tests/run-incoming-email-regressions.py`: 64 email/evidence/lifecycle/real WebKit HTML-fixture checks and 14 production rejection-script checks, with no live rejection or email send.
- `bash Tests/run-incoming-recovery-regressions.sh`: all four existing recovery suites passed, including SQLite atomicity, replay, ownership and rollback.
- Existing QRZ Incoming bulk-mail regression passed.
- Native production views reviewed through CUA at 760×500 and 980×680, light/dark, including missing/available/unknown/login-needed and the prefilled rejection sheet. Screenshots use deliberately invented ZZ*TEST contacts and injected outcomes; they are not evidence about real QRZ accounts.
- W1AW is not classified as missing from a logged-out page. Regression fixtures cover both login-required and the published W1AW@ARRL.ORG value shown by the operator after sign-in.

No real Incoming request was rejected as a development test. Live authentication and profile checks use the operator's saved session and remain subject to QRZ availability.

## Signed-in session correction

Read-only testing in the installed authenticator confirmed an existing authenticated QRZ account whose logout action was hidden in the collapsed header menu. Authentication now also recognizes a server-issued logout-token link within `#qrztop` together with that header's official Account action. A current session cookie remains mandatory, and login/challenge states override this signal. Five real WebKit DOM fixtures cover the signed-in collapsed menu, logged-out header, tokenless menu, hostile host and biography-only imitation. The existing session was verified and saved through the native authenticator; no password or cookie was copied into test files or logs.
