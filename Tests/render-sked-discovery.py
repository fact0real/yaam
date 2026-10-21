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
    '@State private var countryStatuses: [String: SKEDCountryLoadStatus] = [:]': '@State private var countryStatuses = Fixture.statuses',
    '@State private var expandedCountries: Set<String> = []': '@State private var expandedCountries = Fixture.expanded',
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
 static var statuses: [String: SKEDCountryLoadStatus] = [:]
 static var expanded: Set<String> = ["de"]
 static var logChanged = false
 static var history = SKEDCountryBandHistory(worked: ["fr": ["10m"]], missingBandCounts: ["it": 1])
}
@MainActor func snapshot(name: String, width: CGFloat, height: CGFloat, dark: Bool) throws {
 let app = NSApplication.shared; app.setActivationPolicy(.accessory)
 let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
 app.appearance = appearance
 let countries = [SKEDCountryOption(iso: "at", regionID: "eu", serviceName: "Austria"),
     SKEDCountryOption(iso: "fr", regionID: "eu", serviceName: "France"),
     SKEDCountryOption(iso: "de", regionID: "eu", serviceName: "Germany"),
     SKEDCountryOption(iso: "it", regionID: "eu", serviceName: "Italy")]
 let root = SKEDContactDiscoveryView(geography: .init(regions: [], countries: countries, states: []),
     localContacts: [], countryHistory: Fixture.history, logChanged: Fixture.logChanged, token: nil, userAgent: "YAAM-visual-fixture", onPrepare: { _, _ in })
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
   .init(operatorInfo: .init(rank: 1, callsign: "DL1TEST", name: "Alex Example", email: "alex@example.org", score: nil, confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil),
     countryISO: "de", countryName: "Germany", workedBands: ["20m"], sources: ["Your log", "QRZ Rank"]),
   .init(operatorInfo: .init(rank: 2, callsign: "I1TEST", name: "Another Operator", email: "another@example.org", score: nil, confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil),
     countryISO: "it", countryName: "Italy", workedBands: [], sources: ["QRZ Rank"])]
  Fixture.selected = ["DL1TEST"]
  Fixture.statuses = ["de": .complete, "it": .complete, "at": .complete]
  try snapshot(name: "selected-dark-1000", width: 1000, height: 750, dark: true)
  try snapshot(name: "selected-light-700", width: 700, height: 650, dark: false)
  Fixture.loading = true; Fixture.progress = "2 / 3 · Germany"; Fixture.statuses = ["at": .complete, "de": .loading]
  try snapshot(name: "loading-dark-700", width: 700, height: 650, dark: true)
  Fixture.loading = false; Fixture.failures = ["Italy: The SKED service returned HTTP 503."]; Fixture.statuses = ["at": .complete, "de": .partial, "it": .failed]
  try snapshot(name: "partial-light-1000", width: 1000, height: 750, dark: false)
  Fixture.contacts = []; Fixture.failures = []; Fixture.selected = []; Fixture.statuses = ["at": .complete, "de": .complete, "it": .complete]
  try snapshot(name: "empty-dark-700", width: 700, height: 650, dark: true)
  Fixture.logChanged = true
  try snapshot(name: "stale-log-dark-700", width: 700, height: 650, dark: true)
  Fixture.logChanged = false
  Fixture.searched = false; Fixture.history = .init(worked: ["at": ["10m"], "de": ["10m"], "it": ["10m"], "fr": ["10m"]])
  try snapshot(name: "all-worked-light-700", width: 700, height: 700, dark: false)
 }
}
'''
with tempfile.TemporaryDirectory(prefix='yaam-sked-render-') as tmp:
    swift = Path(tmp) / 'Discovery.swift'
    swift.write_text(source)
    binary = Path(tmp) / 'render'
    names = ['SKEDCountryDiscovery', 'SKEDContactDiscovery', 'SKEDDirectoryService', 'SKEDGeographyService', 'QRZRankAPIContract', 'CSVExportSafety', 'SKEDPlanning']
    subprocess.run(['swiftc', '-parse-as-library', str(swift), *[str(root/'YAAM'/f'{x}.swift') for x in names], '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(out)], check=True)
print(out)
