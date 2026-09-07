//
//  RigControlToolbarView.swift
//  YAAM
//
//  Transceiver CAT Control Header & Live Telemetry HUD
//  Renders a high-visibility digital frequency display, animated S-meter,
//  RF power meter, quick band selector, and driver configuration popover.
//

import AppKit
import SwiftUI

public struct RigControlToolbarView: View {
    @ObservedObject var rig = RigControlEngine.shared
    @State private var showConfigPopover = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Connection Status & Model Pill
            Button {
                showConfigPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(rig.isConnected ? Color.green : (rig.isConnecting ? Color.yellow : Color.secondary.opacity(0.4)))
                        .frame(width: 8, height: 8)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(rig.isConnected ? Color.green : Color.secondary)

                    Text(rig.isConnected ? rig.rigModel : "CAT Offline")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(rig.isConnected ? Color.primary : Color.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(rig.isConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(rig.isConnected ? Color.green.opacity(0.35) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConfigPopover) {
                RigConfigPopoverView(rig: rig)
            }

            // Digital LCD Frequency & Band Display
            HStack(spacing: 6) {
                Text(rig.formattedFrequency)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.cyan)

                Text(rig.currentBand)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.cyan.opacity(0.2), in: Capsule())
                    .foregroundStyle(Color.cyan)

                Text(rig.mode)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )

            // Animated LED S-Meter Bar
            HStack(spacing: 4) {
                Text("S")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    ForEach(1...15, id: \.self) { seg in
                        Rectangle()
                            .fill(sMeterSegmentColor(index: seg, current: rig.sMeterValue))
                            .frame(width: 3.5, height: 10)
                            .cornerRadius(1)
                    }
                }

                Text(rig.sMeterDescription)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(rig.sMeterValue > 9 ? Color.red : Color.green)
                    .frame(width: 52, alignment: .leading)
            }

            // RF Power Pill
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.orange)
                Text("\(rig.powerWatts)W")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
        }
    }

    private func sMeterSegmentColor(index: Int, current: Double) -> Color {
        let active = Double(index) <= current
        if !active {
            return Color.secondary.opacity(0.15)
        }
        if index <= 5 {
            return Color.green
        } else if index <= 9 {
            return Color.yellow
        } else {
            return Color.red
        }
    }
}

// MARK: - Rig Configuration Popover

struct RigConfigPopoverView: View {
    @ObservedObject var rig: RigControlEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Transceiver CAT Control", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                if rig.isConnected {
                    Text("ONLINE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green, in: Capsule())
                        .foregroundStyle(Color.black)
                }
            }

            Divider()

            // Driver Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("CAT Driver / Bridge:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Driver", selection: $rig.driverType) {
                    ForEach(RigDriverType.allCases) { driver in
                        Text(driver.rawValue).tag(driver)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: rig.driverType) { _, newType in
                    rig.port = newType.defaultPort
                    rig.connect()
                }
            }

            // Host and Port
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host IP:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $rig.host)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $rig.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            // Quick Band Tune Buttons
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Band Jump (FT8):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(["40M", "20M", "15M", "10M", "6M"], id: \.self) { band in
                        Button(band) {
                            tuneToFT8(band: band)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Connect / Disconnect Action
            HStack {
                Toggle("Auto-Connect on Launch", isOn: $rig.autoConnect)
                    .font(.caption)

                Spacer()

                Button(rig.isConnected ? "Disconnect" : "Connect") {
                    rig.toggleConnection()
                }
                .buttonStyle(.borderedProminent)
                .tint(rig.isConnected ? .red : .blue)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func tuneToFT8(band: String) {
        switch band {
        case "160M": rig.tune(frequencyHz: 1840000, mode: "USB-D")
        case "80M": rig.tune(frequencyHz: 3573000, mode: "USB-D")
        case "40M": rig.tune(frequencyHz: 7074000, mode: "USB-D")
        case "30M": rig.tune(frequencyHz: 10136000, mode: "USB-D")
        case "20M": rig.tune(frequencyHz: 14074000, mode: "USB-D")
        case "17M": rig.tune(frequencyHz: 18100000, mode: "USB-D")
        case "15M": rig.tune(frequencyHz: 21074000, mode: "USB-D")
        case "12M": rig.tune(frequencyHz: 24915000, mode: "USB-D")
        case "10M": rig.tune(frequencyHz: 28074000, mode: "USB-D")
        case "6M": rig.tune(frequencyHz: 50313000, mode: "USB-D")
        default: break
        }
    }
}
