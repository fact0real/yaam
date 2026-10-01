//
//  CallIntelligencePanelView.swift
//  YAAM
//
//  High-Density Real-Time Call Intelligence & Tactical Station Operations Panel.
//  Provides instant visual feedback on ATNO, DXCC needs, Band/Mode matrices,
//  LoTW confirmation probability, solar illumination, antenna steering, and spots.
//

import SwiftUI

struct CallIntelligencePanelView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var intelligenceEngine = CallIntelligenceEngine.shared
    @ObservedObject private var rotator = RotatorService.shared

    @State private var selectedTab: IntelligenceTab = .tactical
    @State private var isRotatorTriggered: Bool = false
    @State private var isShowingVisualQSLInspector: Bool = false

    enum IntelligenceTab: String, CaseIterable, Identifiable {
        case tactical = "Tactical"
        case matrix = "Matrix"
        case history = "History"
        case spots = "Spots"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .tactical: return "antenna.radiowaves.left.and.right"
            case .matrix: return "square.grid.3x3.fill"
            case .history: return "clock.arrow.circlepath"
            case .spots: return "dot.radiowaves.up.forward"
            }
        }
    }

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            if let report = intelligenceEngine.activeReport {
                activeCallsignIntelligenceView(report: report)
            } else {
                defaultStationDashboardView
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .sheet(isPresented: $isShowingVisualQSLInspector) {
            if let report = intelligenceEngine.activeReport {
                VisualQSLInspectorSheet(report: report)
            }
        }
    }

    // MARK: - Active Callsign Intelligence View

    private func activeCallsignIntelligenceView(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Callsign Header & Badges
            headerIdentityCard(report: report)

            // 2. Award Impact Badges Flow
            if !report.badges.isEmpty {
                awardBadgesStrip(badges: report.badges)
            }

            // 3. Quick Action Row (Rotator, Web, Tune)
            quickActionsToolbar(report: report)

            // 4. Segmented Control
            Picker("View Mode", selection: $selectedTab) {
                ForEach(IntelligenceTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.top, 2)

            // 5. Selected Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch selectedTab {
                    case .tactical:
                        tacticalView(report: report)
                    case .matrix:
                        bandMatrixView(report: report)
                    case .history:
                        historyView(report: report)
                    case .spots:
                        spotsView(report: report)
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 4)

            // 6. Last Logged QSO Footer (if exists)
            if let saved = appState.quickLogLastSaved {
                lastLoggedFooter(saved: saved)
            }
        }
        .padding(14)
    }

    // MARK: - Header Identity Card

    private func headerIdentityCard(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                if let img = report.imageURL, !img.isEmpty {
                    VisualQSLThumbnailView(urlString: img, callsign: report.callsign, size: 44) {
                        isShowingVisualQSLInspector = true
                    }
                } else {
                    Text(report.dxcc.flagEmoji)
                        .font(.system(size: 32))
                        .shadow(radius: 1)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(report.callsign)
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundStyle(.primary)

                        if let scp = report.scpMatch, scp.isExact {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                                .help("Verified in Master.scp database")
                        }

                        if let lic = report.licenseClass {
                            Text(lic.uppercased())
                                .font(.system(size: 8.5, weight: .heavy))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.purple.opacity(0.18), in: Capsule())
                                .foregroundStyle(.purple)
                                .help("License Class: \(lic)")
                        }
                    }

                    if !report.operatorName.isEmpty {
                        Text(report.operatorName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        if report.imageURL != nil {
                            Text(report.dxcc.flagEmoji)
                        }
                        Text("\(report.dxcc.entityName) · \(report.continent) · CQ \(report.cqZone) · ITU \(report.ituZone)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Target Solar & Illumination Badge
                if let solar = report.targetIllumination {
                    solarStatusPill(solar: solar)
                }
            }

            // Location details: QTH & Grid & Geographic / Award Enrichment
            HStack(spacing: 6) {
                if !report.qth.isEmpty {
                    Label(report.qth, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !report.grid.isEmpty {
                    Text(report.grid)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.blue)
                }

                if let state = report.usState {
                    Text(state)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 4.5).padding(.vertical, 1.5)
                        .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.cyan)
                        .help("US State: \(state)")
                }

                if let county = report.usCounty {
                    Text("\(county) Co.")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 4.5).padding(.vertical, 1.5)
                        .background(Color.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.teal)
                        .help("US County: \(county)")
                }

                if let iota = report.iotaReference {
                    Text("🏝️ \(iota)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5).padding(.vertical, 1.5)
                        .background(Color.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.mint)
                        .help("Islands On The Air (IOTA): \(iota)")
                }

                if report.profileViews > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.fill").font(.system(size: 8))
                        Text("\(report.profileViews.formatted())")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.orange)
                    .help("\(report.profileViews.formatted()) QRZ Profile Views")
                }
            }

            // Club memberships
            if !report.clubMemberships.isEmpty {
                HStack(spacing: 5) {
                    ForEach(report.clubMemberships) { club in
                        HStack(spacing: 3) {
                            Image(systemName: club.club.icon)
                                .font(.system(size: 8.5))
                            Text("\(club.club.rawValue) #\(club.memberNumber)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(club.club.badgeColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(club.club.badgeColor)
                        .help("\(club.club.fullName) Member #\(club.memberNumber)")
                    }
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
    }

    private func solarStatusPill(solar: SolarEphemeris.IlluminationState) -> some View {
        let tint: Color
        let icon: String
        switch solar {
        case .daylight:
            tint = .yellow
            icon = "sun.max.fill"
        case .greylineCivil:
            tint = .orange
            icon = "sunset.fill"
        case .greylineNautical:
            tint = .indigo
            icon = "moon.fill"
        case .night:
            tint = .purple
            icon = "moon.stars.fill"
        }

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(solar.rawValue)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.18), in: Capsule())
        .foregroundStyle(tint)
    }

    private func channelDeliveryTag(title: String, active: Bool, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: active ? icon : "xmark.circle")
                .font(.system(size: 8.5))
            Text(title)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(active ? color.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(active ? color : .secondary)
    }

    // MARK: - Award Badges Strip

    private func awardBadgesStrip(badges: [AwardNeedBadge]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges) { badge in
                    HStack(spacing: 4) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(badge.title)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(badge.badgeColor.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(badge.badgeColor.opacity(0.45), lineWidth: 1))
                    .foregroundStyle(badge.badgeColor)
                    .help(badge.detail)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Quick Action Bar

    private func quickActionsToolbar(report: CallIntelligenceReport) -> some View {
        HStack(spacing: 6) {
            // Rotator Button
            if let sp = report.shortPathBearingDeg {
                Button {
                    rotator.turnTo(azimuth: sp)
                    isRotatorTriggered = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isRotatorTriggered = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.line.fill")
                            .rotationEffect(.degrees(sp))
                            .font(.system(size: 10, weight: .bold))
                        Text("Turn \(Int(sp.rounded()))° SP")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(isRotatorTriggered ? 0.35 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Command rotator to turn to Short Path bearing (\(Int(sp.rounded()))° \(report.cardinalDirection))")
            }

            // QRZ Button
            Button {
                if let url = URL(string: "https://www.qrz.com/db/\(report.callsign)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 9.5))
                    Text("QRZ")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Open \(report.callsign) profile on QRZ.com")

            // HamQTH Button
            Button {
                if let url = URL(string: "https://www.hamqth.com/\(report.callsign)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9.5))
                    Text("HamQTH")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Open \(report.callsign) profile on HamQTH.com")

            // Live Digital Track (HamTracker) Button
            Button {
                appState.openHamTracker(callsign: report.callsign)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 9.5))
                    Text("HamTracker")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .help("Monitor \(report.callsign)'s live digital transmissions (FT8/FT4) via PSKReporter MQTT & Cluster")

            // QSL Photo & Route Inspector Button
            if report.imageURL != nil || report.qslManager != nil || (report.lookupData?.address1.isEmpty == false) {
                Button {
                    isShowingVisualQSLInspector = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 9.5))
                        Text(report.imageURL != nil ? "QSL Photo" : "QSL Route")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Inspect \(report.callsign)'s QSL card, shack photo & routing intelligence")
            }

            Spacer()

            // Tune rig button if recent spot available
            if let spot = report.liveClusterSpots.first {
                Button {
                    let hz = UInt64(spot.frequencyKHz * 1000.0)
                    appState.rigControlClient.setFrequencyHz(hz)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "radio")
                            .font(.system(size: 9.5))
                        Text("QSY \(String(format: "%.3f", spot.frequencyKHz / 1000.0))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Tune connected transceiver to spotted frequency \(String(format: "%.3f", spot.frequencyKHz / 1000.0)) MHz")
            } else if let arch = report.recentArchivedSpots.first {
                Button {
                    let hz = UInt64(arch.frequencyKHz * 1000.0)
                    appState.rigControlClient.setFrequencyHz(hz)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "radio")
                            .font(.system(size: 9.5))
                        Text("QSY \(String(format: "%.3f", arch.frequencyKHz / 1000.0))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Tune connected transceiver to spotted frequency \(String(format: "%.3f", arch.frequencyKHz / 1000.0)) MHz")
            }
        }
    }

    // MARK: - Tab 1: Tactical View

    private func tacticalView(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Greyline Alert Banner (if applicable)
            if report.isGreylineOpportunity {
                HStack(spacing: 6) {
                    Image(systemName: "sunset.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GREYLINE PROPAGATION WINDOW")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundStyle(.orange)
                        Text("Either target or station is in twilight. Enhanced low-band DX path open!")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }

            // Propagation & Direction Card
            VStack(alignment: .leading, spacing: 6) {
                Text("PROPAGATION & TELEMETRY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                if let sp = report.shortPathBearingDeg, let dist = report.distanceKm {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("BEARING (SP / LP)")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("\(Int(sp.rounded()))° \(report.cardinalDirection) / \(Int((report.longPathBearingDeg ?? 0).rounded()))°")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("DISTANCE")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("\(Int(dist.rounded())) km (\(Int((report.distanceMiles ?? 0).rounded())) mi)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                } else {
                    Text("Target coordinates unavailable. Enter Maidenhead grid for exact beam heading.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let sr = report.sunriseUTC, let ss = report.sunsetUTC {
                    Divider().opacity(0.4)
                    HStack {
                        Label("SR: \(sr) UTC", systemImage: "sunrise.fill")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("SS: \(ss) UTC", systemImage: "sunset.fill")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Live HF Propagation & MUF Radar Card
            propagationRadarCard(report: report)

            // Pileup Sniper & Split QSX Radar Card
            pileupSniperRadarCard(report: report)

            // QSL & LoTW Intelligence Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QSL & LOTW INTELLIGENCE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: report.qslLikelihood.icon)
                            .font(.system(size: 9.5))
                        Text(report.qslLikelihood.rawValue)
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(report.qslLikelihood.color)
                }

                // Explicit QSL Manager Banner (if available)
                if let mgr = report.qslManager {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("QSL MANAGER / ROUTE:")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(mgr)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        Button {
                            isShowingVisualQSLInspector = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 8.5))
                                Text("Mailing Info")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.18), in: Capsule())
                            .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
                }

                HStack(spacing: 8) {
                    Image(systemName: report.isLoTWUser ? "checkmark.seal.fill" : "xmark.seal")
                        .font(.system(size: 16))
                        .foregroundStyle(report.isLoTWUser ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(report.lotwSummaryText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.primary)

                        Text("Recommended Route: \(report.recommendedQSLRoute)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }

                // Delivery Channel Badges
                HStack(spacing: 6) {
                    channelDeliveryTag(
                        title: "LoTW",
                        active: report.isLoTWUser || report.lookupData?.qslViaLotw == true,
                        color: .green,
                        icon: "checkmark.seal.fill"
                    )
                    channelDeliveryTag(
                        title: "eQSL",
                        active: report.lookupData?.qslViaEqsl == true,
                        color: .blue,
                        icon: "envelope.fill"
                    )
                    channelDeliveryTag(
                        title: "Direct / Bureau",
                        active: report.lookupData?.qslViaMail == true || report.qslManager != nil,
                        color: .orange,
                        icon: "paperplane.fill"
                    )

                    Spacer()

                    if report.imageURL != nil {
                        Button {
                            isShowingVisualQSLInspector = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 8.5))
                                Text("QSL Card")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let rate = report.historicalConfirmationRate {
                    Divider().opacity(0.4)
                    HStack {
                        Text("Log Confirmation Rate:")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(rate * 100))%")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(rate >= 0.5 ? .green : .orange)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Live HF Propagation & MUF Radar Card

    @ViewBuilder
    private func propagationRadarCard(report: CallIntelligenceReport) -> some View {
        if let prop = report.propagationPrediction {
            VStack(alignment: .leading, spacing: 7) {
                // Header Row with Status Badge
                HStack {
                    Label("LIVE PROPAGATION & MUF RADAR", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Condition Badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(prop.condition.color)
                            .frame(width: 6, height: 6)
                        Text("\(prop.reliabilityPercent)% \(prop.condition.rawValue.uppercased())")
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        Text(String(format: "(%+.0f dB)", prop.snrDB))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(prop.condition.color.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(prop.condition.color.opacity(0.3), lineWidth: 1))
                }

                // Frequencies Metric Grid (MUF / FOT / LUF / Best Band)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PATH MUF")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MHz", prop.pathMUF))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 1) {
                        Text("FOT (85%)")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MHz", prop.optimalFOT))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.cyan)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("PATH LUF")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MHz", prop.pathLUF))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("BEST BAND")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(prop.bestBandNow.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 2)

                // Tactical Advice
                HStack(spacing: 5) {
                    Image(systemName: prop.condition == .open ? "bolt.fill" : "info.circle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(prop.condition.color)
                    Text(prop.advice)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // 24-Hour Timeline Bar Sparkline
                VStack(alignment: .leading, spacing: 3) {
                    let currentUTCHour: Int = {
                        var cal = Calendar(identifier: .gregorian)
                        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
                        return cal.component(.hour, from: Date())
                    }()

                    HStack {
                        Text("24H FORECAST TIMELINE (\(prop.band.uppercased()))")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Now: \(String(format: "%02d:00z", currentUTCHour))")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 2) {
                        ForEach(prop.hourlyTimeline) { cell in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(cell.condition.color)
                                    .frame(height: max(4, CGFloat(cell.reliabilityPercent) * 0.16))
                            }
                            .frame(maxWidth: .infinity, maxHeight: 16)
                            .overlay(
                                cell.hourUTC == currentUTCHour
                                    ? RoundedRectangle(cornerRadius: 1.5).stroke(Color.white, lineWidth: 1)
                                    : nil
                            )
                            .help(String(format: "%02dz: %d%% (%@, SNR: %+.0f dB)", cell.hourUTC, cell.reliabilityPercent, cell.condition.rawValue, cell.snrDB))
                        }
                    }

                    // Timeline Axis Labels
                    HStack {
                        Text("00z")
                        Spacer()
                        Text("06z")
                        Spacer()
                        Text("12z")
                        Spacer()
                        Text("18z")
                        Spacer()
                        Text("23z")
                    }
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Pileup Sniper & Split QSX Radar Card

    @ViewBuilder
    private func pileupSniperRadarCard(report: CallIntelligenceReport) -> some View {
        if let sniper = report.pileupSniper, sniper.isSplit {
            VStack(alignment: .leading, spacing: 8) {
                // Header Row with glowing Scope Badge
                HStack(alignment: .center) {
                    Label("PILEUP SNIPER & SPLIT RADAR", systemImage: "scope")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.yellow)

                    Spacer()

                    // Pattern & Confidence Badge
                    HStack(spacing: 4) {
                        Image(systemName: sniper.pattern.iconName)
                            .font(.system(size: 8.5))
                        Text("\(sniper.pattern.rawValue.uppercased())")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        Text(String(format: "(%.0f%%)", sniper.confidence * 100))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(sniper.pattern.badgeColor.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(sniper.pattern.badgeColor.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(sniper.pattern.badgeColor)
                }

                // Dual VFO Alignment Grid (RX Base vs Sniper Target)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VFO-A (DX RX)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.3f MHz", sniper.dxRxFrequencyKHz / 1000.0))
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.6))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("TARGET VFO-B (TX)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(sniper.offsetSignFormatted)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                        }
                        Text(sniper.frequencyFormattedMHz)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.yellow)
                    }

                    Spacer()

                    // Quick Arm Button
                    Button {
                        BandmapEngine.shared.applySniperSolution(sniper)
                        let hz = UInt64(sniper.recommendedTxKHz * 1000.0)
                        appState.rigControlClient.setFrequencyHz(hz)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                            Text("ARM VFO-B")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.black)
                        .shadow(color: Color.yellow.opacity(0.4), radius: 3)
                    }
                    .buttonStyle(.plain)
                    .help("Arm VFO-B to Sniper Target (\(sniper.frequencyFormattedMHz)) and activate Split Mode")
                }

                // Interactive Split Spread Track & Hit Distribution
                if let spread = sniper.splitSpreadOffsetKHz {
                    VStack(alignment: .leading, spacing: 4) {
                        let minOff = spread.lowerBound
                        let maxOff = spread.upperBound
                        let span = max(1.0, maxOff - minOff)

                        GeometryReader { geo in
                            let width = geo.size.width

                            ZStack(alignment: .leading) {
                                // Background listening track
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 12)

                                // Active listening spread glow
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.yellow.opacity(0.12))
                                    .frame(height: 12)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.yellow.opacity(0.3), lineWidth: 0.8))

                                // Recent hit points (dots)
                                ForEach(sniper.recentHits) { hit in
                                    let xFraction = (hit.offsetKHz - minOff) / span
                                    let clampedX = max(0.0, min(1.0, xFraction))
                                    let xPos = clampedX * (width - 12) + 6

                                    Circle()
                                        .fill(Color.orange.opacity(hit.weight))
                                        .frame(width: 5, height: 5)
                                        .offset(x: xPos - 2.5)
                                        .help(String(format: "WKD: %.1f kHz by %@ (%@)", hit.frequencyKHz, hit.spotter, hit.comment))
                                }

                                // Sniper Recommended Target Reticle (Diamond / Bullseye)
                                let targetFraction = (sniper.recommendedOffsetKHz - minOff) / span
                                let targetX = max(0.0, min(1.0, targetFraction)) * (width - 16) + 8

                                ZStack {
                                    Circle()
                                        .fill(Color.yellow)
                                        .frame(width: 9, height: 9)
                                    Circle()
                                        .stroke(Color.black, lineWidth: 1.5)
                                        .frame(width: 9, height: 9)
                                }
                                .shadow(color: Color.yellow, radius: 4)
                                .offset(x: targetX - 4.5)
                            }
                        }
                        .frame(height: 14)

                        // Spread Axis Labels
                        HStack {
                            Text(String(format: "%@%.0f kHz", minOff >= 0 ? "+" : "", minOff))
                            Spacer()
                            Text("TARGET: \(sniper.offsetSignFormatted)")
                                .foregroundStyle(Color.yellow)
                            Spacer()
                            Text(String(format: "%@%.0f kHz", maxOff >= 0 ? "+" : "", maxOff))
                        }
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }

                // Tactical Strategy Advice
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.yellow)
                        .padding(.top, 1)

                    Text(sniper.tacticalAdvice)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Tab 2: Band Matrix View

    private func bandMatrixView(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BAND & MODE MATRIX")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("🟩 Confirmed · 🟧 Worked · 🟦 Draft")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                // Table Header
                HStack(spacing: 4) {
                    Text("BAND")
                        .frame(width: 45, alignment: .leading)
                    Spacer()
                    Text("CW").frame(width: 38, alignment: .center)
                    Text("SSB").frame(width: 38, alignment: .center)
                    Text("DIGI").frame(width: 38, alignment: .center)
                    Text("TOTAL").frame(width: 45, alignment: .trailing)
                }
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

                Divider()

                ForEach(report.bandRows) { row in
                    HStack(spacing: 4) {
                        Text(row.band)
                            .font(.system(size: 10.5, weight: row.isCurrent ? .black : .bold, design: .monospaced))
                            .foregroundStyle(row.isCurrent ? Color.blue : (row.isWorked ? .primary : .secondary))
                            .frame(width: 45, alignment: .leading)

                        Spacer()

                        slotBadge(status: row.cwStatus, isCurrentBand: row.isCurrent, targetMode: "CW")
                            .frame(width: 38)
                        slotBadge(status: row.ssbStatus, isCurrentBand: row.isCurrent, targetMode: "SSB")
                            .frame(width: 38)
                        slotBadge(status: row.digiStatus, isCurrentBand: row.isCurrent, targetMode: "DIGI")
                            .frame(width: 38)

                        Text("\(row.confirmedCount)/\(row.workedCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(row.confirmedCount > 0 ? .green : (row.workedCount > 0 ? .orange : .secondary.opacity(0.5)))
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(row.isCurrent ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func slotBadge(status: BandSlotStatus, isCurrentBand: Bool, targetMode: String) -> some View {
        let isCurrentDraft = isCurrentBand && (
            (targetMode == "CW" && appState.quickLogDraft.mode.uppercased() == "CW") ||
            (targetMode == "SSB" && ["SSB", "USB", "LSB"].contains(appState.quickLogDraft.mode.uppercased())) ||
            (targetMode == "DIGI" && ["FT8", "FT4", "RTTY", "JS8"].contains(appState.quickLogDraft.mode.uppercased()))
        )

        return HStack(spacing: 2) {
            switch status {
            case .confirmed:
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            case .worked:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            case .unworked:
                Text("—")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary.opacity(0.4))
            case .currentDraft:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(
            isCurrentDraft
                ? Color.blue.opacity(0.25)
                : (status == .confirmed ? Color.green.opacity(0.12) : (status == .worked ? Color.orange.opacity(0.12) : Color.clear)),
            in: RoundedRectangle(cornerRadius: 3)
        )
        .overlay(
            isCurrentDraft ? RoundedRectangle(cornerRadius: 3).stroke(Color.blue, lineWidth: 1) : nil
        )
    }

    // MARK: - Tab 3: History View

    private func historyView(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PREVIOUS QSOs (\(report.totalWorkedCount))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastWorked = report.lastWorkedDate {
                    Text("Last: \(lastWorked.formatted(date: .abbreviated, time: .shortened)) UTC")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if report.matchingPreviousQSOs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                    Text("All-Time New One (ATNO)")
                        .font(.system(size: 12, weight: .bold))
                    Text("No previous QSO with \(report.callsign) found in active logbook.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 3) {
                    ForEach(report.matchingPreviousQSOs) { rec in
                        HStack(spacing: 5) {
                            Text(rec["QSO_DATE"].prefix(8))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(rec["BAND"])
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            Text(rec["MODE"])
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(modeColor(rec["MODE"]))
                            Spacer()
                            Text("\(rec["RST_SENT"])/\(rec["RST_RCVD"])")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if rec.isConfirmed {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.green)
                                    .help("Confirmed")
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private func modeColor(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "CW": return .green
        case "SSB", "USB", "LSB": return .blue
        case "DATA", "DIGI", "FT8", "FT4", "JS8", "MFSK", "RTTY": return .purple
        case "FM", "AM": return .orange
        default: return .secondary
        }
    }

    // MARK: - Tab 4: Spots View

    private func spotsView(report: CallIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE & ARCHIVED CLUSTER SPOTS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            let allSpots = report.liveClusterSpots
            if allSpots.isEmpty && report.recentArchivedSpots.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("No Recent Spots")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No cluster spots detected for \(report.callsign) in the last 48 hours.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 4) {
                    ForEach(allSpots) { spot in
                        HStack(spacing: 6) {
                            Text(String(format: "%.1f", spot.frequencyKHz))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)

                            Text(spot.band)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))

                            Text("by \(spot.spotter)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            if let snr = spot.snrDB {
                                Text("\(snr > 0 ? "+" : "")\(snr) dB")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(snr >= 0 ? .green : .orange)
                            }

                            Button {
                                let hz = UInt64(spot.frequencyKHz * 1000.0)
                                appState.rigControlClient.setFrequencyHz(hz)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("QSY to \(spot.frequencyKHz) kHz")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    // MARK: - Last Logged Footer

    private func lastLoggedFooter(saved: QSORecordModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAST LOGGED QSO")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(DXCCDatabase.resolve(callsign: saved["CALL"]).flagEmoji)
                Text(saved["CALL"])
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(saved["BAND"]) · \(saved["MODE"])")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Default Station Dashboard View (When no callsign is entered)

    private var defaultStationDashboardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Station & Log Intelligence", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            // Operator Profile Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: appState.isRoverActive ? "bolt.car.fill" : "person.crop.circle.badge.checkmark")
                        .font(.system(size: 22))
                        .foregroundStyle(appState.isRoverActive ? Color.orange : Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(appState.currentStationCallsign.isEmpty ? "NO CALL" : appState.currentStationCallsign)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))

                            if appState.isRoverActive {
                                Text("ROVER")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.black)
                            }
                        }

                        Text(appState.activeStationProfile?.name.isEmpty == false ? (appState.activeStationProfile?.name ?? "Operator") : "Operator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    let effGrid = appState.effectiveStationGrid
                    if !effGrid.isEmpty {
                        Text(effGrid)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((appState.isRoverActive ? Color.orange : Color.blue).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(appState.isRoverActive ? Color.orange : Color.blue)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

            // Logbook Quick Stats
            VStack(alignment: .leading, spacing: 8) {
                Text("STATION LOGBOOK")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    statBox(title: "TOTAL QSOs", value: appState.qsoRecords.count.formatted(), color: .primary)
                    let confirmed = appState.qsoRecords.filter(\.isConfirmed).count
                    let rate = appState.qsoRecords.isEmpty ? 0 : Int((Double(confirmed) / Double(appState.qsoRecords.count)) * 100)
                    statBox(title: "CONFIRMED", value: "\(confirmed.formatted()) (\(rate)%)", color: .green)
                }

                HStack(spacing: 8) {
                    let uniqueCalls = Set(appState.qsoRecords.map { $0["CALL"] }).count
                    statBox(title: "UNIQUE CALLS", value: uniqueCalls.formatted(), color: .blue)
                    let activeBands = Set(appState.qsoRecords.map { $0["BAND"] }.filter { !$0.isEmpty }).count
                    statBox(title: "ACTIVE BANDS", value: "\(activeBands) Bands", color: .purple)
                }
            }

            // Operator Shortcuts Card
            VStack(alignment: .leading, spacing: 6) {
                Text("OPERATOR SHORTCUTS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                shortcutRow(key: "Space", desc: "Advance to RST / Exchange")
                shortcutRow(key: "↵ Enter", desc: "Log QSO immediately")
                shortcutRow(key: "Esc", desc: "Wipe form & reset for next")
                shortcutRow(key: "⌘1", desc: "Switch to full Log Table")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12)))

            Spacer()

            if let saved = appState.quickLogLastSaved {
                lastLoggedFooter(saved: saved)
            }
        }
        .padding(16)
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
    }

    private func shortcutRow(key: String, desc: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
