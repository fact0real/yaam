//
//  ON4KSTView.swift
//  YAAM
//
//  ON4KST Real-Time VHF / UHF / Microwave Chat & Propagation Sked Monitor
//  Live room chat stream, automated frequency & sked detection, 1-click QSY & antenna steering,
//  and active user directory with real-time great-circle distance & bearing calculation.
//

import AppKit
import SwiftUI

public struct ON4KSTView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var kst = ON4KSTClient.shared
    @ObservedObject private var rotator = RotatorService.shared

    @State private var inputCallsign: String = ""
    @State private var inputPassword: String = ""
    @State private var outgoingMessage: String = ""
    @State private var selectedRecipient: String = "ALL"
    @State private var userSearchText: String = ""
    @State private var actionBanner: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header & Room Selector Bar
            topBar

            Divider()

            // Main Split: Chat Stream + Online Users Sidebar
            HSplitView {
                // Left: Live Chat & Sked Stream
                chatPane
                    .frame(minWidth: 420)

                // Right: Online Active Operators Roster
                usersSidebar
                    .frame(minWidth: 220, maxWidth: 300)
            }

            Divider()

            // Bottom Message Composer & Quick CQ Buttons
            composerBar
        }
        .onAppear {
            if inputCallsign.isEmpty {
                inputCallsign = appState.activeStationProfile?.callsign ?? "EP2AES"
            }
        }
    }

    // MARK: - Top Room & Connection Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text("ON4KST Chat")
                    .font(.headline.bold())
            }

            // Room Picker Segment
            Picker("Room", selection: $kst.selectedRoom) {
                ForEach(ON4KSTRoom.allCases) { r in
                    Text(r.shortName).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            .onChange(of: kst.selectedRoom) { _, newRoom in
                if kst.isConnected {
                    kst.connect(room: newRoom, callsign: inputCallsign, password: inputPassword)
                }
            }

            Spacer()

            if !kst.isConnected {
                TextField("Callsign", text: $inputCallsign)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                SecureField("Password (or blank)", text: $inputPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Button("Connect") {
                    kst.connect(callsign: inputCallsign, password: inputPassword)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Connected to \(kst.selectedRoom.shortName)")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: Capsule())

                Button("Disconnect", role: .destructive) {
                    kst.disconnect()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left: Live Chat & Sked Stream

    private var chatPane: some View {
        VStack(spacing: 0) {
            if !actionBanner.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(actionBanner)
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        actionBanner = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(kst.messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: kst.messages.count) { _, _ in
                    if let last = kst.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func messageBubble(_ msg: ON4KSTMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // Sender Badge
                Button {
                    selectedRecipient = msg.sender
                } label: {
                    Text(msg.sender)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(msg.isSpot ? .orange : (msg.isDirected ? .purple : .blue))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (msg.isSpot ? Color.orange : (msg.isDirected ? Color.purple : Color.blue)).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)

                if let recip = msg.recipient {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(recip)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(formattedTime(msg.timestamp))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Message Body
            Text(msg.text)
                .font(.system(size: 12.5))
                .foregroundColor(.primary)
                .textSelection(.enabled)

            // Detected Sked / Frequency Action Bar
            if let freq = msg.detectedFrequencyMHz {
                HStack(spacing: 8) {
                    Label(String(format: "%.3f MHz", freq), systemImage: "waveform")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.indigo)

                    Button {
                        qsyToFrequency(freq, callsign: msg.sender)
                    } label: {
                        Text("QSY")
                            .font(.caption2.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .controlSize(.mini)

                    Button {
                        appState.quickLogDraft.callsign = msg.sender
                        appState.quickLogDraft.frequencyMHz = String(format: "%.4f", freq)
                        appState.selectedTab = 5
                        appState.operatorDeskSection = 0
                    } label: {
                        Text("Log Draft")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Spacer()
                }
                .padding(6)
                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(msg.isDirected ? Color.purple.opacity(0.06) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(msg.isDirected ? Color.purple.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Right: Online Active Operators Sidebar

    private var usersSidebar: some View {
        VStack(spacing: 0) {
            // Search Box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search stations...", text: $userSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HStack {
                Text("ONLINE STATIONS (\(filteredUsers.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(filteredUsers) { user in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Button {
                            selectedRecipient = user.callsign
                        } label: {
                            Text(user.callsign)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !user.locator.isEmpty {
                            Text(user.locator)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let dist = user.distanceKm, let bearing = user.bearingDeg {
                        HStack(spacing: 6) {
                            Text("\(Int(dist)) km")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)

                            Text("• \(Int(bearing))° \(GeodesicMath.compassCardinal(for: bearing))")
                                .font(.caption2.bold())
                                .foregroundColor(.blue)

                            Spacer()

                            Button {
                                rotator.turnTo(azimuth: bearing)
                                actionBanner = "Rotator turning to \(user.callsign) at \(Int(bearing))°"
                            } label: {
                                Image(systemName: "location.north.line.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.orange)
                            .help("Turn rotator to \(user.callsign)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var filteredUsers: [ON4KSTUser] {
        if userSearchText.isEmpty {
            return kst.onlineUsers
        }
        return kst.onlineUsers.filter {
            $0.callsign.localizedCaseInsensitiveContains(userSearchText) ||
            $0.locator.localizedCaseInsensitiveContains(userSearchText)
        }
    }

    // MARK: - Bottom: Composer Bar & Quick CQ Templates

    private var composerBar: some View {
        VStack(spacing: 8) {
            // Quick CQ / Sked Action Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickCQButton("CQ 50.313 FT8", freq: "50.313", mode: "FT8")
                    quickCQButton("CQ 144.174 FT8", freq: "144.174", mode: "FT8")
                    quickCQButton("CQ 144.200 SSB", freq: "144.200", mode: "SSB")
                    quickCQButton("CQ 432.200 SSB", freq: "432.200", mode: "SSB")
                    quickCQButton("Any 6m Es opening?", freq: "50.313", mode: "FT8")
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                // Recipient Dropdown / Selector
                Picker("To:", selection: $selectedRecipient) {
                    Text("ALL (Public)").tag("ALL")
                    ForEach(kst.onlineUsers) { u in
                        Text(u.callsign).tag(u.callsign)
                    }
                }
                .frame(width: 140)

                TextField("Type chat message or /sked proposal...", text: $outgoingMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(outgoingMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func quickCQButton(_ title: String, freq: String, mode: String) -> some View {
        Button {
            kst.sendCQ(frequencyMHz: freq, mode: mode)
            actionBanner = "Posted '\(title)' to \(kst.selectedRoom.shortName)"
        } label: {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())
                .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
    }

    private func sendMessage() {
        let text = outgoingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        kst.sendMessage(text: text, recipient: selectedRecipient == "ALL" ? nil : selectedRecipient)
        outgoingMessage = ""
    }

    private func qsyToFrequency(_ freqMHz: Double, callsign: String) {
        let hz = UInt64(freqMHz * 1_000_000.0)

        // 1. QSY via TCI if connected
        if TCIClient.shared.isConnected {
            TCIClient.shared.setFrequency(hz: hz)
        } else if FLRigClient.shared.isConnected {
            Task {
                try? await FLRigClient.shared.setFrequency(hz: Double(hz))
            }
        }

        // 2. Draft in Quick Log
        appState.quickLogDraft.callsign = callsign
        appState.quickLogDraft.frequencyMHz = String(format: "%.4f", freqMHz)
        actionBanner = "QSY to \(String(format: "%.3f MHz", freqMHz)) for \(callsign)"
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
