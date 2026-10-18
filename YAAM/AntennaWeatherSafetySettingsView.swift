import SwiftUI

// MARK: - Antenna & Station Weather Safety Settings
@MainActor
struct AntennaWeatherSafetySettingsView: View {
    @ObservedObject private var engine: StationWeatherSafetyEngine

    init(engine: StationWeatherSafetyEngine? = nil) {
        self.engine = engine ?? .shared
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Station Weather & Antenna Safety Radar")
                            .font(.headline)
                        Text("Forecast-based weather guidance for station planning and antenna precautions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Master Toggle
                Toggle("Enable Live Atmospheric Radar", isOn: $engine.isEnabled)
                    .font(.body.weight(.medium))

                Text("When enabled, YAAM sends the selected locator centre to api.open-meteo.com immediately, every 20 minutes and when the station or rover location changes. No callsign or logbook is sent. New installations start with weather disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Location shared with Open-Meteo", selection: $engine.locationPrecision) {
                    ForEach(WeatherLocationPrecision.allCases) { precision in
                        Text(precision.title).tag(precision)
                    }
                }
                Text("Approximate mode sends the centre of a 2° longitude × 1° latitude square. Precise mode sends a smaller locator centre and may locate the station within a few kilometres. Approximate forecasts can differ substantially from conditions at your antennas; forecasts do not detect nearby lightning or guarantee safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if engine.isEnabled {
                    // Audio warning toggle
                    Toggle("Voice Alert on Severe Weather / Lightning Threats", isOn: $engine.audioAlertsEnabled)
                        .font(.body)

                    // Wind threshold slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("High Wind Alert Threshold:")
                            Spacer()
                            Text("\(Int(engine.highWindThreshold)) km/h")
                                .font(.body.monospacedDigit().bold())
                        }
                        Slider(value: $engine.highWindThreshold, in: 25...120, step: 5)
                        Text("Triggers warning when wind gusts threaten directional HF Yagi beams or vertical antennas.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Live Status Card
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Station QTH:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(engine.resolvedGrid.isEmpty ? "No Grid Set" : engine.resolvedGrid)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Forecast classification:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(engine.currentTelemetry == nil ? Color.secondary : engine.threatLevel.color)
                                    .frame(width: 8, height: 8)
                                Text(engine.currentTelemetry == nil ? "No forecast" : engine.threatLevel.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(engine.currentTelemetry == nil ? Color.secondary : engine.threatLevel.color)
                            }
                        }

                        Spacer()

                        Button {
                            Task {
                                await engine.refresh()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(engine.isFetching)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }

                // Audio Test Button
                HStack {
                    Button {
                        engine.speak(message: "Warning. Severe lightning or thunderstorm hazard detected at your station locator. Disconnect antenna coaxial cables immediately.")
                    } label: {
                        Label("Test Voice Warning Announcement", systemImage: "speaker.wave.2.fill")
                    }
                    .controlSize(.small)

                    Spacer()

                    Text("Weather telemetry powered by Open-Meteo REST API (No API key needed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}
