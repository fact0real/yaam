import SwiftUI
import MapKit

struct StationLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = StationLocationService()
    let onApply: (StationLocationSelection) -> Void
    @State private var point: GridLocationPoint?
    @State private var camera: MapCameraPosition
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var gridInput = ""
    @State private var precision = 10
    @State private var representsGridCenter = false
    @State private var source = "Choose a location to preview its grid."
    @State private var inputError: String?
    @State private var showManual = false
    @State private var satellite = false

    init(grid: String, latitude: String, longitude: String, onApply: @escaping (StationLocationSelection) -> Void) {
        self.onApply = onApply
        let coordinates = PreciseGridLocator.point(latitude: latitude, longitude: longitude)
        let box = PreciseGridLocator.bounds(grid)
        let initial = coordinates ?? box?.center
        _point = State(initialValue: initial)
        _representsGridCenter = State(initialValue: coordinates == nil && box != nil)
        _latitude = State(initialValue: initial?.latitudeText ?? "")
        _longitude = State(initialValue: initial?.longitudeText ?? "")
        _gridInput = State(initialValue: box?.grid ?? "")
        _precision = State(initialValue: coordinates != nil ? 10 : max(4, box?.grid.count ?? 10))
        _source = State(initialValue: coordinates != nil ? "Existing station coordinates · accuracy not measured" : box != nil ? "Existing grid center · your station may be anywhere inside this cell" : "Choose a location to preview its grid.")
        _camera = State(initialValue: initial.map { Self.position($0, span: coordinates != nil ? 0.02 : max(box?.latitudeSize ?? 1, 0.02) * 3) } ?? Self.world)
    }

    private static var world: MapCameraPosition {
        .rect(MKMapRect.world)
    }
    private static func position(_ point: GridLocationPoint, span: Double) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: .init(latitude: min(85, max(-85, point.latitude)), longitude: point.longitude),
            span: .init(latitudeDelta: min(150, span), longitudeDelta: min(350, span * 1.5))))
    }
    private var selection: StationLocationSelection? { point.flatMap { StationLocationSelection(point: $0, length: precision) } }
    private var box: PreciseGridBounds? { selection.flatMap { PreciseGridLocator.bounds($0.grid) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "location.viewfinder").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose your station location").font(.title2.bold())
                    Text("Locate automatically, enter coordinates, or click the world map.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack { locationActions; Spacer(); mapActions }
                        VStack(alignment: .leading, spacing: 8) { locationActions; mapActions }
                    }
                    if !location.message.isEmpty {
                        HStack {
                            if location.isLocating { ProgressView().controlSize(.small) }
                            Text(location.message).font(.callout).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup("Enter coordinates or a grid", isExpanded: $showManual) { manualEntry.padding(.top, 10) }
                    if let inputError { Label(inputError, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                    map.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Click to place the pin. Zoom in to refine it; the outlined area is the selected grid cell.")
                        .font(.caption).foregroundStyle(.secondary)
                    preview
                }.padding(18)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if let selection { Text(selection.grid).font(.callout.monospaced().bold()) }
                    if hasUnappliedEdits {
                        Text("Apply or restore your manual entry before continuing.").font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Applies to this station draft. Save the profile to keep it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    guard let selection else { return }
                    location.cancel()
                    onApply(selection)
                    dismiss()
                } label: { Label("Use this location", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.borderedProminent).disabled(selection == nil || location.isLocating || hasUnappliedEdits)
            }.padding(16)
        }
        .frame(minWidth: 680, idealWidth: 860, minHeight: 460, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: precision) { old, _ in
            if let point, latitude == point.latitudeText, longitude == point.longitudeText,
               gridInput == PreciseGridLocator.locator(point, length: old) {
                gridInput = PreciseGridLocator.locator(point, length: precision) ?? ""
            }
        }
        .onAppear { if let point { synchronize(point) } }
        .onChange(of: location.fix) { _, fix in
            guard let fix else { return }
            accept(fix.point, source: "Device location · reported accuracy ±\(String(format: "%.0f", ceil(fix.accuracy))) m", recenter: true)
        }
        .onDisappear { location.cancel() }
    }

    private var locationActions: some View {
        HStack {
            Button {
                inputError = nil
                precision = 10
                location.start()
            } label: { Label("Locate me", systemImage: "location.fill") }
                .buttonStyle(.borderedProminent).disabled(location.isLocating)
            if location.isLocating { Button("Stop") { location.cancel() } }
            Button { showManual.toggle() } label: { Label("Enter manually", systemImage: "keyboard") }
        }
    }
    private var mapActions: some View {
        HStack {
            Button("World") { camera = Self.world }
            Button("Zoom to pin") { if let point { camera = Self.position(point, span: 0.005) } }.disabled(point == nil)
            Toggle("Satellite", isOn: $satellite).toggleStyle(.checkbox)
        }.controlSize(.small)
    }
    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let point {
                    Annotation("Selected location", coordinate: .init(latitude: point.latitude, longitude: point.longitude), anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 32))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color.accentColor)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    }
                }
                if let box {
                    MapPolygon(coordinates: [
                        .init(latitude: box.minLatitude, longitude: box.minLongitude),
                        .init(latitude: box.minLatitude, longitude: box.minLongitude + box.longitudeSize),
                        .init(latitude: box.minLatitude + box.latitudeSize, longitude: box.minLongitude + box.longitudeSize),
                        .init(latitude: box.minLatitude + box.latitudeSize, longitude: box.minLongitude)
                    ]).foregroundStyle(Color.accentColor.opacity(0.13)).stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat))
            .mapControls { MapCompass(); MapScaleView(); MapZoomStepper() }
            .mapControlVisibility(.visible)
            .onTapGesture(coordinateSpace: .local) { position in
                guard let coordinate = proxy.convert(position, from: .local),
                      let value = GridLocationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return }
                location.cancel()
                accept(value, source: "Map selection · positional accuracy is not measured", recenter: false)
            }
            .accessibilityLabel("World map. Click a location to select the station pin.")
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection?.grid ?? "No location selected").font(.title2.monospaced().bold()).textSelection(.enabled)
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Grid length", selection: $precision) {
                    ForEach(PreciseGridLocator.precisions, id: \.self) { Text("\($0) characters").tag($0) }
                }.frame(maxWidth: 220)
            }
            if let selection, let box {
                Text("Latitude \(selection.latitude) · Longitude \(selection.longitude)")
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("Grid cell: approximately \(Int(box.widthMeters.rounded())) × \(Int(box.heightMeters.rounded())) m. Grid resolution is separate from location accuracy.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if abs(selection.point.latitude) > 85 {
                    Text("Polar coordinates are retained exactly; the map projection cannot display the poles.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if hasUnappliedEdits {
                Label("Apply your manual entry below, or restore the selected location, before continuing.", systemImage: "pencil.circle")
                    .font(.caption).foregroundStyle(.orange)
                Button("Restore selected values") { if let point { synchronize(point) } }
            }
        }.padding(14).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latitude · −90…90").font(.caption).foregroundStyle(.secondary)
                    TextField("Latitude", text: $latitude).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Longitude · −180…180").font(.caption).foregroundStyle(.secondary)
                    TextField("Longitude", text: $longitude).textFieldStyle(.roundedBorder)
                }
                Button("Use coordinates") {
                    guard let value = PreciseGridLocator.point(latitude: latitude, longitude: longitude) else {
                        inputError = "Enter valid decimal latitude (−90 to 90) and longitude (−180 to 180)."; return
                    }
                    location.cancel()
                    accept(value, source: "Entered coordinates · positional accuracy is not measured", recenter: true)
                }
            }
            HStack {
                TextField("Grid, e.g. IO91WM or IO91WM12", text: $gridInput).textFieldStyle(.roundedBorder)
                Button("Use grid center") {
                    guard let box = PreciseGridLocator.bounds(gridInput), box.grid.count >= 4 else {
                        inputError = "Enter a complete 4, 6, 8 or 10-character Maidenhead grid."; return
                    }
                    precision = box.grid.count
                    location.cancel()
                    accept(box.center, source: "Entered grid center · your station may be anywhere inside this cell", recenter: true, gridCenter: true)
                }
            }
        }.disabled(location.isLocating)
    }
    private var hasUnappliedEdits: Bool {
        guard let point else { return false }
        return latitude != point.latitudeText || longitude != point.longitudeText || gridInput != (PreciseGridLocator.locator(point, length: precision) ?? "")
    }
    private func synchronize(_ value: GridLocationPoint) {
        latitude = value.latitudeText; longitude = value.longitudeText
        gridInput = PreciseGridLocator.locator(value, length: precision) ?? ""
    }
    private func accept(_ value: GridLocationPoint, source: String, recenter: Bool, gridCenter: Bool = false) {
        if representsGridCenter && !gridCenter { precision = 10 }
        representsGridCenter = gridCenter
        point = value
        self.source = source
        inputError = nil
        synchronize(value)
        if recenter { camera = Self.position(value, span: 0.01) }
    }
}
