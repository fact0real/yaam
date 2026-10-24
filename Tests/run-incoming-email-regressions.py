#!/usr/bin/env python3
"""Tests production QRZ email evidence and rejection scripts without accessing QRZ or real QSOs."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='yaam-incoming-email-') as tmp:
    out = Path(tmp)
    subprocess.run(['swiftc', '-parse-as-library', str(root/'Tests/QRZIncomingEmailRegression.swift'),
                    str(root/'YAAM/QRZIncomingEmailLookup.swift'), str(root/'YAAM/QRZAuthenticationPolicy.swift'), '-o', str(out/'email')], check=True)
    subprocess.run([str(out/'email')], check=True)
    source = (root/'YAAM/QRZIncomingAndAssistant.swift').read_text()
    methods = source[source.index('    private static func navigationScript'):source.index('\n}\n\nnonisolated struct ConfirmationReconciliationSnapshot')]
    comments = 'No email. "\\\r\n\u2028; globalThis.pwned = true; //'
    harness = 'import Foundation\nenum Scripts {\n' + methods.replace('private static', 'static') + '\n}\n'
    harness += '''
@main struct Main {
    static func main() throws {
        let comments = String(data: Data(base64Encoded: "COMMENTS")!, encoding: .utf8)!
        let scripts = ["reject": Scripts.buildRejectScript(qsoID: "42", callsign: "W1AW", qsoDate: "2026-10-20", reason: "Other", comments: comments),
            "badID": Scripts.buildRejectScript(qsoID: "42';evil()", callsign: "W1AW", qsoDate: "", reason: "Other", comments: comments),
            "verify": Scripts.buildVerifyScript(qsoID: "42", callsign: "W1AW")]
        print(String(data: try JSONSerialization.data(withJSONObject: scripts), encoding: .utf8)!)
    }
}
'''.replace('COMMENTS', __import__('base64').b64encode(comments.encode()).decode())
    (out/'Scripts.swift').write_text(harness)
    subprocess.run(['swiftc', '-parse-as-library', str(out/'Scripts.swift'), '-o', str(out/'scripts')], check=True)
    scripts = subprocess.check_output([str(out/'scripts')], text=True)
    (out/'scripts.json').write_text(scripts)
    (out/'transport.js').write_text(r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const scripts = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
function context({ready = true, present = false, login = false, host = 'logbook.qrz.com'} = {}) {
    const fields = {};
    const form = {querySelector(s) { return fields[s] ??= {value: ''}; }, submit() { ctx.sent++; }};
    const document = {body: {innerText: ready ? 'Confirmation Requests' : ''},
        querySelectorAll(s) {
            if (s === 'table') return ready ? [{innerText: 'Callsign QSO Date Request Received'}] : [];
            if (s.startsWith('input[type=password]')) return login ? [{getBoundingClientRect: () => ({width: 100, height: 30})}] : [];
            return [];
        },
        querySelector(s) { return null; },
        getElementById(id) { return id === 'lbmenu' ? form : id === 'rcall-42' && present ? {} : null; }};
    const ctx = {document, location: {protocol: 'https:', hostname: host}, sent: 0, fields};
    return ctx;
}
let checks = 0;
function check(value) { assert.ok(value); checks++; }
let ctx = context();
check(vm.runInNewContext(scripts.reject, ctx).action === 'submitted');
check(ctx.sent === 1);
check(ctx.fields['input[name="reason"]'].value === 'Other');
check(ctx.fields['input[name="comments"]'].value.includes('globalThis.pwned'));
check(!ctx.pwned);
ctx = context();
check(vm.runInNewContext(scripts.badID, ctx).action === 'error');
check(ctx.sent === 0);
ctx = context({host: 'evil.example'});
check(vm.runInNewContext(scripts.reject, ctx).action === 'error');
check(ctx.sent === 0);
check(vm.runInNewContext(scripts.verify, context()).verified === true);
for (const options of [{present: true}, {ready: false}, {login: true}, {host: 'evil.example'}]) {
    check(vm.runInNewContext(scripts.verify, context(options)).verified === false);
}
console.log(`QRZ rejection transport: ${checks} checks passed (correct form, literal comments, trusted host/ID, positive page verification).`);
''')
    subprocess.run(['node', str(out/'transport.js'), str(out/'scripts.json')], check=True)
