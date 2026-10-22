"""Render the actual picker and native MapKit map with an inert location-service fixture."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/yaam-station-location-visual')
out.mkdir(parents=True, exist_ok=True)
view = (root/'YAAM/StationLocationPickerView.swift').read_text()
view = view.replace('@State private var showManual = false', '@State private var showManual = Fixture.manual')
view = view.replace('.onAppear { if let point { synchronize(point) } }', '''.onAppear {
 if let point { synchronize(point) }
 if Fixture.invalid { latitude = "91"; longitude = "200"; inputError = "Enter valid latitude (−90 to 90) and longitude (−180 to 180)." }
}''')
source = view + r'''
import AppKit
@MainActor enum Fixture {
 static var manual = false
 static var invalid = false
 static var loading = false
 static var message = ""
}
@MainActor final class StationLocationService: ObservableObject {
 @Published var fix: StationLocationFix?
 @Published var isLocating = Fixture.loading
 @Published var message = Fixture.message
 func start() { isLocating = true }
 func cancel() { isLocating = false; message = "" }
}
@MainActor func snapshot(name: String, width: CGFloat, height: CGFloat, dark: Bool, grid: String, lat: String, lon: String) throws {
 let app = NSApplication.shared; app.setActivationPolicy(.accessory)
 let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
 app.appearance = appearance
 let root = StationLocationPickerView(grid: grid, latitude: lat, longitude: lon, onApply: { _ in })
 let view = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
 view.appearance = appearance
 let size = CGSize(width: width, height: height)
 let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
 window.contentView = view; view.frame = CGRect(origin: .zero, size: size)
 window.makeKeyAndOrderFront(nil)
 RunLoop.current.run(until: Date().addingTimeInterval(4.0))
 view.layoutSubtreeIfNeeded(); window.display()
 let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
 view.cacheDisplay(in: view.bounds, to: bitmap)
 try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
 window.orderOut(nil)
}
@main struct Main {
 @MainActor static func main() throws {
  try snapshot(name: "world-light-680", width: 680, height: 540, dark: false, grid: "", lat: "", lon: "")
  try snapshot(name: "selected-dark-1000", width: 1000, height: 800, dark: true, grid: "IO91WM", lat: "51.5074", lon: "-0.1278")
  Fixture.manual = true
  try snapshot(name: "manual-light-680", width: 680, height: 760, dark: false, grid: "IO91WM", lat: "51.5074", lon: "-0.1278")
  Fixture.invalid = true
  try snapshot(name: "invalid-dark-680", width: 680, height: 760, dark: true, grid: "IO91WM", lat: "51.5074", lon: "-0.1278")
  Fixture.invalid = false; Fixture.message = "Location access is unavailable. Enable YAAM in System Settings or use manual entry or the map."
  try snapshot(name: "denied-light-1000", width: 1000, height: 800, dark: false, grid: "IO91", lat: "", lon: "")
  Fixture.manual = false; Fixture.loading = true; Fixture.message = "Finding your location…"
  try snapshot(name: "locating-dark-680", width: 680, height: 650, dark: true, grid: "", lat: "", lon: "")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='yaam-grid-visual-') as tmp:
    swift = Path(tmp)/'Picker.swift'
    swift.write_text(source)
    binary = Path(tmp)/'render'
    subprocess.run(['swiftc','-parse-as-library',str(swift),str(root/'YAAM/PreciseGridLocator.swift'),'-o',str(binary)], check=True)
    subprocess.run([str(binary),str(out)], check=True)
print(out)
