//
//  DXAdvisorView.swift
//  YAAM
//

import SwiftUI
import AppKit

private struct DXCoordinate {
    let latitude: Double
    let longitude: Double
}

private struct DXBandPathScore: Identifiable {
    let id = UUID()
    let band: String
    let score: Int
    let condition: String
    let window: String
    let reason: String
}

private struct DXPathPrediction: Identifiable {
    let id = UUID()
    let country: String
    let coordinate: DXCoordinate
    let distanceKm: Double
    let bearing: Double
    let isWorked: Bool
    let needsConfirmation: Bool
    let unconfirmedBands: [String]
    let bandScores: [DXBandPathScore]

    var bestScore: DXBandPathScore? {
        bandScores.max { $0.score < $1.score }
    }
}

struct DXAdvisorView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("stationGrid") private var stationGrid = ""
    @AppStorage("radioModel") private var radioModel = ""
    @AppStorage("radioPowerWatts") private var radioPowerWatts = 100
    @AppStorage("antennaDescription") private var antennaDescription = ""
    @AppStorage("antennaHeightMeters") private var antennaHeightMeters = 10
    @State private var cachedPathPredictions: [DXPathPrediction] = []
    @State private var isCalculatingPathPredictions = false
    @State private var bulkEmailTemplate = "LoTW/QRZ Confirmation"
    @State private var isSendingBulkEmail = false
    @State private var bulkEmailStatus = ""
    @State private var selectedBulkEmailCallsigns: Set<String> = []
    @State private var fetchingEmailCallsigns: Set<String> = []

    private var utcHour: Int {
        Calendar(identifier: .gregorian).component(.hour, from: Date())
    }

    private var recommendedBands: [String] {
        let baseBands: [String]
        switch utcHour {
        case 5..<9:
            baseBands = ["40M", "30M", "20M", "17M"]
        case 9..<15:
            baseBands = ["20M", "17M", "15M", "12M", "10M"]
        case 15..<20:
            baseBands = ["17M", "20M", "30M", "40M"]
        default:
            baseBands = ["40M", "30M", "80M", "160M"]
        }

        return baseBands.sorted {
            propagationScore(for: $0) > propagationScore(for: $1)
        }
    }

    private var workedCountries: Set<String> {
        Set(appState.qsoRecords.map { $0["COUNTRY"] }.filter { !$0.isEmpty })
    }

    private var confirmedCountries: Set<String> {
        Set(appState.qsoRecords.filter { $0.isConfirmed }.map { $0["COUNTRY"] }.filter { !$0.isEmpty })
    }

    private var unconfirmedCountries: [String] {
        Array(workedCountries.subtracting(confirmedCountries)).sorted()
    }

    private var bandTargets: [UnconfirmedBandCountryStatModel] {
        appState.unconfirmedBandCountryStatistics.filter { recommendedBands.contains($0.band) }
    }

    private var emailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    private var stationCoordinate: DXCoordinate? {
        coordinate(fromMaidenhead: stationGrid)
    }

    private var amateurBands: [String] {
        ["160M", "80M", "40M", "30M", "20M", "17M", "15M", "12M", "10M"]
    }

    private var bulkEmailRecipients: [BulkEmailRecipient] {
        appState.bulkEmailRecipients(limit: 25)
    }

    private var selectedBulkEmailRecipients: [BulkEmailRecipient] {
        bulkEmailRecipients.filter { selectedBulkEmailCallsigns.contains($0.callsign) }
    }

    private var pathPredictions: [DXPathPrediction] {
        cachedPathPredictions
    }

    private func makePathPredictions() -> [DXPathPrediction] {
        guard let origin = stationCoordinate else { return [] }

        let unconfirmedBandMap = Dictionary(
            uniqueKeysWithValues: appState.unconfirmedBandCountryStatistics.map { stat in
                (stat.band, Set(stat.countries.map { normalizedCountryName($0.country) }))
            }
        )

        let targetCountries = Set(
            appState.countryStatistics
                .map { $0.country }
                .filter { !$0.isEmpty && $0 != "Unknown" }
        )

        return targetCountries.compactMap { country -> DXPathPrediction? in
            guard let target = coordinate(forCountry: country) else { return nil }

            let distance = greatCircleDistanceKm(from: origin, to: target)
            let bearing = initialBearing(from: origin, to: target)
            let normalizedCountry = normalizedCountryName(country)
            let unconfirmedBands = unconfirmedBandMap.compactMap { band, countries in
                countries.contains(normalizedCountry) ? band : nil
            }.sorted(by: bandSort)

            let scores = amateurBands.map { band in
                pathScore(
                    band: band,
                    country: country,
                    target: target,
                    distanceKm: distance,
                    needsConfirmationOnBand: unconfirmedBands.contains(band)
                )
            }.sorted { $0.score > $1.score }

            return DXPathPrediction(
                country: country,
                coordinate: target,
                distanceKm: distance,
                bearing: bearing,
                isWorked: workedCountries.contains(country),
                needsConfirmation: unconfirmedCountries.contains(country),
                unconfirmedBands: unconfirmedBands,
                bandScores: scores
            )
        }
        .sorted {
            let lhs = ($0.bestScore?.score ?? 0) + ($0.needsConfirmation ? 14 : 0)
            let rhs = ($1.bestScore?.score ?? 0) + ($1.needsConfirmation ? 14 : 0)
            return lhs == rhs ? $0.distanceKm > $1.distanceKm : lhs > rhs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    propagationSummary
                    voacapPlannerSection
                    bandOpportunityMatrixSection
                    bandRecommendationSection
                    unconfirmedCountriesSection
                    unconfirmedCallsignSection
                    bulkEmailSection
                    emailHistorySection
                }
                .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            if appState.propagationSnapshot.updatedAt == nil {
                appState.fetchPropagationSnapshot()
            }
            refreshPathPredictions()
            syncBulkEmailSelection()
        }
        .onChange(of: stationGrid) { _, _ in refreshPathPredictions() }
        .onChange(of: radioPowerWatts) { _, _ in refreshPathPredictions() }
        .onChange(of: antennaDescription) { _, _ in refreshPathPredictions() }
        .onChange(of: antennaHeightMeters) { _, _ in refreshPathPredictions() }
        .onChange(of: appState.qsoRecords.count) { _, _ in refreshPathPredictions() }
        .onChange(of: bulkEmailRecipients.count) { _, _ in syncBulkEmailSelection() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .foregroundColor(.accentColor)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("DX Advisor")
                    .font(.title3)
                    .bold()
                Text("Heuristic band and confirmation targets from your YAAM log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                appState.fetchPropagationSnapshot()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(appState.isFetchingPropagation)
            .help("Refresh HamQSL propagation data")

            Text("UTC \(String(format: "%02d", utcHour)):00")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var propagationSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Propagation")
                    .font(.headline)
                Spacer()
                Text("Sources: HamQSL / N0NBH, NOAA SWPC")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            solarForecastSection

            hfBandInfoSection

            vhfPropagationSection

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                propagationCard(title: "Solar Indices", icon: "sun.max") {
                    VStack(spacing: 8) {
                        metricRow("Solar Flux", value: "\(appState.propagationSnapshot.solarFlux) sfu", color: solarFluxColor)
                        metricRow("Sunspots", value: appState.propagationSnapshot.sunspots, color: .green)
                        metricRow("X-ray", value: appState.propagationSnapshot.xray, color: .green)
                    }
                }

                propagationCard(title: "Geomagnetic", icon: "globe.europe.africa") {
                    VStack(spacing: 8) {
                        metricRow("A Index", value: appState.propagationSnapshot.aIndex, color: geomagneticColor(appState.propagationSnapshot.aIndex))
                        metricRow("K Index", value: appState.propagationSnapshot.kIndex, color: geomagneticColor(appState.propagationSnapshot.kIndex))
                        metricRow("Geomag Field", value: appState.propagationSnapshot.geomagField, color: appState.propagationSnapshot.geomagField.lowercased().contains("quiet") ? .green : .orange)
                        metricRow("Aurora", value: appState.propagationSnapshot.aurora, color: .gray)
                        metricRow("Solar Wind", value: appState.propagationSnapshot.solarWind, color: .orange)
                        metricRow("Bz", value: appState.propagationSnapshot.bz, color: .orange)
                        metricRow("Noise Level", value: appState.propagationSnapshot.signalNoise, color: .green)
                    }
                }
            }

            stationSummary
        }
    }

    private var solarForecastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("27-Day Solar Forecast", systemImage: "chart.xyaxis.line")
                .font(.headline)

            if appState.propagationSnapshot.solarForecast.isEmpty {
                emptyText("NOAA SWPC 27-day solar forecast is not available yet.")
            } else {
                SolarFluxForecastChart(points: appState.propagationSnapshot.solarForecast)
                    .frame(height: 190)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.30))
                    .cornerRadius(8)
            }
        }
    }

    private var hfBandInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HF Band Info")
                .font(.headline)
                .foregroundColor(.red)

            VStack(spacing: 0) {
                HStack {
                    Text("Band")
                        .frame(width: 150, alignment: .leading)
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                        Text("Daytime Conditions")
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundColor(.blue)
                        Text("Nighttime Conditions")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 10)

                Divider()
                hfBandInfoRow(band: "80m-40m", range: "3.5 - 7.3 MHz", group: "80M-40M")
                Divider()
                hfBandInfoRow(band: "30m-20m", range: "10.1 - 14.35 MHz", group: "30M-20M")
                Divider()
                hfBandInfoRow(band: "17m-15m", range: "18.068 - 21.45 MHz", group: "17M-15M")
                Divider()
                hfBandInfoRow(band: "12m-10m", range: "24.89 - 29.7 MHz", group: "12M-10M")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.22))
            .cornerRadius(8)
        }
    }

    private var vhfPropagationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VHF & E-Skip Propagation")
                .font(.headline)
                .foregroundColor(.red)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
                vhfConditionCard(name: "VHF Aurora", location: "Northern Hemisphere")
                vhfConditionCard(name: "E-Skip", location: "North America")
                vhfConditionCard(name: "E-Skip", location: "Europe")
                vhfConditionCard(name: "E-Skip", location: "Europe 6m")
                vhfConditionCard(name: "E-Skip", location: "Europe 4m")
            }

            Text("HamQSL currently exposes VHF/E-Skip locations for Northern Hemisphere, North America and Europe. No Asia or Middle East VHF region is present in this feed.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var bandRecommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Band Targets")
                .font(.headline)

            if bandTargets.isEmpty {
                emptyText("No unconfirmed worked countries found on the currently recommended bands.")
            } else {
                ForEach(bandTargets) { bandStat in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(bandStat.band)
                                .font(.system(.headline, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Spacer()
                            Text("\(bandStat.countries.count) countries need confirmation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(bandStat.countries.prefix(18)) { countryStat in
                                countryChip(countryStat.country, count: countryStat.qsoCount)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var voacapPlannerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("VOACAP-Style Path Planner", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text(stationCoordinate == nil ? "Set Grid in Settings" : "Ranked for current UTC hour")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if stationCoordinate == nil {
                emptyText("Enter your station Grid Locator in Settings to calculate path distance, bearing, local day/night and band suggestions.")
            } else if isCalculatingPathPredictions {
                emptyText("Calculating path predictions...")
            } else if pathPredictions.isEmpty {
                emptyText("No known country coordinates found in the current log.")
            } else {
                VStack(spacing: 0) {
                    ForEach(pathPredictions.prefix(18)) { prediction in
                        pathPredictionRow(prediction)
                        Divider()
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                .cornerRadius(8)
            }
        }
    }

    private var bandOpportunityMatrixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Band Opportunity Matrix", systemImage: "square.grid.3x3")
                .font(.headline)

            if stationCoordinate == nil {
                emptyText("Grid Locator is required for per-band country opportunity ranking.")
            } else if isCalculatingPathPredictions {
                emptyText("Calculating band opportunities...")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(amateurBands, id: \.self) { band in
                        bandOpportunityCard(band)
                    }
                }
            }
        }
    }

    private var unconfirmedCountriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Worked Countries Without Confirmation")
                .font(.headline)

            if unconfirmedCountries.isEmpty {
                emptyText("All worked countries have at least one confirmed QSO.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(unconfirmedCountries.prefix(36), id: \.self) { country in
                        countryChip(country, count: nil)
                    }
                }
            }
        }
    }

    private var unconfirmedCallsignSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Callsigns With No Confirmed QSOs")
                .font(.headline)

            if appState.callsignsWithNoConfirmedQSOs.isEmpty {
                emptyText("No callsigns found with only unconfirmed QSOs.")
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.callsignsWithNoConfirmedQSOs.prefix(40)) { item in
                        HStack(spacing: 8) {
                            Text(item.callsign)
                                .font(.system(.caption, design: .monospaced))
                                .bold()
                                .frame(width: 90, alignment: .leading)
                            Text("\(item.qsoCount) QSOs")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .frame(width: 60, alignment: .trailing)
                            Text(item.bands.isEmpty ? "-" : item.bands)
                                .font(.caption)
                                .frame(width: 120, alignment: .leading)
                            Text(item.countries.isEmpty ? "Unknown" : item.countries)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if !item.email.isEmpty {
                                Button {
                                    openEmailComposer(callsign: item.callsign, email: item.email)
                                } label: {
                                    Text(item.email)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .help("Send confirmation request to \(item.callsign)")
                            } else {
                                Button {
                                    fetchEmailAndOpenComposer(for: item)
                                } label: {
                                    HStack(spacing: 4) {
                                        if fetchingEmailCallsigns.contains(item.callsign.uppercased()) {
                                            ProgressView()
                                                .scaleEffect(0.55)
                                                .frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "envelope.badge")
                                                .font(.caption2)
                                        }
                                        Text(fetchingEmailCallsigns.contains(item.callsign.uppercased()) ? "Fetching..." : "Fetch Email")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(fetchingEmailCallsigns.contains(item.callsign.uppercased()))
                                .help("Fetch QRZ email for \(item.callsign), then open confirmation request")
                            }
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                .cornerRadius(8)
            }
        }
    }

    private var emailHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Email History")
                .font(.headline)

            if appState.emailHistory.isEmpty {
                emptyText("No email history yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.emailHistory.prefix(25)) { entry in
                        HStack(spacing: 8) {
                            Text(emailDateFormatter.string(from: entry.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 105, alignment: .leading)
                            Text(entry.callsign.isEmpty ? "-" : entry.callsign)
                                .font(.system(.caption, design: .monospaced))
                                .bold()
                                .frame(width: 80, alignment: .leading)
                            Text(entry.status)
                                .font(.caption)
                                .foregroundColor(entry.status == "Sent" ? .green : .red)
                                .frame(width: 55, alignment: .leading)
                            Text(entry.subject)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if !entry.email.isEmpty {
                                Button("Email") {
                                    openEmailComposer(callsign: entry.callsign, email: entry.email)
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .help("Send another email to \(entry.callsign)")
                            }
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                .cornerRadius(8)
            }
        }
    }

    private var bulkEmailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bulk QSL Email", systemImage: "envelope.badge")
                    .font(.headline)
                Spacer()
                Text("Max 25 per run")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(5)
                Picker("Template", selection: $bulkEmailTemplate) {
                    Text("LoTW/QRZ Confirmation").tag("LoTW/QRZ Confirmation")
                    Text("QSL Card Request").tag("QSL Card Request")
                }
                .frame(width: 230)
            }

            if bulkEmailRecipients.isEmpty {
                emptyText("No unconfirmed callsigns with email addresses are available. Enrich the log first to fetch email addresses.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(bulkEmailRecipients.count) recipients found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(selectedBulkEmailRecipients.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(5)
                        Spacer()
                        Button("Select All") {
                            selectedBulkEmailCallsigns = Set(bulkEmailRecipients.map(\.callsign))
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        Button("Clear") {
                            selectedBulkEmailCallsigns.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if isSendingBulkEmail {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Sending...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button {
                            sendBulkEmail()
                        } label: {
                            Label("Send Bulk", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingBulkEmail || selectedBulkEmailRecipients.isEmpty)
                    }

                    HStack(spacing: 8) {
                        Text("Send")
                            .frame(width: 42, alignment: .leading)
                        Text("Callsign")
                            .frame(width: 82, alignment: .leading)
                        Text("Email")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Unconfirmed QSOs")
                            .frame(width: 115, alignment: .trailing)
                        Text("Bands")
                            .frame(width: 130, alignment: .leading)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(bulkEmailRecipients) { recipient in
                                bulkEmailRecipientRow(recipient)
                                Divider()
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(minHeight: 170, maxHeight: 260)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.45))
                    .cornerRadius(8)

                    if !bulkEmailStatus.isEmpty {
                        Text(bulkEmailStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                .cornerRadius(8)
            }
        }
    }

    private func countryChip(_ country: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(countryToFlag(country))
            Text(country)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.orange)
                    .bold()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.22), lineWidth: 1))
    }

    private func bulkEmailRecipientRow(_ recipient: BulkEmailRecipient) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedBulkEmailCallsigns.contains(recipient.callsign) },
                set: { isSelected in
                    if isSelected {
                        selectedBulkEmailCallsigns.insert(recipient.callsign)
                    } else {
                        selectedBulkEmailCallsigns.remove(recipient.callsign)
                    }
                }
            ))
            .labelsHidden()
            .frame(width: 42, alignment: .leading)

            Text(recipient.callsign)
                .font(.system(.caption, design: .monospaced))
                .bold()
                .frame(width: 82, alignment: .leading)

            Text(recipient.email)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(recipient.qsoCount)")
                .font(.system(.caption, design: .monospaced))
                .bold()
                .foregroundColor(.orange)
                .frame(width: 115, alignment: .trailing)
                .help("Number of unconfirmed QSOs for this callsign")

            Text(recipient.bands.isEmpty ? "-" : recipient.bands)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func pathPredictionRow(_ prediction: DXPathPrediction) -> some View {
        let best = prediction.bestScore

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(countryToFlag(prediction.country))
                    Text(prediction.country)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                    if prediction.needsConfirmation {
                        Text("Need QSL")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(5)
                    }
                }

                Text("\(Int(prediction.distanceKm.rounded())) km, \(Int(prediction.bearing.rounded())) deg bearing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            if let best {
                conditionBadge(best.condition, icon: best.window == "day" ? "sun.max.fill" : "moon.fill")

                Text(best.band)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(conditionColor(for: best.band))
                    .frame(width: 52, alignment: .center)

                Text("\(best.score)%")
                    .font(.system(.headline, design: .rounded))
                    .bold()
                    .frame(width: 52, alignment: .trailing)

                Text(best.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 180, alignment: .leading)
            }
        }
        .padding(.vertical, 7)
    }

    private func bandOpportunityCard(_ band: String) -> some View {
        let opportunities = pathPredictions
            .compactMap { prediction -> (DXPathPrediction, DXBandPathScore)? in
                guard let score = prediction.bandScores.first(where: { $0.band == band }), score.score >= 35 else {
                    return nil
                }
                return (prediction, score)
            }
            .sorted {
                let lhs = $0.1.score + ($0.0.needsConfirmation ? 12 : 0)
                let rhs = $1.1.score + ($1.0.needsConfirmation ? 12 : 0)
                return lhs == rhs ? $0.0.country < $1.0.country : lhs > rhs
            }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(band)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(conditionColor(for: band))
                Spacer()
                Text(conditionText(for: band))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if opportunities.isEmpty {
                Text("No strong paths right now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(opportunities.prefix(5), id: \.0.id) { prediction, score in
                    HStack(spacing: 6) {
                        Text(countryToFlag(prediction.country))
                        Text(prediction.country)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if prediction.needsConfirmation {
                            Image(systemName: "checkmark.seal")
                                .foregroundColor(.orange)
                                .help("Worked but not confirmed")
                        }
                        Text("\(score.score)%")
                            .font(.system(.caption2, design: .monospaced))
                            .bold()
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(8)
    }

    private func propagationMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .bold()
        }
    }

    private var stationSummary: some View {
        HStack(spacing: 12) {
            Label(stationGrid.isEmpty ? "Grid not set" : stationGrid.uppercased(), systemImage: "location")

            Text(radioModel.isEmpty ? "\(radioPowerWatts) W" : "\(radioModel), \(radioPowerWatts) W")
                .lineLimit(1)

            Text(antennaDescription.isEmpty ? "Antenna not set" : "\(antennaDescription), \(antennaHeightMeters)m")
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(8)
    }

    private func propagationCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)

            VStack(spacing: 8) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.38))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func hfConditionRow(_ title: String, group: String) -> some View {
        let day = appState.propagationSnapshot.bands["\(group)_day"] ?? "-"
        let night = appState.propagationSnapshot.bands["\(group)_night"] ?? "-"

        return HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .bold()
                .frame(width: 82, alignment: .leading)

            Spacer(minLength: 8)

            conditionBadge(day, icon: "sun.max.fill")

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            conditionBadge(night, icon: "moon.fill")
        }
    }

    private func hfBandInfoRow(band: String, range: String, group: String) -> some View {
        let day = appState.propagationSnapshot.bands["\(group)_day"] ?? "-"
        let night = appState.propagationSnapshot.bands["\(group)_night"] ?? "-"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(band)
                    .font(.title2)
                    .bold()
                Text(range)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            Spacer(minLength: 0)

            conditionBadge(day, icon: "sun.max.fill")
                .frame(maxWidth: .infinity)

            conditionBadge(night, icon: "moon.fill")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    private func conditionBadge(_ condition: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(condition)
                .lineLimit(1)
        }
        .font(.system(.caption, design: .rounded))
        .bold()
        .foregroundColor(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 90)
        .background(conditionBadgeColor(condition))
        .cornerRadius(7)
    }

    private func metricRow(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "-" : value)
                .font(.system(.caption, design: .rounded))
                .bold()
                .foregroundColor(.black)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 86, alignment: .center)
                .background(color)
                .cornerRadius(7)
        }
    }

    private func vhfRow(name: String, location: String) -> some View {
        let value = appState.propagationSnapshot.vhfConditions["\(name)|\(location)"] ?? "-"

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .bold()
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(.caption, design: .rounded))
                .bold()
                .foregroundColor(.black)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 110, alignment: .center)
                .background(conditionBadgeColor(value))
                .cornerRadius(7)
        }
    }

    private func vhfConditionCard(name: String, location: String) -> some View {
        let value = appState.propagationSnapshot.vhfConditions["\(name)|\(location)"] ?? "-"

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.subheadline)
                    .bold()
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(.caption, design: .rounded))
                .bold()
                .foregroundColor(.black)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: 110, alignment: .center)
                .background(conditionBadgeColor(value).opacity(value == "-" ? 1 : 0.75))
                .cornerRadius(6)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.25))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.18), lineWidth: 1))
    }

    private var solarFluxColor: Color {
        guard let value = Int(appState.propagationSnapshot.solarFlux.filter(\.isNumber)) else {
            return .gray.opacity(0.45)
        }

        if value >= 120 { return .green }
        if value >= 80 { return .yellow }
        return .orange
    }

    private func geomagneticColor(_ value: String) -> Color {
        let lowercased = value.lowercased()
        if lowercased.contains("quiet") || lowercased.contains("low") {
            return .green
        }
        if lowercased.contains("active") || lowercased.contains("storm") {
            return .red
        }

        let numeric = Int(value.filter(\.isNumber)) ?? 0
        if numeric <= 2 { return .green }
        if numeric <= 4 { return .yellow }
        return .orange
    }

    private func conditionBadgeColor(_ condition: String) -> Color {
        let value = condition.lowercased()
        if value.contains("excellent") || value.contains("good") {
            return .green
        }
        if value.contains("fair") {
            return .yellow
        }
        if value.contains("poor") || value.contains("closed") || value.contains("storm") {
            return .red
        }
        if value == "-" {
            return .gray.opacity(0.35)
        }
        return .orange
    }

    private func conditionText(for band: String) -> String {
        let key = "\(conditionBandGroup(for: band))_\(isDaytimeBandWindow ? "day" : "night")"
        return appState.propagationSnapshot.bands[key] ?? "heuristic"
    }

    private func conditionBandGroup(for band: String) -> String {
        switch band.uppercased() {
        case "160M", "80M", "60M", "40M":
            return "80M-40M"
        case "30M", "20M":
            return "30M-20M"
        case "17M", "15M":
            return "17M-15M"
        case "12M", "10M":
            return "12M-10M"
        default:
            return band.uppercased()
        }
    }

    private func conditionColor(for band: String) -> Color {
        switch conditionText(for: band).lowercased() {
        case let value where value.contains("excellent"):
            return .green
        case let value where value.contains("good"):
            return .blue
        case let value where value.contains("fair"):
            return .orange
        case let value where value.contains("poor"):
            return .red
        default:
            return .accentColor
        }
    }

    private var isDaytimeBandWindow: Bool {
        (6..<18).contains(utcHour)
    }

    private func propagationScore(for band: String) -> Int {
        let condition = conditionText(for: band).lowercased()
        let liveScore: Int
        if condition.contains("excellent") {
            liveScore = 40
        } else if condition.contains("good") {
            liveScore = 30
        } else if condition.contains("fair") {
            liveScore = 15
        } else if condition.contains("poor") {
            liveScore = -20
        } else {
            liveScore = 0
        }

        let antennaPenalty = antennaDescription.isEmpty ? -3 : 0
        let lowPowerPenalty = radioPowerWatts < 25 ? -5 : 0
        return liveScore + antennaPenalty + lowPowerPenalty
    }

    private func pathScore(
        band: String,
        country: String,
        target: DXCoordinate,
        distanceKm: Double,
        needsConfirmationOnBand: Bool
    ) -> DXBandPathScore {
        let condition = conditionText(for: band)
        let conditionPoints = conditionScore(condition)
        let localHour = localSolarHour(for: target.longitude)
        let stationDaylight = isDaytimeBandWindow
        let targetDaylight = (6..<18).contains(localHour)
        let window = targetDaylight ? "day" : "night"
        let terminatorBonus = stationDaylight != targetDaylight ? 12 : 0
        let distancePoints = distanceScore(distanceKm: distanceKm, band: band)
        let timePoints = timeScore(band: band, stationDaylight: stationDaylight, targetDaylight: targetDaylight)
        let powerPoints = radioPowerWatts >= 100 ? 4 : (radioPowerWatts < 25 ? -8 : 0)
        let antennaPoints = antennaDescription.isEmpty ? -5 : min(8, antennaHeightMeters / 3)
        let confirmationPoints = needsConfirmationOnBand ? 14 : 0
        let rawScore = conditionPoints + distancePoints + timePoints + terminatorBonus + powerPoints + antennaPoints + confirmationPoints
        let score = min(98, max(5, rawScore))

        let reasonParts = [
            targetDaylight ? "target day" : "target night",
            "\(Int(distanceKm.rounded())) km",
            needsConfirmationOnBand ? "needs confirmation" : "worked path"
        ]

        return DXBandPathScore(
            band: band,
            score: score,
            condition: condition,
            window: window,
            reason: reasonParts.joined(separator: ", ")
        )
    }

    private func conditionScore(_ condition: String) -> Int {
        let value = condition.lowercased()
        if value.contains("excellent") { return 42 }
        if value.contains("good") { return 34 }
        if value.contains("fair") { return 22 }
        if value.contains("poor") { return 8 }
        return 18
    }

    private func distanceScore(distanceKm: Double, band: String) -> Int {
        switch band {
        case "160M", "80M":
            return distanceKm < 2500 ? 20 : (distanceKm < 6500 ? 10 : -8)
        case "40M", "30M":
            return distanceKm < 8000 ? 22 : 15
        case "20M", "17M":
            return distanceKm > 2500 ? 24 : 12
        case "15M", "12M", "10M":
            return distanceKm > 4000 ? 20 : 8
        default:
            return 10
        }
    }

    private func timeScore(band: String, stationDaylight: Bool, targetDaylight: Bool) -> Int {
        switch band {
        case "160M", "80M", "40M":
            return (!stationDaylight || !targetDaylight) ? 18 : 5
        case "30M", "20M":
            return 16
        case "17M", "15M", "12M", "10M":
            return (stationDaylight || targetDaylight) ? 17 : 4
        default:
            return 8
        }
    }

    private func localSolarHour(for longitude: Double) -> Int {
        let shifted = Double(utcHour) + longitude / 15.0
        let normalized = shifted.truncatingRemainder(dividingBy: 24)
        return Int(normalized < 0 ? normalized + 24 : normalized)
    }

    private func coordinate(fromMaidenhead locator: String) -> DXCoordinate? {
        let value = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count >= 4 else { return nil }

        let chars = Array(value)
        guard
            let lonField = chars[0].asciiValue,
            let latField = chars[1].asciiValue,
            let lonSquare = chars[2].wholeNumberValue,
            let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        var longitude = Double(lonField - Character("A").asciiValue!) * 20 - 180 + Double(lonSquare) * 2 + 1
        var latitude = Double(latField - Character("A").asciiValue!) * 10 - 90 + Double(latSquare) + 0.5

        if value.count >= 6,
           let lonSub = chars[4].asciiValue,
           let latSub = chars[5].asciiValue {
            longitude += Double(lonSub - Character("A").asciiValue!) * (5.0 / 60.0) + (2.5 / 60.0) - 1
            latitude += Double(latSub - Character("A").asciiValue!) * (2.5 / 60.0) + (1.25 / 60.0) - 0.5
        }

        return DXCoordinate(latitude: latitude, longitude: longitude)
    }

    private func coordinate(forCountry country: String) -> DXCoordinate? {
        Self.countryCoordinates[normalizedCountryName(country)]
    }

    private func normalizedCountryName(_ country: String) -> String {
        country.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "&", with: "and")
    }

    private func greatCircleDistanceKm(from origin: DXCoordinate, to target: DXCoordinate) -> Double {
        let earthRadiusKm = 6371.0
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let deltaLat = (target.latitude - origin.latitude) * .pi / 180
        let deltaLon = (target.longitude - origin.longitude) * .pi / 180
        let a = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func initialBearing(from origin: DXCoordinate, to target: DXCoordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let deltaLon = (target.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    private func bandSort(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M"]
        return (order.firstIndex(of: lhs) ?? Int.max) < (order.firstIndex(of: rhs) ?? Int.max)
    }

    private func refreshPathPredictions() {
        guard stationCoordinate != nil else {
            cachedPathPredictions = []
            isCalculatingPathPredictions = false
            return
        }

        isCalculatingPathPredictions = true
        DispatchQueue.main.async {
            cachedPathPredictions = makePathPredictions()
            isCalculatingPathPredictions = false
        }
    }

    private func syncBulkEmailSelection() {
        let available = Set(bulkEmailRecipients.map(\.callsign))
        if selectedBulkEmailCallsigns.isEmpty {
            selectedBulkEmailCallsigns = available
        } else {
            selectedBulkEmailCallsigns = selectedBulkEmailCallsigns.intersection(available)
        }
    }

    private func openEmailComposer(callsign: String, email: String) {
        let normalizedCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let unconfirmedQSOs = appState.qsoRecords.filter { record in
            record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCall &&
            !record.isConfirmed
        }

        let matchingQSO = unconfirmedQSOs.first ?? appState.qsoRecords.first { record in
            record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCall &&
            (email.isEmpty || record["EMAIL"] == email)
        } ?? appState.qsoRecords.first { record in
            record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCall
        }

        appState.selectedEmailCallsign = normalizedCall
        appState.selectedEmailAddress = email
        appState.selectedEmailQSO = matchingQSO
        appState.selectedEmailUnconfirmedQSOs = unconfirmedQSOs
        appState.showEmailComposer = true
    }

    private func fetchEmailAndOpenComposer(for item: UnconfirmedCallsignStatModel) {
        let normalizedCall = item.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCall.isEmpty, !fetchingEmailCallsigns.contains(normalizedCall) else { return }

        fetchingEmailCallsigns.insert(normalizedCall)
        Task {
            let email = await appState.fetchAndStoreQRZEmail(for: normalizedCall)
            await MainActor.run {
                fetchingEmailCallsigns.remove(normalizedCall)

                if let email, !email.isEmpty {
                    openEmailComposer(callsign: normalizedCall, email: email)
                } else {
                    appState.alertTitle = "QRZ Email Not Found"
                    appState.alertMessage = "No QRZ email address was found for \(normalizedCall). Make sure you are signed in to QRZ.com and the callsign has published an email address."
                    appState.showAlert = true
                }
            }
        }
    }

    private func sendBulkEmail() {
        let recipients = selectedBulkEmailRecipients
        guard !recipients.isEmpty else { return }

        let repeatedRecipients = recipients.compactMap { recipient -> String? in
            guard let history = appState.latestEmailHistory(for: recipient.callsign) else { return nil }
            return "\(recipient.callsign) - \(appState.formattedEmailHistoryDate(history.date)) - \(history.subject)"
        }

        if !repeatedRecipients.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some Recipients Were Already Emailed"
            alert.informativeText = """
            These callsigns already have email history:

            \(repeatedRecipients.prefix(12).joined(separator: "\n"))
            \(repeatedRecipients.count > 12 ? "\n...and \(repeatedRecipients.count - 12) more." : "")

            Do you still want to send this bulk email?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Send Anyway")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        isSendingBulkEmail = true
        bulkEmailStatus = "Sending \(recipients.count) selected confirmation emails..."

        appState.sendBulkConfirmationEmails(recipients: recipients, templateName: bulkEmailTemplate) { sent, failed in
            isSendingBulkEmail = false
            bulkEmailStatus = "Bulk email complete: \(sent) sent, \(failed) failed."
            appState.alertTitle = "Bulk Email Complete"
            appState.alertMessage = bulkEmailStatus
            appState.showAlert = true
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            .cornerRadius(8)
    }

    private static let countryCoordinates: [String: DXCoordinate] =
        [
            "afghanistan": DXCoordinate(latitude: 33.9, longitude: 67.7),
            "aland is": DXCoordinate(latitude: 60.2, longitude: 20.0),
            "alaska": DXCoordinate(latitude: 64.2, longitude: -149.5),
            "albania": DXCoordinate(latitude: 41.2, longitude: 20.2),
            "algeria": DXCoordinate(latitude: 28.0, longitude: 1.7),
            "american samoa": DXCoordinate(latitude: -14.3, longitude: -170.7),
            "andorra": DXCoordinate(latitude: 42.5, longitude: 1.6),
            "angola": DXCoordinate(latitude: -11.2, longitude: 17.9),
            "argentina": DXCoordinate(latitude: -38.4, longitude: -63.6),
            "armenia": DXCoordinate(latitude: 40.1, longitude: 45.0),
            "aruba": DXCoordinate(latitude: 12.5, longitude: -69.9),
            "asiatic russia": DXCoordinate(latitude: 60.0, longitude: 90.0),
            "australia": DXCoordinate(latitude: -25.3, longitude: 133.8),
            "austria": DXCoordinate(latitude: 47.5, longitude: 14.5),
            "azores": DXCoordinate(latitude: 37.7, longitude: -25.7),
            "bahamas": DXCoordinate(latitude: 25.0, longitude: -77.4),
            "bahrain": DXCoordinate(latitude: 26.0, longitude: 50.6),
            "balearic is": DXCoordinate(latitude: 39.6, longitude: 2.9),
            "bangladesh": DXCoordinate(latitude: 23.7, longitude: 90.4),
            "barbados": DXCoordinate(latitude: 13.2, longitude: -59.5),
            "belarus": DXCoordinate(latitude: 53.7, longitude: 27.9),
            "belgium": DXCoordinate(latitude: 50.5, longitude: 4.5),
            "belize": DXCoordinate(latitude: 17.2, longitude: -88.5),
            "benin": DXCoordinate(latitude: 9.3, longitude: 2.3),
            "bermuda": DXCoordinate(latitude: 32.3, longitude: -64.8),
            "bhutan": DXCoordinate(latitude: 27.5, longitude: 90.4),
            "bolivia": DXCoordinate(latitude: -16.3, longitude: -63.6),
            "bonaire": DXCoordinate(latitude: 12.2, longitude: -68.3),
            "bosnia-herzegovina": DXCoordinate(latitude: 44.0, longitude: 17.7),
            "botswana": DXCoordinate(latitude: -22.3, longitude: 24.7),
            "brazil": DXCoordinate(latitude: -14.2, longitude: -51.9),
            "british virgin is": DXCoordinate(latitude: 18.4, longitude: -64.6),
            "brunei": DXCoordinate(latitude: 4.5, longitude: 114.7),
            "bulgaria": DXCoordinate(latitude: 42.7, longitude: 25.5),
            "burkina faso": DXCoordinate(latitude: 12.2, longitude: -1.6),
            "burundi": DXCoordinate(latitude: -3.4, longitude: 29.9),
            "canada": DXCoordinate(latitude: 56.1, longitude: -106.3),
            "canary is": DXCoordinate(latitude: 28.3, longitude: -16.6),
            "cape verde": DXCoordinate(latitude: 16.0, longitude: -24.0),
            "cayman is": DXCoordinate(latitude: 19.3, longitude: -81.2),
            "central african republic": DXCoordinate(latitude: 6.6, longitude: 20.9),
            "central kiribati": DXCoordinate(latitude: 0.5, longitude: -157.4),
            "chad": DXCoordinate(latitude: 15.5, longitude: 18.7),
            "chile": DXCoordinate(latitude: -35.7, longitude: -71.5),
            "china": DXCoordinate(latitude: 35.9, longitude: 104.2),
            "colombia": DXCoordinate(latitude: 4.6, longitude: -74.1),
            "congo": DXCoordinate(latitude: -0.2, longitude: 15.8),
            "corsica": DXCoordinate(latitude: 42.0, longitude: 9.0),
            "costa rica": DXCoordinate(latitude: 9.7, longitude: -84.2),
            "crete": DXCoordinate(latitude: 35.2, longitude: 24.9),
            "croatia": DXCoordinate(latitude: 45.1, longitude: 15.2),
            "cuba": DXCoordinate(latitude: 21.5, longitude: -79.4),
            "curacao": DXCoordinate(latitude: 12.2, longitude: -69.0),
            "cyprus": DXCoordinate(latitude: 35.1, longitude: 33.4),
            "czech republic": DXCoordinate(latitude: 49.8, longitude: 15.5),
            "denmark": DXCoordinate(latitude: 56.3, longitude: 9.5),
            "djibouti": DXCoordinate(latitude: 11.8, longitude: 42.6),
            "dodecanese": DXCoordinate(latitude: 36.2, longitude: 28.0),
            "dominican republic": DXCoordinate(latitude: 18.7, longitude: -70.2),
            "ecuador": DXCoordinate(latitude: -1.8, longitude: -78.2),
            "egypt": DXCoordinate(latitude: 26.8, longitude: 30.8),
            "england": DXCoordinate(latitude: 52.4, longitude: -1.2),
            "estonia": DXCoordinate(latitude: 58.6, longitude: 25.0),
            "ethiopia": DXCoordinate(latitude: 9.1, longitude: 40.5),
            "european russia": DXCoordinate(latitude: 56.0, longitude: 38.0),
            "falkland is": DXCoordinate(latitude: -51.8, longitude: -59.5),
            "faroe is": DXCoordinate(latitude: 62.0, longitude: -6.8),
            "fiji": DXCoordinate(latitude: -17.7, longitude: 178.1),
            "finland": DXCoordinate(latitude: 61.9, longitude: 25.7),
            "france": DXCoordinate(latitude: 46.2, longitude: 2.2),
            "french guiana": DXCoordinate(latitude: 4.0, longitude: -53.1),
            "gabon": DXCoordinate(latitude: -0.8, longitude: 11.6),
            "galapagos": DXCoordinate(latitude: -0.8, longitude: -90.9),
            "georgia": DXCoordinate(latitude: 42.3, longitude: 43.4),
            "germany": DXCoordinate(latitude: 51.2, longitude: 10.5),
            "ghana": DXCoordinate(latitude: 7.9, longitude: -1.0),
            "gibraltar": DXCoordinate(latitude: 36.1, longitude: -5.4),
            "greece": DXCoordinate(latitude: 39.1, longitude: 21.8),
            "greenland": DXCoordinate(latitude: 71.7, longitude: -42.6),
            "guadeloupe": DXCoordinate(latitude: 16.3, longitude: -61.6),
            "guam": DXCoordinate(latitude: 13.4, longitude: 144.8),
            "guatemala": DXCoordinate(latitude: 15.8, longitude: -90.2),
            "guernsey": DXCoordinate(latitude: 49.5, longitude: -2.6),
            "guyana": DXCoordinate(latitude: 5.0, longitude: -58.9),
            "haiti": DXCoordinate(latitude: 18.9, longitude: -72.3),
            "hawaii": DXCoordinate(latitude: 20.8, longitude: -156.3),
            "honduras": DXCoordinate(latitude: 15.2, longitude: -86.2),
            "hong kong": DXCoordinate(latitude: 22.3, longitude: 114.2),
            "hungary": DXCoordinate(latitude: 47.2, longitude: 19.5),
            "iceland": DXCoordinate(latitude: 64.9, longitude: -19.0),
            "india": DXCoordinate(latitude: 20.6, longitude: 78.9),
            "indonesia": DXCoordinate(latitude: -0.8, longitude: 113.9),
            "iran": DXCoordinate(latitude: 32.4, longitude: 53.7),
            "iraq": DXCoordinate(latitude: 33.2, longitude: 43.7),
            "ireland": DXCoordinate(latitude: 53.4, longitude: -8.2),
            "isle of man": DXCoordinate(latitude: 54.2, longitude: -4.5),
            "israel": DXCoordinate(latitude: 31.0, longitude: 35.0),
            "italy": DXCoordinate(latitude: 42.8, longitude: 12.5),
            "ivory coast": DXCoordinate(latitude: 7.5, longitude: -5.5),
            "jamaica": DXCoordinate(latitude: 18.1, longitude: -77.3),
            "jan mayen": DXCoordinate(latitude: 71.0, longitude: -8.3),
            "japan": DXCoordinate(latitude: 36.2, longitude: 138.3),
            "jersey": DXCoordinate(latitude: 49.2, longitude: -2.1),
            "jordan": DXCoordinate(latitude: 31.2, longitude: 36.2),
            "kazakhstan": DXCoordinate(latitude: 48.0, longitude: 67.0),
            "kenya": DXCoordinate(latitude: -0.0, longitude: 37.9),
            "kosovo": DXCoordinate(latitude: 42.6, longitude: 20.9),
            "kuwait": DXCoordinate(latitude: 29.3, longitude: 47.5),
            "kyrgyzstan": DXCoordinate(latitude: 41.2, longitude: 74.8),
            "latvia": DXCoordinate(latitude: 56.9, longitude: 24.6),
            "lebanon": DXCoordinate(latitude: 33.9, longitude: 35.9),
            "libya": DXCoordinate(latitude: 26.3, longitude: 17.2),
            "liechtenstein": DXCoordinate(latitude: 47.2, longitude: 9.6),
            "lithuania": DXCoordinate(latitude: 55.2, longitude: 23.9),
            "luxembourg": DXCoordinate(latitude: 49.8, longitude: 6.1),
            "macau": DXCoordinate(latitude: 22.2, longitude: 113.5),
            "madagascar": DXCoordinate(latitude: -18.8, longitude: 46.9),
            "madeira is": DXCoordinate(latitude: 32.8, longitude: -16.9),
            "malawi": DXCoordinate(latitude: -13.3, longitude: 34.3),
            "malaysia": DXCoordinate(latitude: 4.2, longitude: 102.0),
            "maldives": DXCoordinate(latitude: 3.2, longitude: 73.2),
            "malta": DXCoordinate(latitude: 35.9, longitude: 14.4),
            "martinique": DXCoordinate(latitude: 14.6, longitude: -61.0),
            "mauritius": DXCoordinate(latitude: -20.3, longitude: 57.6),
            "mayotte": DXCoordinate(latitude: -12.8, longitude: 45.2),
            "mexico": DXCoordinate(latitude: 23.6, longitude: -102.6),
            "moldova": DXCoordinate(latitude: 47.4, longitude: 28.4),
            "monaco": DXCoordinate(latitude: 43.7, longitude: 7.4),
            "mongolia": DXCoordinate(latitude: 46.9, longitude: 103.8),
            "montenegro": DXCoordinate(latitude: 42.7, longitude: 19.4),
            "montserrat": DXCoordinate(latitude: 16.7, longitude: -62.2),
            "morocco": DXCoordinate(latitude: 31.8, longitude: -7.1),
            "mozambique": DXCoordinate(latitude: -18.7, longitude: 35.5),
            "namibia": DXCoordinate(latitude: -22.6, longitude: 17.1),
            "nepal": DXCoordinate(latitude: 28.4, longitude: 84.1),
            "netherlands": DXCoordinate(latitude: 52.1, longitude: 5.3),
            "new caledonia": DXCoordinate(latitude: -20.9, longitude: 165.6),
            "new zealand": DXCoordinate(latitude: -40.9, longitude: 174.9),
            "nicaragua": DXCoordinate(latitude: 12.9, longitude: -85.2),
            "nigeria": DXCoordinate(latitude: 9.1, longitude: 8.7),
            "northern ireland": DXCoordinate(latitude: 54.8, longitude: -6.5),
            "northern mariana is": DXCoordinate(latitude: 15.1, longitude: 145.7),
            "norway": DXCoordinate(latitude: 60.5, longitude: 8.5),
            "oman": DXCoordinate(latitude: 21.5, longitude: 55.9),
            "pakistan": DXCoordinate(latitude: 30.4, longitude: 69.3),
            "palestine": DXCoordinate(latitude: 31.9, longitude: 35.2),
            "panama": DXCoordinate(latitude: 8.5, longitude: -80.8),
            "papua new guinea": DXCoordinate(latitude: -6.3, longitude: 143.9),
            "paraguay": DXCoordinate(latitude: -23.4, longitude: -58.4),
            "peru": DXCoordinate(latitude: -9.2, longitude: -75.0),
            "philippines": DXCoordinate(latitude: 12.9, longitude: 121.8),
            "poland": DXCoordinate(latitude: 51.9, longitude: 19.1),
            "portugal": DXCoordinate(latitude: 39.4, longitude: -8.2),
            "puerto rico": DXCoordinate(latitude: 18.2, longitude: -66.6),
            "qatar": DXCoordinate(latitude: 25.4, longitude: 51.2),
            "reunion": DXCoordinate(latitude: -21.1, longitude: 55.5),
            "romania": DXCoordinate(latitude: 45.9, longitude: 24.9),
            "rodrigues": DXCoordinate(latitude: -19.7, longitude: 63.4),
            "saint helena": DXCoordinate(latitude: -15.9, longitude: -5.7),
            "san marino": DXCoordinate(latitude: 43.9, longitude: 12.5),
            "sardinia": DXCoordinate(latitude: 40.1, longitude: 9.0),
            "saudi arabia": DXCoordinate(latitude: 24.0, longitude: 45.0),
            "scotland": DXCoordinate(latitude: 56.5, longitude: -4.2),
            "senegal": DXCoordinate(latitude: 14.5, longitude: -14.5),
            "serbia": DXCoordinate(latitude: 44.0, longitude: 20.8),
            "seychelles": DXCoordinate(latitude: -4.7, longitude: 55.5),
            "singapore": DXCoordinate(latitude: 1.4, longitude: 103.8),
            "slovak republic": DXCoordinate(latitude: 48.7, longitude: 19.7),
            "slovenia": DXCoordinate(latitude: 46.1, longitude: 14.9),
            "south africa": DXCoordinate(latitude: -30.6, longitude: 22.9),
            "south korea": DXCoordinate(latitude: 36.5, longitude: 127.8),
            "spain": DXCoordinate(latitude: 40.5, longitude: -3.7),
            "sri lanka": DXCoordinate(latitude: 7.9, longitude: 80.8),
            "svalbard": DXCoordinate(latitude: 78.2, longitude: 16.0),
            "sweden": DXCoordinate(latitude: 60.1, longitude: 18.6),
            "switzerland": DXCoordinate(latitude: 46.8, longitude: 8.2),
            "syria": DXCoordinate(latitude: 34.8, longitude: 38.9),
            "taiwan": DXCoordinate(latitude: 23.7, longitude: 121.0),
            "tajikistan": DXCoordinate(latitude: 38.9, longitude: 71.0),
            "tanzania": DXCoordinate(latitude: -6.4, longitude: 34.9),
            "thailand": DXCoordinate(latitude: 15.9, longitude: 100.9),
            "trinidad and tobago": DXCoordinate(latitude: 10.7, longitude: -61.2),
            "tunisia": DXCoordinate(latitude: 33.9, longitude: 9.5),
            "turkey": DXCoordinate(latitude: 39.0, longitude: 35.2),
            "turkmenistan": DXCoordinate(latitude: 38.9, longitude: 59.6),
            "ukraine": DXCoordinate(latitude: 48.4, longitude: 31.2),
            "united arab emirates": DXCoordinate(latitude: 24.4, longitude: 54.4),
            "united states": DXCoordinate(latitude: 39.8, longitude: -98.6),
            "usa": DXCoordinate(latitude: 39.8, longitude: -98.6),
            "uruguay": DXCoordinate(latitude: -32.5, longitude: -55.8),
            "us virgin is": DXCoordinate(latitude: 18.3, longitude: -64.9),
            "uzbekistan": DXCoordinate(latitude: 41.4, longitude: 64.6),
            "venezuela": DXCoordinate(latitude: 6.4, longitude: -66.6),
            "viet nam": DXCoordinate(latitude: 14.1, longitude: 108.3),
            "wales": DXCoordinate(latitude: 52.1, longitude: -3.8),
            "western sahara": DXCoordinate(latitude: 24.2, longitude: -12.9),
            "zambia": DXCoordinate(latitude: -13.1, longitude: 27.8),
            "zimbabwe": DXCoordinate(latitude: -19.0, longitude: 29.2)
        ]
}

private struct SolarFluxForecastChart: View {
    let points: [SolarForecastPoint]

    private var solarRange: ClosedRange<Int> {
        let values = points.map(\.solarFlux)
        let minValue = max(0, (values.min() ?? 70) - 5)
        let maxValue = (values.max() ?? 130) + 5
        return minValue...max(maxValue, minValue + 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                legend(color: .red, title: "Predicted Solar Flux")
                legend(color: .blue, title: "Kp-Index Predicted")
                Spacer()
                Text("NOAA SWPC 27-day outlook")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                let plotWidth = max(1, geometry.size.width - 56)
                let plotHeight = max(1, geometry.size.height - 34)
                let origin = CGPoint(x: 36, y: plotHeight)
                let step = points.count > 1 ? plotWidth / CGFloat(points.count - 1) : plotWidth
                let solarMin = CGFloat(solarRange.lowerBound)
                let solarSpan = CGFloat(max(1, solarRange.upperBound - solarRange.lowerBound))

                let solarCoordinates = points.enumerated().map { index, point in
                    CGPoint(
                        x: origin.x + CGFloat(index) * step,
                        y: plotHeight - ((CGFloat(point.solarFlux) - solarMin) / solarSpan) * (plotHeight - 12)
                    )
                }
                let kpCoordinates = points.enumerated().map { index, point in
                    CGPoint(
                        x: origin.x + CGFloat(index) * step,
                        y: plotHeight - (CGFloat(point.kpIndex) / 9.0) * (plotHeight - 12)
                    )
                }

                ZStack(alignment: .topLeading) {
                    grid(width: geometry.size.width, height: plotHeight, origin: origin)

                    linePath(solarCoordinates)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    linePath(kpCoordinates)
                        .stroke(Color.blue.opacity(0.75), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                            .position(solarCoordinates[index])
                            .help("\(point.dateLabel): SFI \(point.solarFlux), Kp \(point.kpIndex)")

                        Circle()
                            .fill(Color.blue.opacity(0.75))
                            .frame(width: 5, height: 5)
                            .position(kpCoordinates[index])
                    }

                    Text("\(solarRange.upperBound)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: 14, y: 8)
                    Text("\(solarRange.lowerBound)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: 14, y: plotHeight - 2)
                    Text("Kp 9")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: geometry.size.width - 18, y: 8)

                    if let first = points.first {
                        Text(first.dateLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .position(x: origin.x + 12, y: geometry.size.height - 8)
                    }
                    if let last = points.last {
                        Text(last.dateLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .position(x: geometry.size.width - 28, y: geometry.size.height - 8)
                    }
                }
            }
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(color)
                .frame(width: 24, height: 5)
            Text(title)
                .font(.caption)
        }
    }

    private func grid(width: CGFloat, height: CGFloat, origin: CGPoint) -> some View {
        Path { path in
            path.move(to: CGPoint(x: origin.x, y: 0))
            path.addLine(to: origin)
            path.addLine(to: CGPoint(x: width, y: origin.y))

            for row in 0...4 {
                let y = CGFloat(row) * height / 4
                path.move(to: CGPoint(x: origin.x, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
    }

    private func linePath(_ coordinates: [CGPoint]) -> Path {
        Path { path in
            guard let first = coordinates.first else { return }
            path.move(to: first)
            for point in coordinates.dropFirst() {
                path.addLine(to: point)
            }
        }
    }
}
