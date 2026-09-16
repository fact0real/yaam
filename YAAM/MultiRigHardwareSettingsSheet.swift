//
//  MultiRigHardwareSettingsSheet.swift
//  YAAM
//
//  Dedicated Hardware Configuration Sheet for an individual transceiver slot
//  within the Multi-Rig FT8 Cluster.
//

import SwiftUI
import CoreAudio
import FT8808Engine

struct MultiRigHardwareSettingsSheet: View {
    @ObservedObject var slot: MultiRigSlot
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var availablePorts: [String] = []
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var outputDevices: [AudioInputDevice] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Hardware Settings: \(slot.name)", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Form {
                Section("Slot Profile") {
                    TextField("Slot Name / Label", text: $slot.name)
                    Picker("Transceiver Driver", selection: $slot.driverType) {
                        ForEach(RadioDriverType.allCases) { driver in
                            Label(driver.rawValue, systemImage: driver.icon).tag(driver)
                        }
                    }
                    Picker("FT8 Band Preset", selection: Binding(
                        get: {
                            FT8BandPreset.common.first(where: { $0.frequencyHz == slot.dialFrequencyHz }) ?? FT8BandPreset.common[5]
                        },
                        set: { newPreset in
                            slot.setBandPreset(newPreset)
                        }
                    )) {
                        ForEach(FT8BandPreset.common) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                }

                if slot.driverType == .icomLAN {
                    Section("Direct Icom LAN Network Settings (UDP)") {
                        TextField("Radio IP / Hostname", text: $slot.icomHost)
                        TextField("Control Port", value: $slot.icomPort, format: .number)
                        TextField("Username", text: $slot.icomUsername)
                        SecureField("Password", text: $slot.icomPassword)
                        Picker("Transceiver Model", selection: $slot.icomModel) {
                            ForEach(IcomNetworkModel.allCases) { model in
                                Text(model.rawValue).tag(model)
                            }
                        }
                        Text("CI-V Address: 0x\(String(format: "%02X", slot.icomModel.civAddress)) | Network Ports: UDP \(slot.icomPort) (Ctrl), \(slot.icomPort + 1) (CI-V/Audio), \(slot.icomPort + 2) (Scope)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if slot.driverType == .coreAudioRigctld {
                    Section("Hamlib rigctld Network CAT Settings") {
                        TextField("rigctld Host", text: $slot.rigctldHost)
                        TextField("rigctld TCP Port", value: $slot.rigctldPort, format: .number)
                        Text("Connects via Hamlib TCP network daemon (default port: 4532)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if slot.driverType == .transceiverEmulator {
                    Section("Internal Transceiver Emulator (NTE)") {
                        Text("Connects directly to the built-in Network-Attached Transceiver Emulator via CI-V LAN UDP on 127.0.0.1:50001 or Hamlib on TCP 4532 with synthetic RF signals.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Serial CAT Port Settings") {
                        HStack {
                            Picker("Serial Port", selection: $slot.serialPort) {
                                Text("Auto-Detect / Select Port").tag("")
                                ForEach(availablePorts, id: \.self) { port in
                                    Text(port).tag(port)
                                }
                            }
                            Button(action: refreshSerialPorts) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                        }
                        Picker("Baud Rate", selection: $slot.baudRate) {
                            Text("9600 (TX-500 default)").tag(9600)
                            Text("19200 (IC-7300 default)").tag(19200)
                            Text("38400").tag(38400)
                            Text("115200 (High-Speed CI-V)").tag(115200)
                        }
                    }
                }

                if slot.driverType != .icomLAN && slot.driverType != .transceiverEmulator {
                    Section("CoreAudio Soundcard Routing") {
                        Picker("Audio Input (RX Stream)", selection: $slot.audioInputDeviceUID) {
                            Text("System Default Input").tag("")
                            ForEach(inputDevices, id: \.uid) { dev in
                                Text("\(dev.name)").tag(dev.uid)
                            }
                        }
                        Picker("Audio Output (TX Modulation)", selection: $slot.audioOutputDeviceUID) {
                            Text("System Default Output").tag("")
                            ForEach(outputDevices, id: \.uid) { dev in
                                Text("\(dev.name)").tag(dev.uid)
                            }
                        }
                        Text("Select the specific USB Audio CODEC for this transceiver to prevent audio cross-talk between rigs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            refreshSerialPorts()
            refreshAudioDevices()
        }
    }

    private func refreshSerialPorts() {
        var ports: [String] = []
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: "/dev") {
            for item in items where item.hasPrefix("cu.") {
                ports.append("/dev/\(item)")
            }
        }
        availablePorts = ports.sorted()
    }

    private func refreshAudioDevices() {
        inputDevices = AudioDevices.inputDevices()
        outputDevices = AudioDevices.outputDevices()
    }
}
