"""Render the production discovery view with offline state fixtures, without AppState or credentials."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/yaam-sked-discovery-visual')
out.mkdir(parents=True, exist_ok=True)
view = (root / 'YAAM/SKEDContactDiscoveryView.swift').read_text()
for before, after in {
    '@State private var contacts: [SKEDDiscoveryContact] = []': '@State private var contacts = Fixture.contacts',
    '@State private var selected: Set<String> = []': '@State private var selected = Fixture.selected',
    '@State private var loading = false': '@State private var loading = Fixture.loading',
    '@State private var progress = ""': '@State private var progress = Fixture.progress',
    '@State private var failures: [String] = []': '@State private var failures = Fixture.failures',
    '@State private var searched = false': '@State private var searched = Fixture.searched',
    '@State private var historyOnly = false': '@State private var historyOnly = Fixture.historyOnly',
}.items():
    assert before in view, before
    view = view.replace(before, after)
source = view + r'''
import AppKit
@MainActor enum Fixture {
 static var contacts: [SKEDDiscoveryContact] = []
 static var selected: Set<String> = []
 static var loading = false
 static var progress = ""
 static var failures: [String] = []
 static var searched = false
 static var historyOnly = false
}
@MainActor func snapshot(name: String, width: CGFloat, height: CGFloat, dark: Bool) throws {
 let app = NSApplication.shared; app.setActivationPolicy(.accessory)
 let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
 app.appearance = appearance
 let country = SKEDCountryOption(iso: "ir", regionID: "me", serviceName: "Iran")
 let root = SKEDContactDiscoveryView(geography: .init(regions: [], countries: [country], states: []),
     localContacts: [], token: nil, userAgent: "YAAM-visual-fixture", onPrepare: { _, _ in })
 let view = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
 view.appearance = appearance
 let size = CGSize(width: width, height: height)
 let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
 window.contentView = view; view.frame = CGRect(origin: .zero, size: size)
 window.makeKeyAndOrderFront(nil)
 RunLoop.current.run(until: Date().addingTimeInterval(0.25))
 view.layoutSubtreeIfNeeded(); window.display()
 let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
 view.cacheDisplay(in: view.bounds, to: bitmap)
 try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
 window.orderOut(nil)
}
@main struct Main {
 @MainActor static func main() throws {
  try snapshot(name: "initial-light-700", width: 700, height: 440, dark: false)
  Fixture.searched = true
  Fixture.contacts = [
   .init(operatorInfo: .init(rank: 1, callsign: "EP1TEST", name: "Alex Example", email: "alex@example.org", score: nil, confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil),
     countryISO: "ir", countryName: "Iran", workedBands: ["20m"], sources: ["Your log", "QRZ Rank"]),
   .init(operatorInfo: .init(rank: 2, callsign: "EP2TEST", name: "Another Operator", email: "another@example.org", score: nil, confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil),
     countryISO: "ir", countryName: "Iran", workedBands: [], sources: ["QRZ Rank"])]
  Fixture.selected = ["EP1TEST"]
  try snapshot(name: "selected-dark-1000", width: 1000, height: 750, dark: true)
  try snapshot(name: "selected-light-700", width: 700, height: 650, dark: false)
  Fixture.loading = true; Fixture.progress = "1 / 24 · Iran"
  try snapshot(name: "loading-dark-700", width: 700, height: 650, dark: true)
  Fixture.loading = false; Fixture.failures = ["Iran: The SKED service returned HTTP 503."]
  try snapshot(name: "partial-light-1000", width: 1000, height: 750, dark: false)
  Fixture.contacts = []; Fixture.failures = []; Fixture.selected = []; Fixture.historyOnly = true
  try snapshot(name: "empty-dark-700", width: 700, height: 650, dark: true)
 }
}
'''
with tempfile.TemporaryDirectory(prefix='yaam-sked-render-') as tmp:
    swift = Path(tmp) / 'Discovery.swift'
    swift.write_text(source)
    binary = Path(tmp) / 'render'
    names = ['SKEDContactDiscovery', 'SKEDDirectoryService', 'SKEDGeographyService', 'QRZRankAPIContract', 'CSVExportSafety', 'SKEDPlanning']
    subprocess.run(['swiftc', '-parse-as-library', str(swift), *[str(root/'YAAM'/f'{x}.swift') for x in names], '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(out)], check=True)
print(out)
