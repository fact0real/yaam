import SwiftUI

struct DXLivePropagationView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var live = DXLivePropagationStore.shared
    @State private var showEquipment = false
    @State private var profileDraft = StationProfile()
    @State private var equipmentStatus = ""

    private var activeProfile: StationProfile? { appState.activeStationProfile }
    private var stationHasPosition: Bool {
        guard let profile = activeProfile else { return false }
        return !profile.grid.isEmpty || (Double(profile.latitude) != nil && Double(profile.longitude) != nil)
    }
    private var stationCoordinate: GeoCoordinate { appState.effectiveStationCoordinate }
    private var stationGrid: String {
        let grid = appState.effectiveStationGrid
        if !grid.isEmpty { return grid }
        return stationHasPosition ? MaidenheadGridEngine.locator(from: stationCoordinate) : ""
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stationCard
                HStack(alignment: .top, spacing: 14) {
                    evidenceSummary
                    noaaCard
                }
                HStack(alignment: .top, spacing: 14) {
                    receptionCard
                    wsprCard
                }
                HStack(alignment: .top, spacing: 14) {
                    skimmerCard
                    ionosondeCard
                }
                beaconCard
                Text("Reception reports are measurements, not guarantees for another station or mode. Missing reports do not prove a band is closed. WSPR and ionosonde distances are checked on this Mac. Beacon entries are a transmission schedule, not receptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Color(NSColor.textBackgroundColor))
        .task(id: appState.activeStationProfileID) {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(120))
            }
        }
        .sheet(isPresented: $showEquipment) { equipmentSheet }
    }

    private func refresh() {
        live.refresh(callsign: activeProfile?.normalizedCallsign ?? "", grid: stationGrid,
                     coordinate: stationCoordinate)
    }

    private var stationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your station · \(activeProfile?.normalizedCallsign ?? "Not set")", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                if live.isRefreshing { ProgressView().controlSize(.small) }
                Button("Refresh sources") {
                    live.refresh(callsign: activeProfile?.normalizedCallsign ?? "", grid: stationGrid,
                                 coordinate: stationCoordinate, force: true)
                }
                .disabled(live.isRefreshing)
                Button("Station equipment") {
                    if let profile = activeProfile { profileDraft = profile }
                    equipmentStatus = ""
                    showEquipment = true
                }
            }
            if !live.refreshNotice.isEmpty {
                Text(live.refreshNotice).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                metric("Grid", stationGrid.isEmpty ? "Missing" : stationGrid)
                metric("Radio", activeProfile?.radioModel.isEmpty == false ? activeProfile!.radioModel : "Missing")
                metric("Power", activeProfile?.antennaDescription.isEmpty == false ? "\(activeProfile!.powerWatts) W" : "Verify profile default")
                metric("Antenna", activeProfile?.antennaDescription.isEmpty == false ? activeProfile!.antennaDescription : "Missing")
                metric("Height", activeProfile?.antennaDescription.isEmpty == false ? "\(activeProfile!.antennaHeightMeters) m" : "Verify profile default")
            }
            if !stationHasPosition || activeProfile?.antennaDescription.isEmpty != false || activeProfile?.radioModel.isEmpty != false {
                Label("Complete the station position, radio and antenna to personalize path planning. Please confirm the profile's default power and height values.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.16)))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var freshReceptions: [DXReception] {
        live.receptions.filter { Date().timeIntervalSince($0.observedAt) <= 7200 }
    }

    private var observedBands: [String] {
        let groups = Dictionary(grouping: freshReceptions, by: \.band)
        return groups.keys.sorted { groups[$0, default: []].count > groups[$1, default: []].count }
    }

    private var evidenceSummary: some View {
        let reports = freshReceptions
        let countries = Set(reports.map(\.country).filter { $0 != "Unknown" })
        let farthest = reports.compactMap(\.distanceKm).max()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("YOUR SIGNAL · OBSERVED REACH", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("PSK Reporter · last 2 h").font(.caption2).foregroundStyle(.secondary)
            }
            if let primary = observedBands.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(primary).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
                    Text("most observed band").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    summaryValue("Reports", "\(reports.count)")
                    summaryValue("Countries", "\(countries.count)")
                    summaryValue("Farthest", farthest.map { "\($0) km" } ?? "—")
                }
                HStack(spacing: 8) {
                    ForEach(Array(observedBands.prefix(5)), id: \.self) { band in
                        Text("\(band)  \(reports.filter { $0.band == band }.count)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.13), in: Capsule())
                    }
                }
                Text("Measured decodes of your callsign; this is evidence of transmission, not a band forecast.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No station reception measured in the last 2 hours")
                    .font(.title3.weight(.semibold))
                Text("Transmit a short CQ on your operating mode, then check PSK Reporter. NOAA and regional reference data remain available below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(LinearGradient(colors: [Color.accentColor.opacity(0.14), Color.cyan.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.22)))
    }

    private func summaryValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded).weight(.bold))
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private var noaaCard: some View {
        card("NOAA SWPC · space weather", icon: "sun.max.fill", status: live.noaaStatus) {
            HStack(alignment: .top, spacing: 14) {
                noaaMetric("Estimated Kp", live.noaa.estimatedKp.map { String(format: "%.1f", $0) } ?? "—",
                           at: live.noaa.kpObservedAt, detail: "Global geomagnetic",
                           color: (live.noaa.estimatedKp ?? 0) >= 5 ? .orange : .green)
                noaaMetric("Solar flux", live.noaa.solarFlux.map { String(format: "%.0f", $0) } ?? "—",
                           at: live.noaa.fluxObservedAt, detail: "Daily 10.7 cm · sfu", color: .orange)
                noaaMetric("Radio blackout", live.noaa.radioBlackoutScale.map { "R\($0)" } ?? "—",
                           at: live.noaa.scalesObservedAt, detail: "Sunlit-side HF scale",
                           color: (live.noaa.radioBlackoutScale ?? 0) > 0 ? .red : .green)
            }
            Text("These are global indicators; the measured station reports below are stronger evidence for a specific path.")
                .font(.caption2).foregroundStyle(.secondary)
            Link("Open NOAA SWPC", destination: URL(string: "https://www.swpc.noaa.gov/communities/radio-communications")!)
                .font(.caption)
        }
    }

    private func noaaMetric(_ title: String, _ value: String, at date: Date?, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
            Text(date.map { DXLivePropagationStore.age($0) } ?? "No fresh value")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(_ title: String, icon: String, status: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            content()
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.10)))
    }

    private var receptionCard: some View {
        card("PSK Reporter · my signal", icon: "dot.radiowaves.left.and.right", status: live.pskStatus) {
            if !live.receptions.isEmpty {
                HStack {
                    Text("RECEIVER").frame(width: 85, alignment: .leading)
                    Text("COUNTRY").frame(maxWidth: .infinity, alignment: .leading)
                    Text("BAND").frame(width: 40)
                    Text("SNR").frame(width: 40)
                    Text("AGE").frame(width: 56, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            ForEach(live.receptions.prefix(8)) { report in
                HStack(spacing: 8) {
                    Text(report.receiver).font(.caption.monospaced().weight(.semibold)).frame(width: 85, alignment: .leading)
                    Text(report.country).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(report.band).font(.caption.weight(.semibold)).frame(width: 40)
                    Text(report.snr.map { "\($0)" } ?? "—").font(.caption.monospaced()).frame(width: 40)
                    Text(DXLivePropagationStore.age(report.observedAt)).font(.caption2).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                }
            }
            if let farthest = live.receptions.compactMap(\.distanceKm).max() {
                Text("Farthest measured reception: \(farthest) km · \(live.receptions.count) sampled reports")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Link("Open PSK Reporter", destination: URL(string: "https://pskreporter.info/pskmap.html")!)
                .font(.caption)
        }
    }

    private var wsprCard: some View {
        card("WSPR · receiver evidence", icon: "waveform.path", status: live.wsprStatus) {
            ForEach(live.wsprBands.prefix(6)) { band in
                HStack {
                    Text(band.band).font(.caption.monospaced().weight(.bold)).frame(width: 42, alignment: .leading)
                    Text("\(band.reports) reports").font(.caption)
                    Spacer()
                    Text(DXLivePropagationStore.age(band.latest)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if live.wsprBands.isEmpty && !live.wsprReceivers.isEmpty {
                Text("NEAREST AVAILABLE RECEIVERS")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                ForEach(live.wsprReceivers.prefix(6)) { receiver in
                    HStack {
                        Text(receiver.grid).font(.caption.monospaced().weight(.semibold)).frame(width: 48, alignment: .leading)
                        Text("\(receiver.distanceKm) km").font(.caption)
                        Text(receiver.band).font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(receiver.reports) reports").font(.caption)
                        Text(DXLivePropagationStore.age(receiver.latest)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("These receivers are outside your local 600 km area. Their decodes are context, not proof of a path from your antenna.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Link("Open WSPR.live", destination: URL(string: "https://wspr.live/")!).font(.caption)
        }
    }

    private var skimmerCard: some View {
        card("Reverse Beacon Network · direct", icon: "waveform.badge.magnifyingglass", status: live.rbnStatus) {
            ForEach(live.rbnReceptions.prefix(6)) { spot in
                HStack {
                    Text(spot.spotter).font(.caption.monospaced().weight(.semibold))
                    Text(spot.band).font(.caption)
                    Text(spot.mode).font(.caption)
                    Text("\(spot.snr) dB").font(.caption)
                    Spacer()
                    Text(DXLivePropagationStore.age(spot.observedAt)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if live.rbnReceptions.isEmpty {
                Text("RBN spots depend on skimmer coverage and what you transmit. Try a short CW CQ; use PSK Reporter above for your current FT8 reception evidence.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Link("Open Reverse Beacon Network", destination: URL(string: "https://www.reversebeacon.net/")!).font(.caption)
        }
    }

    private var ionosondeCard: some View {
        card("GIRO · nearest ionosondes", icon: "waveform.path.ecg", status: live.ionoStatus) {
            ForEach(live.ionosondes.prefix(4)) { station in
                HStack {
                    VStack(alignment: .leading) {
                        Text(station.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text("\(station.distanceKm) km · \(DXLivePropagationStore.age(station.observedAt))" + (station.confidence.map { " · CS \(Int($0))" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "foF2 %.1f MHz", station.foF2MHz)).font(.caption.monospaced())
                }
            }
            if let nearest = live.ionosondes.first {
                Text(nearest.distanceKm > 2000 ? "Nearest fresh station is remote; do not use this as a local NVIS measurement." : "foF2 is a vertical critical frequency. 80m (~3.5 MHz) and 40m (~7 MHz) need suitable foF2, but absorption and antenna geometry also matter.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Link("GIRO measurements", destination: URL(string: "https://giro.uml.edu/didbase/")!).font(.caption)
        }
    }

    private var beaconCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("NCDXF / IARU · scheduled beacons", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Link("Official schedule & beacon status", destination: URL(string: "https://www.ncdxf.org/beacon/")!)
                    .font(.caption)
            }
            Text("The table shows who is scheduled to transmit on each frequency now. Tune your receiver to verify whether the path is actually open. Each 10-second slot sends 100 W, 10 W, 1 W and 0.1 W steps.")
                .font(.caption).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let slot = ((Int(context.date.timeIntervalSince1970 / 10) % 18) + 18) % 18
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.beaconFrequencies[index]).font(.caption.monospaced().weight(.bold))
                            Text(Self.beaconCallsigns[(slot - index + 18) % 18]).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private static let beaconFrequencies = ["14.100 MHz", "18.110 MHz", "21.150 MHz", "24.930 MHz", "28.200 MHz"]
    private static let beaconCallsigns = ["4U1UN", "VE8AT", "W6WX", "KH6RS", "ZL6B", "VK6RBP", "JA2IGY", "RR9O", "VR2B", "4S7B", "ZS6DN", "5Z4B", "4X6TU", "OH2B", "CS3B", "LU4AA", "OA4B", "YV5B"]

    private var equipmentSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Station equipment for DX Advisor").font(.title3.weight(.semibold))
            Text("Saved to the active station profile and used for path planning.").font(.caption).foregroundStyle(.secondary)
            Form {
                TextField("Grid locator", text: $profileDraft.grid)
                TextField("Radio model", text: $profileDraft.radioModel)
                TextField("Power (W)", value: $profileDraft.powerWatts, format: .number)
                TextField("Antenna type", text: $profileDraft.antennaDescription)
                TextField("Antenna height (m)", value: $profileDraft.antennaHeightMeters, format: .number)
            }
            if !equipmentStatus.isEmpty { Text(equipmentStatus).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { showEquipment = false }
                Button("Save station") {
                    do {
                        try appState.saveStationProfile(profileDraft)
                        showEquipment = false
                        refresh()
                    } catch { equipmentStatus = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
