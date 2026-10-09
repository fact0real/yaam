//
//  RoverModeControlSheet.swift
//  YAAM
//
//  Tactical Rover & Portable Scout Control Center
//  Interactive configuration sheet with 4-way compass grid stepper,
//  popular geographic presets, session duration timer, and live telemetry diagnostics.
//

import AppKit
import SwiftUI

public struct RoverModeControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var roverEngine = RoverModeEngine.shared

    // Form inputs
    @State private var inputGrid: String = ""
    @State private var sessionLabel: String = ""
    @State private var selectedDuration: RoverSessionDuration = .fourHours
    @State private var stampInOutgoingQSOs: Bool = false
    @State private var showingAddPresetAlert: Bool = false
    @State private var newPresetName: String = ""
    @State private var validationError: String?

    private var homeGrid: String {
        appState.activeStationProfile?.normalizedGrid ?? ""
    }

    private var homeGridLabel: String {
        homeGrid.isEmpty ? TransmitIdentity.locatorNotSetLabel : homeGrid
    }

    private var homeCall: String {
        appState.activeStationProfile?.normalizedCallsign ?? appState.currentStationCallsign
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    if roverEngine.isRoverActive, let session = roverEngine.activeSession {
                        activeSessionBanner(session: session)
                    }

                    gridSelectionSection

                    presetsSection

                    sessionOptionsSection

                    telemetryComparisonCard
                }
                .padding(20)
            }

            Divider()
            footerActions
        }
        .frame(width: 620, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            initializeFields()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Tactical Rover & Portable Scout")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Temporarily project station vantage point without modifying master profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Active Session Banner
    private func activeSessionBanner(session: RoverSession) -> some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)

                    Text("ROVER MODE ACTIVE")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.orange)
                }

                Spacer()

                Text(session.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT ROVER GRID")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(session.targetGrid)
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.orange)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIME REMAINING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(session.formattedRemainingTime)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    roverEngine.extendDuration(seconds: 3600)
                } label: {
                    Label("+1 Hour", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    roverEngine.extendDuration(seconds: 14400)
                } label: {
                    Label("+4 Hours", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    roverEngine.deactivate()
                    dismiss()
                } label: {
                    Label("Return to Home (\(homeGridLabel))", systemImage: "house.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Grid Selection Section with 4-Way Compass Stepper
    private var gridSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Target Maidenhead Grid", systemImage: "maidenhead.locator")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            HStack(alignment: .center, spacing: 18) {
                // Input and Validation
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(TransmitIdentity.locatorPlaceholder, text: $inputGrid)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .frame(width: 170)
                            .onChange(of: inputGrid) { _, newValue in
                                inputGrid = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                validateCurrentGrid()
                            }

                        if let err = validationError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        } else if !inputGrid.isEmpty {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    Text("Enter a 4 or 6 character Maidenhead locator")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 4-Way Compass Stepper Pad
                compassStepperPad
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
    }

    // MARK: - Compass Stepper Pad (N, S, E, W)
    private var compassStepperPad: some View {
        VStack(spacing: 4) {
            Text("GRID STEPPER")
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(.secondary)

            // North
            Button {
                stepDirection(dLon: 0, dLat: 1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 22)
            }
            .buttonStyle(.bordered)
            .help("Step 1 Grid North")

            HStack(spacing: 6) {
                // West
                Button {
                    stepDirection(dLon: -1, dLat: 0)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.bordered)
                .help("Step 1 Grid West")

                // Center Icon
                Image(systemName: "compass.drawing")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)

                // East
                Button {
                    stepDirection(dLon: 1, dLat: 0)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.bordered)
                .help("Step 1 Grid East")
            }

            // South
            Button {
                stepDirection(dLon: 0, dLat: -1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 22)
            }
            .buttonStyle(.bordered)
            .help("Step 1 Grid South")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
    }

    // MARK: - Presets Section
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Popular & Saved Presets", systemImage: "bookmark.fill")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddPresetAlert = true
                } label: {
                    Label("Save Current", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(validationError != nil || inputGrid.isEmpty)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8)], spacing: 8) {
                ForEach(roverEngine.allPresets) { preset in
                    presetChip(preset)
                }
            }
        }
        .sheet(isPresented: $showingAddPresetAlert) {
            addPresetSheet
        }
    }

    private func presetChip(_ preset: RoverPreset) -> some View {
        let isSelected = inputGrid == preset.grid
        return Button {
            inputGrid = preset.grid
            if sessionLabel.isEmpty || sessionLabel.starts(with: "Rover ") {
                sessionLabel = preset.name
            }
            validateCurrentGrid()
            NSSound(named: "Tink")?.play()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.orange : .primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(preset.grid)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if !preset.note.isEmpty {
                            Text("· \(preset.note)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.orange.opacity(0.18) : Color(NSColor.controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session Options Section
    private var sessionOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session Configuration", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                // Duration Picker
                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(RoverSessionDuration.allCases) { dur in
                            Text(dur.title).tag(dur)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Label TextField
                HStack {
                    Text("Label:")
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    TextField("Optional label", text: $sessionLabel)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Stamp in QSOs Toggle
                Toggle(isOn: $stampInOutgoingQSOs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stamp Rover Grid in outgoing new QSOs")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("Overrides MY_GRIDSQUARE during logging while keeping your master profile intact")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
    }

    // MARK: - Live Telemetry Comparison Card
    private var telemetryComparisonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Geodesic & Vantage Diagnostics", systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            if let tel = roverEngine.telemetry(homeGrid: homeGrid, roverGridOverride: inputGrid.isEmpty ? nil : inputGrid) {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        statCell(
                            title: "DISTANCE FROM HOME",
                            value: "\(Int(tel.distanceKm.rounded())) km",
                            subtitle: "(\(Int(tel.distanceMiles.rounded())) miles)",
                            icon: "point.topleft.down.curvedto.point.bottomright.up"
                        )

                        statCell(
                            title: "BEARING FROM HOME",
                            value: "\(Int(tel.bearingDegrees.rounded()))°",
                            subtitle: tel.cardinalDirection,
                            icon: "safari.fill"
                        )

                        statCell(
                            title: "COORDINATES",
                            value: tel.formattedCoordinates,
                            subtitle: "Maidenhead Center",
                            icon: "location.north.circle.fill"
                        )
                    }

                    Divider()

                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 13))

                        Text(tel.daylightSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Home: \(homeCall) (\(homeGridLabel))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
            } else {
                Text("Enter a valid Maidenhead grid to preview distance and solar path telemetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
    }

    private func statCell(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer Actions
    private var footerActions: some View {
        HStack {
            if roverEngine.isRoverActive {
                Button(role: .destructive) {
                    roverEngine.deactivate()
                    dismiss()
                } label: {
                    Label("Disengage Rover Mode", systemImage: "xmark.shield")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                activateRover()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shoeprints.fill")
                    Text(roverEngine.isRoverActive ? "Update Rover Session" : "Activate Rover Mode")
                }
                .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.orange)
            .disabled(validationError != nil || inputGrid.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Helper Methods & Actions
    private func initializeFields() {
        if let session = roverEngine.activeSession, roverEngine.isRoverActive {
            inputGrid = session.targetGrid
            sessionLabel = session.label
            selectedDuration = session.duration
            stampInOutgoingQSOs = session.stampInOutgoingQSOs
        } else {
            inputGrid = ""
            sessionLabel = ""
            selectedDuration = .fourHours
            stampInOutgoingQSOs = false
        }
        validateCurrentGrid()
    }

    private func validateCurrentGrid() {
        let clean = inputGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty {
            validationError = "Grid cannot be empty"
            return
        }
        if GridLocator.fourCharacterGrid(from: clean) == nil {
            validationError = "Invalid Maidenhead format"
            return
        }
        validationError = nil
    }

    private func stepDirection(dLon: Int, dLat: Int) {
        if let stepped = RoverModeEngine.calculateSteppedGrid(from: inputGrid, dLon: dLon, dLat: dLat) {
            inputGrid = stepped
            validateCurrentGrid()
            NSSound(named: "Tink")?.play()
        }
    }

    private func activateRover() {
        guard validationError == nil, !inputGrid.isEmpty else { return }
        let success = roverEngine.activate(
            grid: inputGrid,
            label: sessionLabel.isEmpty ? "Rover \(inputGrid)" : sessionLabel,
            duration: selectedDuration,
            stampInOutgoingQSOs: stampInOutgoingQSOs
        )
        if success {
            // Immediately inform subsystems
            appState.handleRoverModeChanged()
            dismiss()
        }
    }

    // MARK: - Add Preset Sheet
    private var addPresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Location Preset")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Name:")
                    .font(.caption)
                TextField("e.g. Field Day Lake Site", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)

                Text("Grid: \(inputGrid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    showingAddPresetAlert = false
                    newPresetName = ""
                }

                Spacer()

                Button("Save Preset") {
                    roverEngine.saveCustomPreset(name: newPresetName, grid: inputGrid)
                    showingAddPresetAlert = false
                    newPresetName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
