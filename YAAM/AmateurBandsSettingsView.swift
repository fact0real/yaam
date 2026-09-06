//
//  AmateurBandsSettingsView.swift
//  YAAM
//
//  Created by EP2AES on 8/9/26.
//

import SwiftUI

struct AmateurBandsSettingsView: View {
    @ObservedObject private var settings = AmateurBandSettings.shared
    @State private var searchText = ""

    private var activeCount: Int {
        settings.activeBands.count
    }

    private var coreActiveCount: Int {
        AmateurBandSettings.coreBands.filter { settings.isBandActive($0) }.count
    }

    private var extendedActiveCount: Int {
        AmateurBandSettings.extendedBands.filter { settings.isBandActive($0) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MARK: - Header & Hero Banner
                headerBanner

                // MARK: - Preset Selector Toolbar
                presetsSection

                // MARK: - General Monitoring Options
                optionsSection

                Divider()

                // MARK: - Band Category Sections
                ForEach(AmateurBandCategory.allCases) { category in
                    let categoryBands = AmateurBandSettings.allBands.filter { $0.category == category }
                    let filteredBands = categoryBands.filter { band in
                        searchText.isEmpty ||
                        band.uppercaseName.localizedCaseInsensitiveContains(searchText) ||
                        band.frequencyRange.localizedCaseInsensitiveContains(searchText) ||
                        band.wavelengthDesc.localizedCaseInsensitiveContains(searchText)
                    }

                    if !filteredBands.isEmpty {
                        categorySection(category: category, bands: filteredBands)
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Header Banner
    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("Amateur Radio Bands & Monitoring")
                            .font(.title2.weight(.bold))
                    }
                    Text("Select which amateur radio bands to monitor across Log Tables, Country Bands DXCC matrix, Band Breakdown, and Operator Desk.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter bands...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 130)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }

            // Metric Summary Badges
            HStack(spacing: 8) {
                metricChip(
                    title: "Active Bands",
                    value: "\(activeCount) / 24",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .blue
                )
                metricChip(
                    title: "Core HF & 6M",
                    value: "\(coreActiveCount) of 11",
                    icon: "checkmark.seal.fill",
                    color: coreActiveCount == 11 ? .green : .orange
                )
                metricChip(
                    title: "Extended Bands",
                    value: "\(extendedActiveCount) of 13",
                    icon: "dot.radiowaves.up.forward",
                    color: extendedActiveCount > 0 ? .purple : .secondary
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func metricChip(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(color.opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - Presets Section
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK CONFIGURATION PRESETS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button {
                    settings.resetToCore11Only()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Core 11 Bands (160m – 6m Default)")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .help("Activate only the 11 universally standard amateur radio bands (160m, 80m, 60m, 40m, 30m, 20m, 17m, 15m, 12m, 10m, 6m). Recommended for all HF DXers.")

                Button {
                    settings.enableCorePlusVHFUHF()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)
                        Text("Core + 2M & 70CM")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .help("Activate the 11 core bands plus the two most popular VHF/UHF repeater and weak-signal bands (144 MHz and 430 MHz).")

                Button {
                    settings.enableHFOnly()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe.americas.fill")
                            .foregroundColor(.indigo)
                        Text("HF Only (160m – 10m)")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button {
                    settings.enableAll24Bands()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundColor(.purple)
                        Text("Enable All 24 Bands")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .help("Enable every ITU-allocated amateur band from 2190m (136 kHz) to 1.25cm (24 GHz).")
            }
        }
    }

    // MARK: - Options Section
    private var optionsSection: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $settings.autoIncludeBandsWithQSOs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-include bands with existing QSOs")
                        .font(.system(size: 12, weight: .semibold))
                    Text("If your log contains QSOs on an unselected band (e.g. 2m or 70cm), YAAM will automatically display it in coverage matrices so historical contacts are never hidden.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.4)))
    }

    // MARK: - Category Section
    private func categorySection(category: AmateurBandCategory, bands: [AmateurBandDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundColor(category.accentColor)
                    .font(.system(size: 13, weight: .bold))

                Text(category.rawValue)
                    .font(.headline)

                Text("(\(bands.filter { settings.isBandActive($0.id) }.count) of \(bands.count) active)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                Button(bands.allSatisfy { settings.isBandActive($0.id) } ? "Disable All" : "Enable All") {
                    let allActive = bands.allSatisfy { settings.isBandActive($0.id) }
                    for band in bands {
                        settings.setBand(band.id, enabled: !allActive)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }

            Text(category.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            // Grid of Band Cards
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 235, maximum: 360), spacing: 10)],
                spacing: 10
            ) {
                ForEach(bands) { band in
                    bandCard(band: band, categoryColor: category.accentColor)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Individual Band Card
    private func bandCard(band: AmateurBandDefinition, categoryColor: Color) -> some View {
        let isActive = settings.isBandActive(band.id)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(band.uppercaseName)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(isActive ? .primary : .secondary)

                    if band.isCore {
                        Text("CORE")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.blue))
                    }
                }

                Text(band.wavelengthDesc)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                    .lineLimit(1)

                Text(band.frequencyRange)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.isBandActive(band.id) },
                set: { settings.setBand(band.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isActive
                        ? (band.isCore ? Color.blue.opacity(0.08) : categoryColor.opacity(0.07))
                        : Color(NSColor.controlBackgroundColor).opacity(0.35)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isActive
                        ? (band.isCore ? Color.blue.opacity(0.35) : categoryColor.opacity(0.3))
                        : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
    }
}
