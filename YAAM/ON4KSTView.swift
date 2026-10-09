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
    @State private var showOnlyDirected: Bool = false

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
                    .frame(minWidth: 460)

                // Right: Online Active Operators Roster
                usersSidebar
                    .frame(minWidth: 260, maxWidth: 340)
            }

            Divider()

            // Bottom Message Composer & Quick CQ Buttons
            composerBar
        }
        .onAppear {
            if inputCallsign.isEmpty {
                inputCallsign = appState.activeStationProfile?.normalizedCallsign ?? ""
            }
            if kst.myGrid.isEmpty {
                kst.myGrid = appState.activeStationProfile?.normalizedGrid ?? ""
            }
        }
    }

    // MARK: - Top Room & Connection Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("ON4KST Chat & DX Skeds")
                            .font(.system(size: 13, weight: .bold))
                        Text("VHF / UHF / Microwave / 160m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("Direct propagation coordination & real-time chat gateway")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Room Picker Segment
            Picker("Room", selection: $kst.selectedRoom) {
                ForEach(ON4KSTRoom.allCases) { r in
                    Text(r.shortName).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)
            .onChange(of: kst.selectedRoom) { _, newRoom in
                if kst.isConnected {
                    kst.connect(room: newRoom, callsign: inputCallsign, password: inputPassword)
                }
            }

            Divider()
                .frame(height: 20)

            if !kst.isConnected {
                HStack(spacing: 6) {
                    TextField("Callsign", text: $inputCallsign)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 95)

                    SecureField("Password (optional)", text: $inputPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Button {
                        kst.connect(callsign: inputCallsign, password: inputPassword)
                    } label: {
                        Label("Connect", systemImage: "bolt.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Online (\(kst.selectedRoom.shortName))")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())

                    Button("Disconnect", role: .destructive) {
                        kst.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left: Live Chat & Sked Stream

    private var chatPane: some View {
        VStack(spacing: 0) {
            // Action & Filter Notification Bar
            HStack(spacing: 8) {
                if !actionBanner.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(actionBanner)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        actionBanner = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("ROOM: \(kst.selectedRoom.title)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle(isOn: $showOnlyDirected) {
                        Label("Directed to me", systemImage: "at")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(actionBanner.isEmpty ? Color(NSColor.controlBackgroundColor).opacity(0.6) : Color.green.opacity(0.14))

            Divider()

            if filteredMessages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: kst.isConnected ? "bubble.left.and.bubble.right" : "network.slash")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.6))
                    if !kst.isConnected {
                        Text("Not Connected to ON4KST")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Enter your callsign and click **Connect** in the top bar to join \(kst.selectedRoom.title) and receive live messages.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    } else {
                        Text("No Messages in \(kst.selectedRoom.shortName)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Connected to \(kst.selectedRoom.title). Waiting for incoming DX spots and chat messages...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            let displayedMessages = filteredMessages
                            ForEach(Array(displayedMessages.enumerated()), id: \.element.id) { index, msg in
                                // Date divider if day changed
                                if shouldShowDateDivider(messages: displayedMessages, at: index) {
                                    dateDivider(for: msg.timestamp)
                                }

                                messageCard(msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(14)
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
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var filteredMessages: [ON4KSTMessage] {
        if showOnlyDirected {
            let myCall = (appState.activeStationProfile?.callsign ?? "").uppercased()
            return kst.messages.filter { $0.isDirected || $0.recipient?.uppercased() == myCall || $0.text.localizedCaseInsensitiveContains(myCall) }
        }
        return kst.messages
    }

    // MARK: - Date Divider

    private func shouldShowDateDivider(messages: [ON4KSTMessage], at index: Int) -> Bool {
        guard index < messages.count else { return false }
        if index == 0 { return true }
        let prev = messages[index - 1].timestamp
        let curr = messages[index].timestamp
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return !calendar.isDate(prev, inSameDayAs: curr)
    }

    private func dateDivider(for date: Date) -> some View {
        HStack {
            VStack { Divider() }
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(formattedDateHeader(date))
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            VStack { Divider() }
        }
        .padding(.vertical, 6)
    }

    private func formattedDateHeader(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        if calendar.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "EEEE, dd MMMM yyyy"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return "Today — " + f.string(from: date) + " UTC"
        } else if calendar.isDateInYesterday(date) {
            let f = DateFormatter()
            f.dateFormat = "EEEE, dd MMMM yyyy"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return "Yesterday — " + f.string(from: date) + " UTC"
        } else {
            let f = DateFormatter()
            f.dateFormat = "EEEE, dd MMMM yyyy 'UTC'"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f.string(from: date)
        }
    }

    // MARK: - Message Card

    private func messageCard(_ msg: ON4KSTMessage) -> some View {
        let isMe = msg.sender.uppercased() == (appState.activeStationProfile?.callsign ?? "").uppercased()

        return VStack(alignment: .leading, spacing: 6) {
            // Header: Sender, Recipient, Badges, Full Date & Time
            HStack(spacing: 8) {
                // Sender Badge
                Button {
                    selectedRecipient = msg.sender
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(msg.isSpot ? Color.orange : (msg.isDirected ? Color.purple : (isMe ? Color.green : Color.blue)))
                            .frame(width: 6, height: 6)
                        Text(msg.sender)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (msg.isSpot ? Color.orange : (msg.isDirected ? Color.purple : (isMe ? Color.green : Color.blue))).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .foregroundColor(msg.isSpot ? .orange : (msg.isDirected ? .purple : (isMe ? .green : .blue)))
                }
                .buttonStyle(.plain)
                .help("Click to reply directly to \(msg.sender)")

                // Directed Recipient Arrow
                if let recip = msg.recipient, !recip.isEmpty, recip != "ALL" {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(recip)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }

                if msg.isSpot {
                    Text("DX SPOT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Spacer()

                // Explicit Date & Time UTC stamp
                HStack(spacing: 4) {
                    Text(formattedTime(msg.timestamp))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                    Text("· " + formattedShortDate(msg.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }

            // Message Body Text
            Text(msg.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(2)

            // Detected Frequency & Sked Action Toolbar
            if let freq = msg.detectedFrequencyMHz {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .foregroundColor(.indigo)
                        Text(String(format: "%.3f MHz", freq))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.indigo)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                    Button {
                        qsyToFrequency(freq, callsign: msg.sender)
                    } label: {
                        Label("QSY Radio", systemImage: "dial.low.fill")
                            .font(.system(size: 10.5, weight: .bold))
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
                        Label("Log Draft", systemImage: "square.and.pencil")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Spacer()

                    Button {
                        selectedRecipient = msg.sender
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(msg.isDirected ? Color.purple.opacity(0.06) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    msg.isDirected ? Color.purple.opacity(0.35) : (msg.isSpot ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.12)),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Right: Online Active Operators Sidebar

    private var usersSidebar: some View {
        VStack(spacing: 0) {
            // Search Box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter by callsign, grid...", text: $userSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HStack {
                Text("ONLINE STATIONS (\(filteredUsers.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Bearing / Dist")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(filteredUsers) { user in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button {
                            selectedRecipient = user.callsign
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(user.callsign)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to select \(user.callsign) as recipient")

                        Spacer()

                        if !user.locator.isEmpty {
                            Text(user.locator)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    if let dist = user.distanceKm, let bearing = user.bearingDeg {
                        HStack(spacing: 6) {
                            Text("\(Int(dist)) km")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("• \(Int(bearing))° \(GeodesicMath.compassCardinal(for: bearing))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)

                            Spacer()

                            Button {
                                rotator.turnTo(azimuth: bearing)
                                actionBanner = "Antenna turning to \(user.callsign) at \(Int(bearing))°"
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "location.north.line.fill")
                                        .font(.system(size: 9))
                                    Text("Aim")
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("Rotate beam antenna to \(user.callsign) (\(Int(bearing))°)")
                        }
                    }

                    if !user.extraInfo.isEmpty {
                        Text(user.extraInfo)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
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
            $0.locator.localizedCaseInsensitiveContains(userSearchText) ||
            $0.extraInfo.localizedCaseInsensitiveContains(userSearchText)
        }
    }

    // MARK: - Bottom: Composer Bar & Quick CQ Templates

    private var composerBar: some View {
        VStack(spacing: 8) {
            // Quick CQ / Sked Action Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickCQButton("CQ 50.313 FT8", freq: "50.313", mode: "FT8")
                    quickCQButton("CQ 70.154 CW", freq: "70.154", mode: "CW")
                    quickCQButton("CQ 144.174 FT8", freq: "144.174", mode: "FT8")
                    quickCQButton("CQ 144.200 SSB", freq: "144.200", mode: "SSB")
                    quickCQButton("CQ 432.200 SSB", freq: "432.200", mode: "SSB")
                    quickCQButton("1.2 GHz Tropo Sked?", freq: "1296.200", mode: "SSB")
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                // Recipient Dropdown / Selector
                Picker("To:", selection: $selectedRecipient) {
                    Text("📢 ALL (Public Room)").tag("ALL")
                    Divider()
                    ForEach(kst.onlineUsers) { u in
                        Text("🔒 \(u.callsign)").tag(u.callsign)
                    }
                }
                .frame(width: 175)

                TextField("Type message or sked proposal...", text: $outgoingMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(outgoingMessage.trimmingCharacters(in: .whitespaces).isEmpty || !kst.isConnected)
                .help(kst.isConnected ? "Send message" : "Connect to ON4KST in the top bar first")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func quickCQButton(_ title: String, freq: String, mode: String) -> some View {
        Button {
            guard kst.isConnected else {
                actionBanner = "⚠️ Connect to ON4KST room first before broadcasting CQ"
                return
            }
            kst.sendCQ(frequencyMHz: freq, mode: mode)
            actionBanner = "Broadcasted '\(title)' to \(kst.selectedRoom.shortName)"
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
    }

    private func sendMessage() {
        let text = outgoingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard kst.isConnected else {
            actionBanner = "⚠️ Cannot send message: Not connected to ON4KST. Click Connect above."
            return
        }
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

    private func formattedShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
