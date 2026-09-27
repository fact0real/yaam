//
//  FilterSheetView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

struct FilterSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempCriteria = FilterCriteria()
    @State private var countrySearchText = ""

    var availableBands: [String] {
        ["All"] + AmateurBandSettings.shared.orderedActiveBands().map { $0.uppercased() }
    }
    let availableModes = ["All", "FT8", "FT4", "CW", "SSB", "FM", "AM", "RTTY", "PSK31", "JS8", "DIGI", "VARAFM", "MSK144"]
    let continents = ["AF", "AN", "AS", "EU", "NA", "OC", "SA"]

    private var filteredCountries: [String] {
        let query = countrySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.availableCountries }

        return appState.availableCountries.filter { country in
            country.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header Bar
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("YAAM Advanced Filters")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding(.top, 12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 14) {
                    // Date Filter Card
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use Date Filter", isOn: $tempCriteria.useDate)
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            DatePicker("From:", selection: $tempCriteria.startDate, displayedComponents: .date)
                                .disabled(!tempCriteria.useDate)
                            DatePicker("To:", selection: $tempCriteria.endDate, displayedComponents: .date)
                                .disabled(!tempCriteria.useDate)
                        }

                        Label("After Apply Filters, visible matches receive a temporary UTC row number, newest first. The number is not a database ID and disappears after Reset Filters.", systemImage: "clock.arrow.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // Country Multi-Select Filter Card with Flags
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Toggle("Filter by Countries", isOn: $tempCriteria.useCountry)
                                .font(.headline)

                            Spacer()

                            Text("\(tempCriteria.selectedCountries.count) selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if tempCriteria.useCountry {
                            HStack(spacing: 8) {
                                TextField("Search countries...", text: $countrySearchText)
                                    .textFieldStyle(.roundedBorder)

                                Button("Select Shown") {
                                    tempCriteria.selectedCountries.formUnion(filteredCountries)
                                }
                                .disabled(filteredCountries.isEmpty)

                                Button("Clear") {
                                    tempCriteria.selectedCountries.removeAll()
                                }
                                .disabled(tempCriteria.selectedCountries.isEmpty)
                            }

                            // Selected Countries Flags Preview Bar
                            if !tempCriteria.selectedCountries.isEmpty {
                                HStack(spacing: 6) {
                                    Text("Selected:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(Array(tempCriteria.selectedCountries).sorted(), id: \.self) { c in
                                                Button {
                                                    tempCriteria.selectedCountries.remove(c)
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(countryToFlag(c))
                                                        Text(c)
                                                            .font(.caption2)
                                                            .fontWeight(.bold)
                                                        Image(systemName: "xmark.circle.fill")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.15))
                                                .cornerRadius(6)
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Countries Selector Dropdown Menu / Chips
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                                    ForEach(filteredCountries, id: \.self) { country in
                                        let isSelected = tempCriteria.selectedCountries.contains(country)
                                        Button(action: {
                                            if isSelected { tempCriteria.selectedCountries.remove(country) }
                                            else { tempCriteria.selectedCountries.insert(country) }
                                        }) {
                                            HStack(spacing: 6) {
                                                Text(countryToFlag(country))
                                                Text(country)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                            .padding(6)
                                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 120)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // Band, Mode & Zone Card
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Band", isOn: $tempCriteria.useBand).bold()
                            Picker("", selection: $tempCriteria.band) {
                                ForEach(availableBands, id: \.self) { b in Text(b).tag(b) }
                            }
                            .disabled(!tempCriteria.useBand)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Mode", isOn: $tempCriteria.useMode).bold()
                            Picker("", selection: $tempCriteria.mode) {
                                ForEach(availableModes, id: \.self) { m in Text(m).tag(m) }
                            }
                            .disabled(!tempCriteria.useMode)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("CQ Zone", isOn: $tempCriteria.useZone).bold()
                            TextField("e.g. 20", text: $tempCriteria.zone)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!tempCriteria.useZone)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                    }
                    
                    // Callsign & Operator Card
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Callsign", isOn: $tempCriteria.useCallsign).bold()
                            TextField("Callsign search...", text: $tempCriteria.callsign)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!tempCriteria.useCallsign)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Operator", isOn: $tempCriteria.useOperator).bold()
                            TextField("Operator search...", text: $tempCriteria.operatorStation)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!tempCriteria.useOperator)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                    }
                    
                    // Email Address Availability Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Filter by Email Address", isOn: $tempCriteria.useEmailPresence)
                                .font(.headline)

                            Spacer()

                            if tempCriteria.useEmailPresence {
                                let withEmailCount = appState.callsignsWithEmailCount
                                Text(tempCriteria.emailPresenceState == "Has Email" ? "\(withEmailCount) with email" : "Without email")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            Picker("", selection: $tempCriteria.emailPresenceState) {
                                Text("Has Email (@)").tag("Has Email")
                                Text("No Email / Missing").tag("No Email")
                            }
                            .pickerStyle(.segmented)
                            .disabled(!tempCriteria.useEmailPresence)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // Confirmation Status Card
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Filter Confirmation / Verification Status", isOn: $tempCriteria.useConfirmation)
                            .font(.headline)
                        
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Method:")
                                    .fixedSize()
                                Picker("", selection: $tempCriteria.confirmationType) {
                                    Text("Any Method").tag("Any Method")
                                    Text("LoTW").tag("LoTW")
                                    Text("eQSL").tag("eQSL")
                                    Text("Paper QSL").tag("Paper QSL")
                                }
                                .disabled(!tempCriteria.useConfirmation)
                            }
                            
                            HStack(spacing: 10) {
                                Text("Status:")
                                    .fixedSize()
                                Picker("", selection: $tempCriteria.confirmationState) {
                                    Text("Confirmed (Y)").tag("Confirmed (Y)")
                                    Text("Unconfirmed (N/Blank)").tag("Unconfirmed (N/Blank)")
                                }
                                .pickerStyle(.segmented)
                                .disabled(!tempCriteria.useConfirmation)
                            }
                            
                            Divider()
                            
                            HStack(spacing: 16) {
                                Toggle("🌟 Today's Confirmed Only", isOn: $tempCriteria.useTodayConfirmed)
                                    .font(.subheadline)
                                
                                Toggle("🌸 Newly Confirmed Only", isOn: $tempCriteria.useNewlyConfirmed)
                                    .font(.subheadline)
                                
                                Toggle("✉️ Has Sent Email", isOn: $tempCriteria.useSentEmail)
                                    .font(.subheadline)
                            }

                            HStack(spacing: 16) {
                                Toggle(isOn: $tempCriteria.useNewBand) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .foregroundColor(.blue)
                                        Text("📡 New Band Tag Only (\(appState.newBandCount))")
                                            .font(.subheadline)
                                    }
                                }
                                .help("Filter contacts with NEW BAND tag (earns a new DXCC band credit for that entity)")
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // Paper QSL Status Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paper QSL Direct Status")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Toggle("QSL_SENT:", isOn: $tempCriteria.useQSLSent)
                            Picker("", selection: $tempCriteria.qslSent) {
                                Text("Yes (Y)").tag("Y")
                                Text("No (N)").tag("N")
                                Text("Blank").tag("Blank")
                            }
                            .pickerStyle(.segmented)
                            .disabled(!tempCriteria.useQSLSent)
                        }
                        
                        HStack(spacing: 12) {
                            Toggle("QSL_RCVD:", isOn: $tempCriteria.useQSLRcvd)
                            Picker("", selection: $tempCriteria.qslRcvd) {
                                Text("Yes (Y)").tag("Y")
                                Text("No (N)").tag("N")
                                Text("Blank").tag("Blank")
                            }
                            .pickerStyle(.segmented)
                            .disabled(!tempCriteria.useQSLRcvd)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // Continent Card
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use Continent Filter", isOn: $tempCriteria.useContinent)
                            .font(.headline)
                        
                        HStack(spacing: 14) {
                            ForEach(continents, id: \.self) { cont in
                                Toggle(cont, isOn: Binding(
                                    get: { tempCriteria.selectedContinents.contains(cont) },
                                    set: { isSelected in
                                        if isSelected { tempCriteria.selectedContinents.insert(cont) }
                                        else { tempCriteria.selectedContinents.remove(cont) }
                                    }
                                ))
                                .disabled(!tempCriteria.useContinent)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 4)
            }
            
            Divider()
            
            // Action Buttons Bar
            HStack {
                Button("Reset Filters") {
                    tempCriteria.reset()
                }
                .foregroundColor(.red)

                Menu {
                    let templatesWithFilters = BulkEmailTemplateStore.shared.templates.filter { $0.savedFilterCriteria != nil }
                    ForEach(templatesWithFilters) { template in
                        if let criteria = template.savedFilterCriteria {
                            Button {
                                tempCriteria = criteria
                                appState.appendLog("Loaded filter criteria from template '\(template.name)': \(criteria.activeFilterSummary)")
                            } label: {
                                Text("\(template.name) (\(criteria.activeFilterSummary))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                        Text("Template Filter")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button {
                    appState.filterCriteria = tempCriteria
                    appState.sortHeader = "QSO_DATE"
                    appState.sortAscending = false
                    appState.appendLog("Applied active filters and opened Bulk Email Dispatcher.")
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appState.showFilteredBulkEmailSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.badge")
                        Text("Apply & Email Contacts")
                    }
                }
                .buttonStyle(.bordered)

                Button("Apply Filters") {
                    appState.filterCriteria = tempCriteria
                    appState.sortHeader = "QSO_DATE"
                    appState.sortAscending = false
                    appState.appendLog("Applied active filters and ordered matching QSOs by UTC date/time (newest first).")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(
            minWidth: 560,
            idealWidth: 700,
            maxWidth: .infinity,
            minHeight: 500,
            idealHeight: 680,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 560, minHeight: 500)
        .onAppear {
            tempCriteria = appState.filterCriteria
        }
    }
}
