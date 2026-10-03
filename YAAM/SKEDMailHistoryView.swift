import SwiftUI

struct SKEDMailHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [EmailHistoryEntry]
    let destinationKey: String
    let initialCallsign: String

    @State private var search = ""
    @State private var currentDestinationOnly = false
    @State private var selectedID: UUID?

    private var visibleEntries: [EmailHistoryEntry] {
        entries.filter { entry in
            if currentDestinationOnly && entry.sked?.destinationKey.caseInsensitiveCompare(destinationKey) != .orderedSame {
                return false
            }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [entry.callsign, entry.email, entry.subject, entry.sked?.recipientName ?? "",
                    entry.sked?.destinationName ?? "", entry.sked?.body ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selected: EmailHistoryEntry? {
        visibleEntries.first(where: { $0.id == selectedID }) ?? visibleEntries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("Sent SKED emails", systemImage: "clock.arrow.circlepath")
                    .font(.title2.bold())
                Text("\(entries.count) delivered")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(18)
            Divider()
            HStack(spacing: 18) {
                TextField("Search callsign, name, email or message", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("Current destination only", isOn: $currentDestinationOnly)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                List {
                    ForEach(visibleEntries) { entry in
                        Button { selectedID = entry.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.callsign).font(.callout.bold())
                                    Spacer()
                                    Text(entry.date.formatted(date: .numeric, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(entry.sked?.recipientName ?? entry.email)
                                    .font(.caption).lineLimit(1)
                                Text(entry.sked?.schedule?.shortDescription ?? "Dates not recorded")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(7)
                            .background(selected?.id == entry.id ? Color.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 335)
                Divider()
                if let selected {
                    detail(selected)
                } else {
                    ContentUnavailableView("No sent SKED emails", systemImage: "envelope.open",
                                           description: Text("Try a different search or show all destinations."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 980, height: 630)
        .onAppear {
            search = initialCallsign
            selectedID = visibleEntries.first?.id
        }
    }

    private func detail(_ entry: EmailHistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.subject).font(.title3.bold()).textSelection(.enabled)
                LabeledContent("Sent", value: entry.date.formatted(date: .long, time: .standard))
                LabeledContent("To", value: "\(entry.sked?.recipientName ?? entry.callsign) · \(entry.callsign) <\(entry.email)>")
                if let details = entry.sked {
                    LabeledContent("From station", value: details.senderCallsign)
                    LabeledContent("Destination", value: details.destinationName)
                    LabeledContent("Requested bands", value: details.bands.joined(separator: ", "))
                    if let schedule = details.schedule {
                        LabeledContent("Planned days", value: schedule.shortDescription)
                        Text(schedule.utcDescription).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Label("No daily availability was proposed.", systemImage: "calendar.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Divider()
                    Text("Message as sent").font(.headline)
                    Text(details.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Label("This email was sent by an earlier YAAM version. Its full text and planned days were not recorded.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
