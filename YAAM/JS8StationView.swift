//
//  JS8StationView.swift
//  YAAM
//
//  Conversational Chat Workstation for JS8 / JS8Call Digital Mode
//  Features live station activity roster, directed messaging timeline,
//  UTC slot synchronization gauge, multi-speed selector, and 1-click YAAM logging.
//

import AppKit
import SwiftUI

public struct JS8StationView: View {
    @ObservedObject var engine: JS8Engine

    @State private var selectedFilter: String = "ALL"
    @State private var messageInputText: String = ""

    public init(engine: JS8Engine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Top Control Bar & UTC Slot Progress
            topControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)

            // 2. Split Workstation: Station Activity Roster + Chat Timeline
            HStack(spacing: 10) {
                // Left: Active Stations Roster
                stationRosterPanel
                    .frame(width: 250)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)

                // Right: Chat Messages Timeline & Composer
                chatTimelinePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
            }
            .frame(minHeight: 280)
        }
        .padding(10)
    }

    // MARK: - 1. Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Master Start / Stop
            Button {
                if engine.isListening {
                    engine.stopListening()
                } else {
                    engine.startListening()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: engine.isListening ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                    Text(engine.isListening ? "STOP JS8" : "START JS8")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .purple)

            // Speed Selector
            Picker("Speed:", selection: $engine.speed) {
                ForEach(JS8Speed.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            Divider().frame(height: 20)

            // UTC Slot Progress
            HStack(spacing: 6) {
                Text("SLOT:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                ProgressView(value: engine.slotProgress, total: 1.0)
                    .frame(width: 80)
                    .tint(.purple)
                Text(String(format: "%0.1fs", engine.secondsRemaining))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .frame(width: 42)
            }

            Spacer()

            // Simulation Button
            Button {
                engine.toggleSimulation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(engine.isSimulationActive ? .yellow : .secondary)
                    Text(engine.isSimulationActive ? "SIM ON" : "Practice Feed")
                        .font(.caption2.bold())
                }
            }
            .buttonStyle(.bordered)
            .tint(engine.isSimulationActive ? .yellow : .secondary)
        }
    }

    // MARK: - 2. Station Activity Roster Panel

    private var stationRosterPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("ACTIVITY ROSTER (\(engine.stations.count))", systemImage: "person.3.fill")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Divider()

            List(selection: $engine.selectedStation) {
                ForEach(engine.stations) { st in
                    Button {
                        engine.selectedStation = st
                    } label: {
                        HStack(spacing: 6) {
                            Text(st.countryFlag)
                                .font(.body)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(st.callsign)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)

                                HStack(spacing: 4) {
                                    Text(st.grid)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("·")
                                    Text("\(st.snrDb) dB")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(st.snrDb > -10 ? .green : .yellow)
                                }
                            }

                            Spacer()

                            Text("\(Int(st.audioFreqHz)) Hz")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(st)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 3. Chat Timeline Panel

    private var chatTimelinePanel: some View {
        VStack(spacing: 6) {
            // Selected Target Bar
            HStack {
                if let target = engine.selectedStation {
                    HStack(spacing: 6) {
                        Text("DIRECTED TO:")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(target.countryFlag) \(target.callsign)")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(.purple)

                        Button("Log QSO") {
                            engine.logCurrentQSO(target: target.callsign)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                } else {
                    Text("BROADCAST TO: @ALLCALL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Clear Chat") {
                    engine.messages.removeAll()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Divider()

            // Message Scroll Timeline
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(engine.messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: engine.messages.count) { _, _ in
                    if let last = engine.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Message Composer
            HStack(spacing: 8) {
                TextField("Type JS8 directed or broadcast message...", text: $messageInputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        sendCurrentMessage()
                    }

                Button {
                    sendCurrentMessage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("SEND")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(messageInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func chatBubble(_ msg: JS8Message) -> some View {
        HStack {
            if msg.isOutgoing { Spacer() }

            VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(msg.fromCall)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(msg.isOutgoing ? .cyan : .purple)
                    Text("→")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(msg.toCall)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(msg.text)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(msg.isOutgoing ? Color.purple.opacity(0.35) : Color(white: 0.15))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            if !msg.isOutgoing { Spacer() }
        }
    }

    private func sendCurrentMessage() {
        let text = messageInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let target = engine.selectedStation?.callsign ?? "@ALLCALL"
        engine.sendMessage(text: text, to: target)
        messageInputText = ""
    }
}
