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

struct ContestPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ContestSession()

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
    }

    private var contestHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 30)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Contest Workspace").font(.title3.weight(.bold))
                Text(appState.contestStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if appState.currentContestSession != nil {
                Button {
                    appState.exportCurrentContestCabrillo()
                } label: {
                    Label("Export Cabrillo", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Session Setup", systemImage: "slider.horizontal.3")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    formField("Contest ID") { TextField("CQ-WW-SSB", text: $draft.contestID) }
                    formField("Display name") { TextField("CQ World Wide", text: $draft.contestName) }
                    formField("Sent exchange") { TextField("Zone / state / serial", text: $draft.sentExchange) }
                    formField("Operator") { TextField(appState.currentStationCallsign, text: $draft.operatorCallsign) }
                }
                GridRow {
                    formPicker("Operator", value: $draft.categoryOperator, options: ["SINGLE-OP", "MULTI-OP", "CHECKLOG"])
                    formPicker("Assistance", value: $draft.categoryAssisted, options: ["NON-ASSISTED", "ASSISTED"])
                    formPicker("Band", value: $draft.categoryBand, options: ["ALL", "160M", "80M", "40M", "20M", "15M", "10M", "VHF"])
                    formPicker("Mode", value: $draft.categoryMode, options: ["MIXED", "CW", "SSB", "DIGI", "RTTY"])
                }
                GridRow {
                    formPicker("Power", value: $draft.categoryPower, options: ["HIGH", "LOW", "QRP"])
                    Color.clear
                    Color.clear
                    Color.clear
                }
            }

            HStack {
                Button {
                    appState.startContestSession(draft)
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.contestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Times are stored in UTC. Quick Log will add serial and exchange fields automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func sessionDashboard(_ session: ContestSession) -> some View {
        let summary = appState.contestSummary()
        let records = appState.contestRecords()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.displayName).font(.title2.weight(.bold))
                        Text(session.isActive ? "ACTIVE" : "ENDED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(session.isActive ? .green : .secondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background((session.isActive ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
                    }
                    Text("\(session.contestID) · Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) UTC")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.isActive {
                    Button {
                        appState.operatorDeskSection = 0
                    } label: {
                        Label("Open Quick Log", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        appState.endContestSession()
                    } label: {
                        Label("End", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        appState.resumeContestSession()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        appState.clearContestSession()
                        draft = ContestSession(operatorCallsign: appState.currentStationCallsign)
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
            .padding(20)

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 1)], spacing: 1) {
                metric("QSOs", value: summary.qsoCount, icon: "antenna.radiowaves.left.and.right", color: .blue)
                metric("Unique Calls", value: summary.uniqueCallsigns, icon: "person.2", color: .purple)
                metric("DXCC", value: summary.uniqueDXCC, icon: "globe", color: .green)
                metric("Bands", value: summary.uniqueBands, icon: "waveform", color: .orange)
                metric("Dupes", value: summary.duplicateCount, icon: "exclamationmark.triangle", color: summary.duplicateCount > 0 ? .red : .secondary)
                metric("Next Serial", value: ContestWorkspaceLogic.nextSerial(in: session, records: appState.qsoRecords), icon: "number", color: .primary)
            }
            .background(Color(nsColor: .separatorColor).opacity(0.55))

            Divider()

            HStack(spacing: 30) {
                detail("Sent exchange", value: session.sentExchange.isEmpty ? "--" : session.sentExchange)
                detail("Category", value: "\(session.categoryOperator) · \(session.categoryPower)")
                detail("Band / Mode", value: "\(session.categoryBand) · \(session.categoryMode)")
                Spacer()
            }
            .padding(20)

            Divider()
            recentContestQSOs(records)
        }
    }

    private func recentContestQSOs(_ records: [QSORecordModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Contest QSOs", systemImage: "list.bullet.rectangle")
                .font(.headline)
            if records.isEmpty {
                ContentUnavailableView(
                    "No Contest QSOs Yet",
                    systemImage: "flag.checkered",
                    description: Text("QSOs logged while this session is active appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Grid(horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        tableHeading("UTC")
                        tableHeading("CALL")
                        tableHeading("BAND")
                        tableHeading("MODE")
                        tableHeading("SENT")
                        tableHeading("RCVD")
                    }
                    Divider().gridCellColumns(6)
                    ForEach(records.prefix(30)) { record in
                        GridRow {
                            Text(record["TIME_ON"]).monospacedDigit()
                            Text(record["CALL"]).fontWeight(.semibold).monospaced()
                            Text(record["BAND"])
                            Text(record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"])
                            Text(record["STX_STRING"].isEmpty ? record["STX"] : record["STX_STRING"])
                            Text(record["SRX_STRING"].isEmpty ? record["SRX"] : record["SRX_STRING"])
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(20)
    }

    private func metric(_ title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted()).font(.system(.title3, design: .rounded).weight(.bold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(minHeight: 68)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced).weight(.semibold))
        }
    }

    private func formField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formPicker(_ title: String, value: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
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

    private func hydrateDraft() {
        if let current = appState.currentContestSession {
            draft = current
        } else {
            draft.operatorCallsign = appState.currentStationCallsign
        }
    }
}
