#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-incoming-email.XXXXXX)
swiftc -parse-as-library Tests/QRZIncomingEmailRegression.swift YAAM/QRZIncomingEmailLookup.swift \
    YAAM/QRZAuthenticationPolicy.swift YAAM/QRZIncomingEmailBatch.swift \
    YAAM/QRZIncomingRecoveryArchive.swift YAAM/QRZIncomingBulkMail.swift -o "$out/email"
"$out/email"
swiftc -parse-as-library Tests/QRZIncomingBulkMailRegression.swift YAAM/QRZIncomingBulkMail.swift -o "$out/bulk"
"$out/bulk"
