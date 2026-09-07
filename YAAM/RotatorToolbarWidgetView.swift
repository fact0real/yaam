//
//  RotatorToolbarWidgetView.swift
//  YAAM
//
//  Antenna Rotator Toolbar HUD & Quick Direction Control
//  Displays live beam azimuth, cardinal direction, rotation status,
//  and presents a direct heading control popover.
//

import SwiftUI

public struct RotatorToolbarWidgetView: View {
    @ObservedObject var engine = RotatorControlEngine.shared
    @State private var inputBearingText: String = ""
    @State private var showPopover: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 5) {
                    // Compass Icon
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(engine.isConnected ? (engine.status.isMoving ? .orange : .cyan) : .secondary)
                        .rotationEffect(.degrees(engine.status.azimuth))
                        .animation(.easeInOut(duration: 0.4), value: engine.status.azimuth)

                    // Azimuth & Cardinal Heading Readout
                    Text(String(format: "%03.0f°", engine.status.azimuth))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(engine.isConnected ? .primary : .secondary)

                    Text(engine.status.cardinalDirection)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(engine.isConnected ? Color.cyan.opacity(0.18) : Color.gray.opacity(0.12))
                        .foregroundStyle(engine.isConnected ? Color.cyan : Color.secondary)
                        .clipShape(Capsule())

                    if engine.status.isMoving {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(engine.status.isMoving ? Color.orange.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Antenna Rotator Control (Hamlib rotctld TCP 4533)")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                rotatorPopoverContent
            }
        }
    }

    private var rotatorPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Antenna Rotator", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)

                Spacer()

                // Connection status pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(engine.isConnected ? Color.green : (engine.isConnecting ? Color.orange : Color.red))
                        .frame(width: 8, height: 8)
                    Text(engine.isConnected ? "Connected" : (engine.isConnecting ? "Connecting" : "Offline"))
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
            }

            Divider()

            // Big Digital Dial
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(String(format: "%03.0f°", engine.status.azimuth))
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                    Text(engine.status.cardinalDirection)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 100)

                VStack(alignment: .leading, spacing: 6) {
                    if let target = engine.status.targetAzimuth {
                        HStack(spacing: 4) {
                            Text("Target:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%03.0f°", target))
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(.orange)
                        }
                    }

                    if engine.status.isMoving {
                        Label("Rotating Beam...", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Label("Heading Locked", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Button(role: .destructive, action: { engine.stop() }) {
                        Label("EMERGENCY STOP", systemImage: "stop.circle.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Quick Cardinal Direction Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK HEADING PRESETS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    presetButton(title: "N (000°)", az: 0.0)
                    presetButton(title: "NE (045°)", az: 45.0)
                    presetButton(title: "E (090°)", az: 90.0)
                    presetButton(title: "SE (135°)", az: 135.0)
                    presetButton(title: "S (180°)", az: 180.0)
                    presetButton(title: "SW (225°)", az: 225.0)
                    presetButton(title: "W (270°)", az: 270.0)
                    presetButton(title: "NW (315°)", az: 315.0)
                }
            }

            // Direct Azimuth Input
            HStack(spacing: 8) {
                TextField("Enter 0 - 360°", text: $inputBearingText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Button("Rotate to Bearing") {
                    if let az = Double(inputBearingText) {
                        engine.setAzimuth(az)
                        inputBearingText = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(inputBearingText.isEmpty || Double(inputBearingText) == nil)
            }

            Divider()

            // Server Connection Details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hamlib rotctld")
                        .font(.caption2.bold())
                    Text("\(engine.host):\(engine.port)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(engine.isConnected ? "Disconnect" : "Connect") {
                    engine.toggleConnection()
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func presetButton(title: String, az: Double) -> some View {
        Button(action: { engine.setAzimuth(az) }) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
}
