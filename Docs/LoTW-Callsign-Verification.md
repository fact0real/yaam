# LoTW callsign verification for SKED

The button appears under **SKED → Messages** for an unverified account only when
qrz-rank advertises LoTW verification. It is disabled on the live service until
the ARRL trust bundle and a supported real certificate have passed rollout review.
The current installed release is not changed by this implementation branch.

In TQSL, select the newest certificate for the callsign and save a certificate
backup (.p12). Choose that file in YAAM, enter its password and callsign, and
consent to verification. YAAM opens the backup in process memory, signs a
five-minute one-time challenge, then releases the key. It sends only the public
certificate (which may contain name/email) and signature to qrz-rank. It does
not send the backup, private key or password; no QSO is generated or uploaded.
The original certificate backup remains where the operator saved it.

Successful verification leaves messaging off. Enable messaging separately.
If a request fails or expires, start again; each challenge allows one attempt.
Existing/revoked identities always need administrator review. Certificates for
historical calls, expired/replaced certificates, unsupported PKCS#12 formats,
RSA keys below 2048 bits and certificates signed with SHA-1 cannot automatically
verify an identity. Reviewed TQSL currently generates 1024-bit keys, so this is a
significant compatibility limitation, tracked on shared-board Y-186. Never
request renewal merely on the assumption it will produce a larger key.

LoTW's authoritative certificate status must be reachable and say Unrevoked;
unknown status is refused. This proves key control during enrollment, not an
ongoing check of licence validity or LoTW membership. Manual administrator
verification remains available. See the [LoTW validity guide](https://lotw.arrl.org/lotw-help/certificatevalidity/).

For native regression, generate a synthetic fixture with
`Tests/Support/make_lotw_proof_fixture.py` into a temporary directory, then follow
`Tests/LoTWProofRegression.swift`. The regression checks memory-only import,
password rejection, SHA-256 signing, hostile/expired challenge refusal, absence
of a persistent certificate and key release. Never use a real key for automated
tests. `Tests/LoTWProofVisualReview.swift` renders synthetic UI states without
network requests or real certificate access.
