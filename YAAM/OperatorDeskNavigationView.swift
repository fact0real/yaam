import SwiftUI

extension OperatorDeskDestination {
    var deskShortcut: KeyboardShortcut? {
        switch self {
        case .quickLog: KeyboardShortcut("l", modifiers: .command)
        case .callRoster: KeyboardShortcut("r", modifiers: [.command, .shift])
        case .cwKeyer: KeyboardShortcut("k", modifiers: [.command, .shift])
        case .cwAcademy: KeyboardShortcut("a", modifiers: [.command, .shift])
        case .cwReference: KeyboardShortcut("q", modifiers: [.command, .shift])
        case .cwDecoder: KeyboardShortcut("d", modifiers: [.command, .shift])
        case .globeGrids: KeyboardShortcut("g", modifiers: .command)
        case .signalFootprint: KeyboardShortcut("f", modifiers: [.command, .option])
        case .sixMeter: KeyboardShortcut("6", modifiers: .command)
        case .contest: KeyboardShortcut("4", modifiers: .command)
        case .bandmap: KeyboardShortcut("b", modifiers: [.command, .option])
        case .dxNews: KeyboardShortcut("n", modifiers: [.command, .shift])
        // Command-Shift-S belongs to File > Save As.
        case .logSources: KeyboardShortcut("s", modifiers: [.command, .option, .shift])
        case .qslLabels: KeyboardShortcut("p", modifiers: [.command, .option])
        case .shackClock: KeyboardShortcut("h", modifiers: [.command, .option])
        case .emulator: KeyboardShortcut("e", modifiers: [.command, .option])
        default: nil
        }
    }
}

extension OperatorDeskGroup {
    var tint: Color {
        switch self {
        case .operating: .blue
        case .dxActivity: .teal
        case .radioDigital: .indigo
        case .cw: .orange
        case .contests: .purple
        case .qslData: .green
        }
    }
}

/// Presentation only: all entry points use the same destination catalog.
struct OperatorDeskNavigationView: View {
    let selection: OperatorDeskDestination
    let stationCallsign: String
    let select: (OperatorDeskDestination) -> Void
    let selectGroup: (OperatorDeskGroup) -> Void

    @State private var showingFinder = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(OperatorDeskGroup.allCases) { group in
                    groupButton(group)
                }

                Button { showingFinder.toggle() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 15, weight: .medium))
                        Text("All tools").font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 57, height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Find any Operator Desk tool by name or task")
                .accessibilityIdentifier("operatorDesk.allTools")
                .popover(isPresented: $showingFinder, arrowEdge: .bottom) {
                    OperatorDeskToolFinder(selection: selection) { destination in
                        showingFinder = false
                        select(destination)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selection.group.tint)
                    .frame(width: 3, height: 19)

                // A menu replaces the complete strip when it cannot fit. No hidden off-screen tabs.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        ForEach(selection.group.destinations) { destination in
                            destinationButton(destination)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 2) {
                        ForEach(selection.group.destinations) { destination in
                            destinationButton(destination, compact: true)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    compactDestinationMenu
                }

                Spacer(minLength: 0)

                Label(stationCallsign.isEmpty ? "No station" : stationCallsign,
                      systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 125)
                    .help("Active station")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(selection.group.tint.opacity(0.035))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Operator Desk navigation")
    }

    private func groupButton(_ group: OperatorDeskGroup) -> some View {
        let isSelected = selection.group == group
        return Button {
            guard !isSelected else { return }
            selectGroup(group)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: group.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? group.tint : Color.secondary)
                        .frame(width: 18)
                    Text(group.title)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Spacer(minLength: 0)
                }
                Text(group.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? group.tint.opacity(0.10) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? group.tint.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("\(group.title) — \(group.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("operatorDesk.group.\(group.rawValue)")
    }

    private func destinationButton(_ destination: OperatorDeskDestination, compact: Bool = false) -> some View {
        let isSelected = selection == destination
        return Button { select(destination) } label: {
            Group {
                if compact {
                    Text(destination.title)
                } else {
                    Label(destination.title, systemImage: destination.icon)
                }
            }
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, compact ? 7 : 9)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background(isSelected ? selection.group.tint.opacity(0.10) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(destination.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("operatorDesk.tool.\(destination.rawValue)")
    }

    private var compactDestinationMenu: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(selection.group.destinations) { destination in
                    Button { select(destination) } label: {
                        Label(destination.title, systemImage: selection == destination ? "checkmark" : destination.icon)
                    }
                }
            } label: {
                Label(selection.title, systemImage: selection.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selection.group.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(selection.group.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose a tool in \(selection.group.title)")
            Text(selection.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct OperatorDeskToolFinder: View {
    let selection: OperatorDeskDestination
    let select: (OperatorDeskDestination) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [OperatorDeskDestination] {
        OperatorDeskGroup.allCases.flatMap(\.destinations).filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a tool, mode, or service…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = matches.first { select(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(16)
            Divider()
            ScrollView {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(height: 210)
                } else {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(OperatorDeskGroup.allCases) { group in
                            let destinations = matches.filter { $0.group == group }
                            if !destinations.isEmpty {
                                Label(group.title.uppercased(), systemImage: group.icon)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(group.tint)
                                    .padding(.top, 14)
                                    .padding(.bottom, 5)
                                    .padding(.horizontal, 10)
                                ForEach(destinations) { destination in
                                    Button { select(destination) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: destination.icon)
                                                .frame(width: 22)
                                                .foregroundStyle(group.tint)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(destination.title).font(.system(size: 12, weight: .semibold))
                                                Text(destination.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            if selection == destination {
                                                Image(systemName: "checkmark").foregroundStyle(group.tint)
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == destination ? group.tint.opacity(0.08) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 460)
        }
        .frame(width: 430)
        .onAppear { searchFocused = true }
    }
}
