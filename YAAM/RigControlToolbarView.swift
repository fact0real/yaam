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

                    Text(rig.statusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(rig.isConnected ? Color.primary : Color.secondary)

                    // flrig: a release of PTT that could not be confirmed. The text is in the popover and in the help tag.
                    if rig.flrigPTTWarning != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }

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
            .help(rig.flrigPTTWarning.map { Text(verbatim: $0) } ?? Text("Configure Transceiver CAT Control"))
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
        VStack(alignment: .leading, spacing: 16) {
            // Header with Live Connection Badge
            HStack(alignment: .center) {
                Label("Transceiver CAT Control", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if rig.isConnected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(rig.rigModel.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text("OFFLINE")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            Divider()

            // Protocol Driver Cards
            VStack(alignment: .leading, spacing: 6) {
                Text("CAT Driver / Bridge Protocol:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        driverCard(
                            title: "Icom USB",
                            subtitle: "CI-V Direct",
                            icon: "radio.fill",
                            driver: .icomUSB
                        )
                        driverCard(
                            title: "Xiegu X6100",
                            subtitle: "USB-C Direct",
                            icon: "radio.fill",
                            driver: .xiegu6100
                        )
                        driverCard(
                            title: "TX-500",
                            subtitle: "USB-C Direct",
                            icon: "bolt.horizontal.fill",
                            driver: .tx500
                        )
                    }
                    HStack(spacing: 8) {
                        driverCard(
                            title: "FX-4CR",
                            subtitle: "USB-C / BT",
                            icon: "antenna.radiowaves.left.and.right",
                            driver: .fx4cr
                        )
                        driverCard(
                            title: "Flrig",
                            subtitle: "XML-RPC (:12345)",
                            icon: "waveform.badge.magnifyingglass",
                            driver: .flrig
                        )
                        driverCard(
                            title: "Hamlib",
                            subtitle: "rigctld (:4532)",
                            icon: "cable.connector",
                            driver: .rigctld
                        )
                        driverCard(
                            title: "Disabled",
                            subtitle: "Manual / Off",
                            icon: "power",
                            driver: .disabled
                        )
                    }
                }
            }

            // Connection Configuration
            if rig.driverType == .icomUSB {
                let icom = IcomUSBRadioDriver.shared
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Icom Model", systemImage: "radio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { icom.model }, set: { icom.model = $0 })) {
                                ForEach(IcomUSBModel.allCases) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Label("Serial Port", systemImage: "cable.connector")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { icom.selectedPort }, set: { icom.selectedPort = $0 })) {
                                if icom.availablePorts.isEmpty {
                                    Text("No ports").tag("")
                                }
                                ForEach(icom.availablePorts, id: \.self) { port in
                                    Text(port.components(separatedBy: "/").last ?? port).tag(port)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }

                        Button {
                            icom.refreshPorts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh serial ports")

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(icom.baudRate) 8N1")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "0x%02X", icom.resolvedCIVAddress))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                    }

                    HStack {
                        if icom.isAudioCodecDetected {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("USB Audio Codec Ready")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.green)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            } else if rig.driverType == .tx500 {
                let tx500 = Lab599TX500Driver.shared
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("USB Serial Port (AD-514/AD-502)", systemImage: "cable.connector")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { tx500.selectedPort }, set: { tx500.selectedPort = $0 })) {
                                if tx500.availablePorts.isEmpty {
                                    Text("No serial ports found").tag("")
                                }
                                ForEach(tx500.availablePorts, id: \.self) { port in
                                    Text(port.components(separatedBy: "/").last ?? port).tag(port)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        }

                        Button {
                            tx500.refreshPorts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh serial ports")

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("9600 8N2")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("Menu 34: TS2000")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Toggle("Preserve DIG Mode (Menu 34=TS2000)", isOn: Binding(get: { tx500.preserveDIGMode }, set: { tx500.preserveDIGMode = $0 }))
                            .font(.caption)
                            .help("Prevents TX-500 from dropping to USB voice mode on transmit (Firmware Bug #1 fix)")

                        Spacer()

                        if tx500.isAudioDeviceDetected {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("AD-508 Audio Ready")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.green)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            } else if rig.driverType == .fx4cr {
                let fx4cr = FX4CRDriver.shared
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // Transport Mode Picker
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Transport Link", systemImage: fx4cr.connectionType == .bluetooth ? "antenna.radiowaves.left.and.right" : "cable.connector")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { fx4cr.connectionType }, set: { fx4cr.connectionType = $0 })) {
                                ForEach(FX4CRConnectionType.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }

                        // Serial Port Picker
                        VStack(alignment: .leading, spacing: 3) {
                            Label(fx4cr.connectionType == .bluetooth ? "Bluetooth Serial Port" : "USB Serial Port", systemImage: "point.filled.topleft.down.curvedto.point.bottomright.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { fx4cr.selectedPort }, set: { fx4cr.selectedPort = $0 })) {
                                if fx4cr.availablePorts.isEmpty {
                                    Text("No matching ports").tag("")
                                }
                                ForEach(fx4cr.availablePorts, id: \.self) { port in
                                    Text(port.components(separatedBy: "/").last ?? port).tag(port)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        Button {
                            fx4cr.refreshPorts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh available serial ports")
                    }

                    HStack {
                        // Protocol Info
                        Text("Kenwood TS-590S • 115200 8N1")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Audio Codec Status
                        if fx4cr.isAudioDeviceDetected {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(fx4cr.detectedAudioDeviceName ?? "Audio Codec Ready")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text(fx4cr.connectionType == .bluetooth ? "BT Audio Not Found" : "CM108AH Not Found")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Hardware Quirk Advisory Notice
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(fx4cr.connectionType == .usb
                             ? "USB-C: Use USB-A adapter & set Radio Menu 'Bluetooth = 0' to avoid UART clash."
                             : "Bluetooth: Set Radio Menu 'Bluetooth = 1' & pair in macOS System Settings.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            } else if rig.driverType == .xiegu6100 {
                let xiegu = Xiegu6100Driver.shared
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Serial Port (DEV Port)", systemImage: "point.filled.topleft.down.curvedto.point.bottomright.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { xiegu.selectedPort }, set: { xiegu.selectedPort = $0 })) {
                                if xiegu.availablePorts.isEmpty {
                                    Text("No serial ports found").tag("")
                                }
                                ForEach(xiegu.availablePorts, id: \.self) { port in
                                    Text(port.components(separatedBy: "/").last ?? port).tag(port)
                                }
                            }
                            .frame(minWidth: 160)
                        }

                        Button {
                            xiegu.refreshPorts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh serial ports")

                        VStack(alignment: .leading, spacing: 4) {
                            Label("CI-V Baud", systemImage: "speedometer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { xiegu.baudRate }, set: { xiegu.baudRate = $0 })) {
                                Text("9600").tag(9600)
                                Text("19200 (Default)").tag(19200)
                                Text("38400").tag(38400)
                                Text("57600").tag(57600)
                                Text("115200").tag(115200)
                            }
                            .frame(width: 130)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Address", systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Text("0x").font(.caption.monospaced()).foregroundColor(.secondary)
                                TextField("A4", text: Binding(get: { xiegu.civAddressHex }, set: { xiegu.civAddressHex = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 45)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }

                    // Audio codec pill
                    HStack(spacing: 8) {
                        Circle()
                            .fill(xiegu.isAudioDeviceDetected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        if xiegu.isAudioDeviceDetected {
                            Text(xiegu.detectedAudioDeviceName ?? "Audio Codec Ready")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Text("USB Audio Not Found (connect to DEV port)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("Connect USB-C cable to DEV port (not HOST). Standard CI-V address: 0xA4, 19200 8N1.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            } else if rig.driverType != .disabled {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Host IP / Address", systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("127.0.0.1", text: $rig.host)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Port", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Port", value: $rig.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 100)
                    }
                }
            }

            // Quick FT8 Band Jumps (All 10 major HF/VHF bands)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Quick Band Jump (FT8 Digital):")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tunes VFO & Sets USB-D")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let bands = ["160M", "80M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M"]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(bands, id: \.self) { band in
                        Button {
                            tuneToFT8(band: band)
                        } label: {
                            Text(band)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Live Connection Status or Error Banner
            if let err = rig.lastError, !rig.isConnected || rig.driverType == .flrig {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else if rig.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    let dest: String = {
                        if rig.driverType == .icomUSB {
                            return IcomUSBRadioDriver.shared.selectedPort.components(separatedBy: "/").last ?? "USB"
                        } else if rig.driverType == .tx500 {
                            return Lab599TX500Driver.shared.selectedPort.components(separatedBy: "/").last ?? "USB"
                        } else if rig.driverType == .fx4cr {
                            let p = FX4CRDriver.shared.selectedPort.components(separatedBy: "/").last ?? "Port"
                            return "\(FX4CRDriver.shared.connectionType.rawValue) (\(p))"
                        } else if rig.driverType == .xiegu6100 {
                            return Xiegu6100Driver.shared.selectedPort.components(separatedBy: "/").last ?? "USB"
                        } else {
                            return "\(rig.host):\(rig.port)"
                        }
                    }()
                    Text(rig.driverType == .flrig ? "\(rig.flrigLink.detail) (\(dest))" : "Connected to \(rig.rigModel) on \(dest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rig.formattedFrequency)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.cyan)
                }
                .padding(8)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Footer Action Strip
            HStack {
                Toggle("Auto-Connect on Launch", isOn: $rig.autoConnect)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                Spacer()

                Button(rig.isConnected || (rig.driverType == .flrig && rig.isConnecting) ? "Disconnect Transceiver" : "Connect Transceiver") {
                    rig.toggleConnection()
                }
                .buttonStyle(.borderedProminent)
                .tint(rig.isConnected ? .red : .accentColor)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func driverCard(title: String, subtitle: String, icon: String, driver: RigDriverType) -> some View {
        let isSelected = rig.driverType == driver
        return Button {
            if rig.driverType != driver { rig.disconnect() }
            rig.driverType = driver
            rig.port = driver.defaultPort
            if driver != .disabled {
                rig.connect()
            } else {
                rig.disconnect()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
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
