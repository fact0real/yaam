"""Ephemeral synthetic PKCS#12; never use a real identity or write into Git.

python Tests/Support/make_lotw_proof_fixture.py /tmp/lotw-test/synthetic.p12
Requires cryptography. Delete the generated file after the native regression.
"""
import datetime as dt
import os
from pathlib import Path
import sys
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

path = Path(sys.argv[1]).resolve()
allowed = (Path('/tmp').resolve(), Path(tempfile.gettempdir()).resolve())
if not any(path.is_relative_to(root) for root in allowed):
    raise SystemExit('Write the synthetic fixture into a temporary directory only.')
path.parent.mkdir(parents=True, exist_ok=True)
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'YAAM Synthetic LoTW Test 20261024')])
now = dt.datetime.now(dt.timezone.utc)
cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
        .public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now - dt.timedelta(minutes=1)).not_valid_after(now + dt.timedelta(days=1))
        .sign(key, hashes.SHA256()))
# Match the legacy PKCS#12 wrapping supported by macOS. The proof signature
# itself is SHA-256; this password protects a disposable synthetic fixture only.
encryption = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
              .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
              .hmac_hash(hashes.SHA1()).build(b'synthetic-test-only'))
raw = pkcs12.serialize_key_and_certificates(b'YAAM Synthetic LoTW Test 20261024', key, cert, None, encryption)
with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as output:
    output.write(raw)
print('Created temporary synthetic test fixture; delete it after testing.')
