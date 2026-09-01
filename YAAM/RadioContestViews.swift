//
//  RadioContestViews.swift
//  YAAM
//

import SwiftUI

struct RadioBridgePanel: View {
    private enum Workspace: String, CaseIterable, Identifiable {
        case bridge = "Bridge"
        case ft8 = "FT8 Station"

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject var rig: RigControlClient
    @ObservedObject var wsjtx: WSJTXListener
    @AppStorage("rigControlHost") private var rigHost = "127.0.0.1"
    @AppStorage("rigControlPort") private var rigPort = 4532
    @AppStorage("rigAutoFillQuickLog") private var rigAutoFill = false
    @AppStorage("wsjtxUDPPort") private var wsjtxPort = 2237
    @AppStorage("wsjtxAutoFillQuickLog") private var wsjtxAutoFill = false
    @State private var actionStatus = ""
    @State private var workspace: Workspace = .bridge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if workspace == .bridge {
                    rigSection
                    Divider()
                    wsjtxSection
                    Divider()
                    pendingSection
                } else {
                    FT8StationView(
                        engine: appState.ft8Engine,
                        radio: appState.icomNetworkRadio,
                        rig: rig
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace == .bridge ? "Radio & Digital Bridge" : "FT8 Station").font(.title3.weight(.bold))
                Text(workspace == .bridge
                     ? "One operating context for your radio, WSJT-X/JTDX, and Quick Log"
                     : "Native FT8 receive, decode, sequencing, and guarded transmit")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Radio workspace", selection: $workspace) {
                ForEach(Workspace.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            if !actionStatus.isEmpty {
                Text(actionStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(20)
    }

    private var rigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Rig Control", icon: "radio", active: rig.state.isConnected, subtitle: rig.lastMessage)
                Spacer()
                Toggle("Fill Quick Log", isOn: $rigAutoFill)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button {
                    rig.state.isConnected ? rig.disconnect() : rig.connect(host: rigHost, port: rigPort)
                } label: {
                    Label(rig.state.isConnected ? "Disconnect" : "Connect", systemImage: rig.state.isConnected ? "xmark.circle" : "link")
                }
                .buttonStyle(.borderedProminent)
                .tint(rig.state.isConnected ? .secondary : .accentColor)
            }

            HStack(alignment: .bottom, spacing: 12) {
                settingField("Host", width: 190) {
                    TextField("127.0.0.1", text: $rigHost).textFieldStyle(.roundedBorder)
                }
                settingField("TCP Port", width: 100) {
                    TextField("4532", value: $rigPort, format: .number).textFieldStyle(.roundedBorder)
                }

                Divider().frame(height: 40).padding(.horizontal, 4)

                if let snapshot = rig.snapshot {
                    liveMetric("Frequency", value: "\(snapshot.frequencyMHz) MHz", color: .blue, width: 170)
                    liveMetric("Band", value: snapshot.band.isEmpty ? "--" : snapshot.band, color: .primary, width: 80)
                    liveMetric("Mode", value: snapshot.mode.isEmpty ? "--" : snapshot.mode, color: .primary, width: 100)
                    Button {
                        appState.applyRigSnapshotToQuickLog(snapshot)
                        actionStatus = "Rig frequency and mode copied to Quick Log"
                    } label: {
                        Label("Use in Quick Log", systemImage: "arrow.down.to.line.compact")
                    }
                } else {
                    Text("Connect to Hamlib rigctld to read frequency and mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Keep rigctld on this Mac or a trusted local network. The rigctld TCP protocol is not encrypted.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var wsjtxSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("WSJT-X / JTDX", icon: "dot.radiowaves.left.and.right", active: wsjtx.state.isListening, subtitle: wsjtx.lastMessage)
                Spacer()
                Toggle("Fill Quick Log", isOn: $wsjtxAutoFill)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                settingField("UDP Port", width: 95) {
                    TextField("2237", value: $wsjtxPort, format: .number).textFieldStyle(.roundedBorder)
                }
                Button {
                    wsjtx.state.isListening ? wsjtx.stop() : wsjtx.start(port: wsjtxPort)
                } label: {
                    Label(wsjtx.state.isListening ? "Stop" : "Listen", systemImage: wsjtx.state.isListening ? "stop.circle" : "ear")
                }
                .buttonStyle(.borderedProminent)
                .tint(wsjtx.state.isListening ? .secondary : .accentColor)
            }

            if let status = wsjtx.lastStatus {
                HStack(spacing: 20) {
                    liveMetric("Application", value: status.sourceID, color: .primary, width: 120)
                    liveMetric("Dial", value: "\(status.frequencyMHz) MHz", color: .blue, width: 170)
                    liveMetric("Mode", value: status.mode, color: .primary, width: 90)
                    liveMetric("DX", value: status.dxCallsign.isEmpty ? "--" : status.dxCallsign, color: .orange, width: 120)
                    liveMetric("Grid", value: status.dxGrid.isEmpty ? "--" : status.dxGrid, color: .primary, width: 90)
                    Label(status.transmitting ? "Transmitting" : (status.decoding ? "Decoding" : "Monitoring"),
                          systemImage: status.transmitting ? "antenna.radiowaves.left.and.right" : "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.transmitting ? .red : .green)
                    Spacer()
                }
            } else {
                Text("Set the same UDP server port in WSJT-X/JTDX. Logged ADIF messages are held for review below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Digital QSO Review", systemImage: "tray.full")
                    .font(.headline)
                Text(appState.wsjtxPendingQSOs.count.formatted())
                    .font(.caption.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Text("Review-first import prevents accidental duplicates")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if appState.wsjtxPendingQSOs.isEmpty {
                ContentUnavailableView(
                    "No Digital QSOs Waiting",
                    systemImage: "checkmark.circle",
                    description: Text("New Logged ADIF packets appear here before they enter the station log.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(appState.wsjtxPendingQSOs) { pending in
                        pendingRow(pending)
                        Divider()
                    }
                }
            }
        }
        .padding(20)
    }

    private func pendingRow(_ pending: WSJTXPendingQSO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: pending.isDuplicate ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(pending.isDuplicate ? .orange : .green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(pending.callsign.isEmpty ? "Unknown callsign" : pending.callsign)
                    .font(.system(.headline, design: .monospaced))
                Text("\(pending.sourceID) · \(pending.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(pending.band.isEmpty ? "--" : pending.band).frame(width: 60)
            Text(pending.mode.isEmpty ? "--" : pending.mode).frame(width: 70)
            if pending.isDuplicate {
                Text("Duplicate").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Spacer()
            Button {
                appState.prepareQuickLog(from: pending)
            } label: {
                Label("Review", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                do {
                    _ = try appState.importWSJTXPendingQSO(id: pending.id)
                    actionStatus = "\(pending.callsign) added to the active station log"
                } catch {
                    actionStatus = error.localizedDescription
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(pending.isDuplicate)
            Button(role: .destructive) {
                appState.dismissWSJTXPendingQSO(id: pending.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss this queued QSO")
        }
        .padding(.vertical, 10)
    }

    private func sectionTitle(_ title: String, icon: String, active: Bool, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(active ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func settingField<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private func liveMetric(_ title: String, value: String, color: Color, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Advanced Contest Workspace Panel

struct ContestPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ContestSession()
    @State private var showCabrilloInspector = false
    @State private var selectedTemplateID: String = "CQ-WW-SSB"

    // Fast Logging HUD State
    @State private var inputCall = ""
    @State private var inputBand = "20M"
    @State private var inputMode = "SSB"
    @State private var inputRstSent = "59"
    @State private var inputRstRcvd = "59"
    @State private var inputSentExchange = "21"
    @State private var inputRcvdExchange = ""
    @State private var fastLogStatus = ""
    @State private var fastLogSuccess = false

    private let contestBands = ["160M", "80M", "40M", "20M", "15M", "10M", "6M"]
    private let contestModes = ["SSB", "CW", "RTTY", "DIGI"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                contestHeader
                Divider()
                if let session = appState.currentContestSession {
                    sessionDashboard(session)
                } else {
                    setupPanel
                }
            }
        }
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .onAppear { hydrateDraft() }
        .sheet(isPresented: $showCabrilloInspector) {
            CabrilloInspectorSheet()
        }
    }

    // MARK: - 1. Contest Workspace Header
    private var contestHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 30)).foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Contest Operations & Scoring Engine").font(.title3.weight(.bold))
                Text(appState.contestStatus.isEmpty ? "High-speed logging, real-time multiplier matrix, and official Cabrillo 3.0 export" : appState.contestStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if appState.currentContestSession != nil {
                Button {
                    showCabrilloInspector = true
                } label: {
                    Label("Inspect & Export Cabrillo", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(20)
    }

    // MARK: - 2. Session Setup & Template Chooser Panel
    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Start a New Contest Session", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text("Pre-configures rules, exchange formats, and Cabrillo headers")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Quick Preset Contest Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("POPULAR GLOBAL CONTEST PRESETS:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ContestTemplate.catalog) { tmpl in
                            Button {
                                applyTemplate(tmpl)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(tmpl.id)
                                            .font(.caption.monospaced().weight(.bold))
                                            .foregroundStyle(selectedTemplateID == tmpl.id ? .orange : .primary)
                                        Spacer()
                                        Text(tmpl.defaultCategoryMode)
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(tmpl.name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(8)
                                .frame(width: 170, alignment: .leading)
                                .background(selectedTemplateID == tmpl.id ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedTemplateID == tmpl.id ? Color.orange : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    formField("Contest ID (Cabrillo Tag)") { TextField("CQ-WW-SSB", text: $draft.contestID) }
                    formField("Contest Display Name") { TextField("CQ World Wide DX (SSB)", text: $draft.contestName) }
                    formField("Sent Exchange (Zone/Serial/State)") { TextField("21", text: $draft.sentExchange) }
                    formField("Operator Callsign") { TextField(appState.currentStationCallsign, text: $draft.operatorCallsign) }
                }
                GridRow {
                    formPicker("Operator Category", value: $draft.categoryOperator, options: ["SINGLE-OP", "MULTI-OP", "CHECKLOG"])
                    formPicker("Assistance", value: $draft.categoryAssisted, options: ["NON-ASSISTED", "ASSISTED"])
                    formPicker("Band Category", value: $draft.categoryBand, options: ["ALL", "160M", "80M", "40M", "20M", "15M", "10M", "VHF"])
                    formPicker("Mode Category", value: $draft.categoryMode, options: ["SSB", "CW", "RTTY", "MIXED", "DIGI"])
                }
                GridRow {
                    formPicker("Power Category", value: $draft.categoryPower, options: ["LOW", "HIGH", "QRP"])
                    formPicker("Transmitter", value: $draft.categoryTransmitter, options: ["ONE", "TWO", "MULTI"])
                    formPicker("Station Category", value: $draft.categoryStation, options: ["FIXED", "PORTABLE", "MOBILE", "ROVER"])
                    formField("Club Affiliation") { TextField("DX Contest Club", text: $draft.club) }
                }
            }

            HStack {
                Button {
                    appState.startContestSession(draft)
                    syncFastLogInputs(session: draft)
                } label: {
                    Label("Start Contest Session", systemImage: "play.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.contestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Times are logged in UTC. Serial numbers increment automatically on each logged contact.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    // MARK: - 3. Active Session Dashboard with Fast Logging HUD
    private func sessionDashboard(_ session: ContestSession) -> some View {
        let summary = appState.contestSummary()
        let records = appState.contestRecords()

        return VStack(alignment: .leading, spacing: 0) {
            // Session Status & Control Bar
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.displayName).font(.title2.weight(.bold))
                        Text(session.isActive ? "ACTIVE SESSION" : "CONTEST ENDED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(session.isActive ? .green : .secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((session.isActive ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
                    }
                    Text("\(session.contestID) · Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) UTC · Category: \(session.categoryOperator) \(session.categoryPower) \(session.categoryMode)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if session.isActive {
                    Button {
                        showCabrilloInspector = true
                    } label: {
                        Label("Cabrillo 3.0", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        appState.endContestSession()
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        appState.resumeContestSession()
                    } label: {
                        Label("Resume Session", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        appState.clearContestSession()
                        draft = ContestSession(operatorCallsign: appState.currentStationCallsign)
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(20)

            Divider()

            // High-Speed Contest Logging HUD (ESM Flow)
            if session.isActive {
                fastContestLoggingHUD(session)
                Divider()
            }

            // Real-Time Claimed Score Gauge & Metrics Bar
            claimedScoreBanner(summary)

            Divider()

            // Band-by-Band Scoring Multiplier Matrix
            bandScoreMatrix(summary)

            Divider()

            // Recent Contest QSOs Stream
            recentContestQSOs(records)
        }
    }

    // MARK: - 4. Fast-Paced Contest Logging Entry HUD
    private func fastContestLoggingHUD(_ session: ContestSession) -> some View {
        let isDupe = appState.isCurrentContestDuplicate(callsign: inputCall, band: inputBand, mode: inputMode)
        let scpMatches = SuperCheckPartial.match(query: inputCall, recentContestRecords: appState.contestRecords())

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fast Contest Entry HUD (ESM)", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                // Band Chips
                HStack(spacing: 4) {
                    ForEach(contestBands, id: \.self) { band in
                        Button {
                            inputBand = band
                        } label: {
                            Text(band)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(inputBand == band ? Color.orange : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(inputBand == band ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().frame(height: 14)

                // Mode Chips
                HStack(spacing: 4) {
                    ForEach(contestModes, id: \.self) { mode in
                        Button {
                            inputMode = mode
                            inputRstSent = (mode == "CW" || mode == "RTTY") ? "599" : "59"
                            inputRstRcvd = (mode == "CW" || mode == "RTTY") ? "599" : "59"
                        } label: {
                            Text(mode)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(inputMode == mode ? Color.blue : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(inputMode == mode ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Input Fields Row
            HStack(spacing: 10) {
                // Callsign
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALLSIGN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("DL1AAA", text: $inputCall)
                        .font(.title3.monospaced().weight(.bold))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }

                // Sent RST
                VStack(alignment: .leading, spacing: 3) {
                    Text("SENT RST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("59", text: $inputRstSent)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 65)
                }

                // Sent Exchange / Serial
                VStack(alignment: .leading, spacing: 3) {
                    Text("SENT EXCH (#\(String(format: "%03d", session.nextSerial)))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField(session.sentExchange.isEmpty ? "001" : session.sentExchange, text: $inputSentExchange)
                        .font(.body.monospaced().weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 95)
                }

                // Received RST
                VStack(alignment: .leading, spacing: 3) {
                    Text("RCVD RST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("59", text: $inputRstRcvd)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 65)
                }

                // Received Exchange
                VStack(alignment: .leading, spacing: 3) {
                    Text("RCVD EXCH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("14 / 001 / CA", text: $inputRcvdExchange)
                        .font(.title3.monospaced().weight(.bold))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onSubmit {
                            submitFastQSO(session: session)
                        }
                }

                // Log Button
                Button {
                    submitFastQSO(session: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.left")
                        Text("Log (↵)")
                    }
                    .font(.body.weight(.bold))
                    .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(isDupe ? .orange : .green)
                .disabled(inputCall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 14)

                Spacer()
            }

            // Real-Time Dupe & Super Check Partial Pill
            HStack(spacing: 8) {
                if inputCall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Ready for callsign entry", systemImage: "keyboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isDupe {
                    Label("⚠️ DUPE: \(inputCall.uppercased()) already logged on \(inputBand) \(inputMode)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                } else {
                    Label("✅ VALID QSO (+3 Pts on \(inputBand))", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }

                if !scpMatches.isEmpty {
                    Text("SCP:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ForEach(scpMatches, id: \.self) { candidate in
                        Button {
                            inputCall = candidate
                        } label: {
                            Text(candidate)
                                .font(.caption2.monospaced().weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                if !fastLogStatus.isEmpty {
                    Text(fastLogStatus)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(fastLogSuccess ? .green : .red)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func submitFastQSO(session: ContestSession) {
        let cleanCall = inputCall.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return }

        let rcvd = inputRcvdExchange.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent = inputSentExchange.isEmpty ? session.sentExchange : inputSentExchange

        do {
            _ = try appState.logContestFastQSO(
                callsign: cleanCall,
                band: inputBand,
                mode: inputMode,
                frequencyMHz: "",
                rstSent: inputRstSent,
                rstReceived: inputRstRcvd,
                sentExchange: sent,
                receivedExchange: rcvd
            )

            fastLogSuccess = true
            fastLogStatus = "✅ Logged \(cleanCall) #\(session.nextSerial)"
            inputCall = ""
            inputRcvdExchange = ""
            inputSentExchange = session.sentExchange.isEmpty ? String(format: "%03d", session.nextSerial + 1) : session.sentExchange
        } catch {
            fastLogSuccess = false
            fastLogStatus = "❌ \(error.localizedDescription)"
        }
    }

    // MARK: - 5. Claimed Score Banner & Rate Gauges
    private func claimedScoreBanner(_ summary: ContestSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                // Primary Claimed Score Box
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLAIMED CONTEST SCORE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(summary.claimedScore.formatted())
                        .font(.system(size: 32, design: .rounded).weight(.heavy))
                        .foregroundStyle(.orange)

                    Text("\(summary.totalPoints.formatted()) pts × \(summary.totalMultipliers.formatted()) mults")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 10)

                Divider().frame(height: 50)

                // Rate Gauges
                rateMetric("10m Rate", value: "\(Int(summary.rateLast10Min))", unit: "QSOs/hr", icon: "gauge.with.needle.fill", color: .green)
                rateMetric("60m Rate", value: "\(Int(summary.rateLast60Min))", unit: "QSOs/hr", icon: "speedometer", color: .blue)

                Divider().frame(height: 50)

                // Counts
                metric("Valid QSOs", value: summary.qsoCount, icon: "antenna.radiowaves.left.and.right", color: .blue)
                metric("Multipliers", value: summary.totalMultipliers, icon: "sparkles", color: .yellow)
                metric("Dupes", value: summary.duplicateCount, icon: "exclamationmark.triangle", color: summary.duplicateCount > 0 ? .red : .secondary)

                Spacer()
            }
            .padding(16)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        }
        .padding(16)
    }

    private func rateMetric(_ title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3.monospaced().weight(.bold))
                    Text(unit)
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 6. Band-by-Band Scoring Multiplier Matrix Table
    private func bandScoreMatrix(_ summary: ContestSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Band-by-Band Scoring & Multiplier Breakdown", systemImage: "tablecells.badge.ellipsis")
                    .font(.headline)
                Spacer()
                Text("Tracks points, dupes, and multipliers per active band")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if summary.bandBreakdown.isEmpty {
                Text("No QSOs recorded yet in this contest session. Use the Fast Entry HUD above to begin logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("BAND").frame(width: 80, alignment: .leading)
                        Text("VALID QSOS").frame(width: 100, alignment: .leading)
                        Text("DUPES").frame(width: 70, alignment: .leading)
                        Text("QSO POINTS").frame(width: 100, alignment: .leading)
                        Text("MULTS").frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("MULTIPLIER DETAILS").frame(width: 160, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .separatorColor).opacity(0.12))

                    Divider()

                    ForEach(summary.bandBreakdown) { bandScore in
                        HStack {
                            Text(bandScore.band)
                                .font(.caption.monospaced().weight(.bold))
                                .frame(width: 80, alignment: .leading)

                            Text("\(bandScore.qsoCount)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .frame(width: 100, alignment: .leading)

                            Text("\(bandScore.dupeCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(bandScore.dupeCount > 0 ? .red : .secondary)
                                .frame(width: 70, alignment: .leading)

                            Text("\(bandScore.points)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 100, alignment: .leading)

                            Text("\(bandScore.multipliers)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 80, alignment: .leading)

                            Spacer()

                            Text(bandScore.multDetail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)

                        Divider()
                    }

                    // Total Summary Row
                    HStack {
                        Text("TOTAL")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)

                        Text("\(summary.qsoCount)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 100, alignment: .leading)

                        Text("\(summary.duplicateCount)")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(summary.duplicateCount > 0 ? .red : .secondary)
                            .frame(width: 70, alignment: .leading)

                        Text("\(summary.totalPoints)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.blue)
                            .frame(width: 100, alignment: .leading)

                        Text("\(summary.totalMultipliers)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.orange)
                            .frame(width: 80, alignment: .leading)

                        Spacer()

                        Text("Claimed: \(summary.claimedScore.formatted())")
                            .font(.caption.monospaced().weight(.heavy))
                            .foregroundStyle(.orange)
                            .frame(width: 160, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
            }
        }
        .padding(16)
    }

    // MARK: - 7. Recent Contest QSOs List
    private func recentContestQSOs(_ records: [QSORecordModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Contest QSOs Stream", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(records.count) logged contacts in session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                ContentUnavailableView(
                    "No Contest QSOs Yet",
                    systemImage: "flag.checkered",
                    description: Text("QSOs logged with the Fast Entry HUD appear here in real time.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Grid(horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        tableHeading("UTC")
                        tableHeading("CALLSIGN")
                        tableHeading("BAND")
                        tableHeading("MODE")
                        tableHeading("SENT EXCH")
                        tableHeading("RCVD EXCH")
                    }
                    Divider().gridCellColumns(6)
                    ForEach(records.prefix(25)) { record in
                        GridRow {
                            Text(record["TIME_ON"]).monospacedDigit()
                            HStack(spacing: 4) {
                                if let flag = flagFromCallsignPrefix(record["CALL"]) {
                                    Text(flag)
                                }
                                Text(record["CALL"]).fontWeight(.semibold).monospaced()
                            }
                            Text(record["BAND"]).font(.caption.monospaced())
                            Text(record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]).font(.caption)
                            Text(record["STX_STRING"].isEmpty ? record["STX"] : record["STX_STRING"]).monospaced()
                            Text(record["SRX_STRING"].isEmpty ? record["SRX"] : record["SRX_STRING"]).monospaced().fontWeight(.semibold)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(16)
    }

    private func metric(_ title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted()).font(.subheadline.monospacedDigit().weight(.bold))
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func formField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formPicker(_ title: String, value: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Picker("", selection: value) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableHeading(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
    }

    private func applyTemplate(_ tmpl: ContestTemplate) {
        selectedTemplateID = tmpl.id
        draft.contestID = tmpl.id
        draft.contestName = tmpl.name
        draft.sentExchange = tmpl.defaultSentExchange
        draft.categoryMode = tmpl.defaultCategoryMode
        inputSentExchange = tmpl.defaultSentExchange
        inputMode = tmpl.defaultCategoryMode == "MIXED" ? "SSB" : tmpl.defaultCategoryMode
    }

    private func syncFastLogInputs(session: ContestSession) {
        inputSentExchange = session.sentExchange.isEmpty ? "001" : session.sentExchange
        inputMode = session.categoryMode == "MIXED" ? "SSB" : session.categoryMode
    }

    private func hydrateDraft() {
        if let current = appState.currentContestSession {
            draft = current
            syncFastLogInputs(session: current)
        } else {
            draft.operatorCallsign = appState.currentStationCallsign
            if let first = ContestTemplate.catalog.first {
                applyTemplate(first)
            }
        }
    }
}

// MARK: - Official Cabrillo 3.0 / 2.0 Inspector & Pre-Flight Validator Sheet

public struct CabrilloInspectorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copyStatus = ""

    public var body: some View {
        let session = appState.currentContestSession ?? ContestSession()
        let records = appState.contestRecords()
        let issues = appState.validateCurrentContestCabrillo()
        let cabrilloContent = CabrilloExporter.generate(
            session: session,
            station: appState.activeStationProfile,
            records: appState.qsoRecords,
            createdBy: "YAAM \(appState.currentVersion)"
        )

        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Cabrillo 3.0 Log Inspector & Pre-Flight Validator", systemImage: "doc.text.magnifyingglass")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("Verify official robot submission compliance before submitting your log to contest sponsors:")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Pre-Flight Validation Status Bar
            HStack(spacing: 12) {
                let errorCount = issues.filter { $0.severity == .error }.count
                let warningCount = issues.filter { $0.severity == .warning }.count

                if errorCount == 0 && warningCount == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("100% Valid Cabrillo Log")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.green)
                            Text("Ready for direct robot upload to CQ / ARRL / DARC / IARU")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(errorCount > 0 ? .red : .yellow)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(errorCount) Errors · \(warningCount) Warnings Detected")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(errorCount > 0 ? .red : .yellow)
                            Text("Review items below before exporting")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cabrilloContent, forType: .string)
                        copyStatus = "✅ Copied to clipboard!"
                    } label: {
                        Label("Copy Log", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        appState.exportCurrentContestCabrillo()
                    } label: {
                        Label("Export File (.log / .cbr)", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            // Validation Issues List (if any)
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { issue in
                        HStack(spacing: 6) {
                            Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .yellow)
                                .font(.caption2)
                            Text(issue.message)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Raw Cabrillo Text View
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CABRILLO 3.0 OUTPUT PREVIEW (\(records.count) QSOs):")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !copyStatus.isEmpty {
                        Text(copyStatus)
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }

                ScrollView {
                    Text(cabrilloContent)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 640, idealWidth: 700, minHeight: 500, idealHeight: 600)
    }
}

