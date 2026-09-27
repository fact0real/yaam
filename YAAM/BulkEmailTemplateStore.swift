//
//  BulkEmailTemplateStore.swift
//  YAAM
//
//  Created for YAAM Amateur Radio Logbook.
//

import SwiftUI
import Combine

struct SavedBulkEmailTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var subject: String
    var body: String
    var isBuiltIn: Bool
    var recommendedFilterHint: String
    var savedFilterCriteria: FilterCriteria?
    var createdDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        subject: String,
        body: String,
        isBuiltIn: Bool = false,
        recommendedFilterHint: String = "",
        savedFilterCriteria: FilterCriteria? = nil,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.body = body
        self.isBuiltIn = isBuiltIn
        self.recommendedFilterHint = recommendedFilterHint
        self.savedFilterCriteria = savedFilterCriteria
        self.createdDate = createdDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SavedBulkEmailTemplate, rhs: SavedBulkEmailTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

final class BulkEmailTemplateStore: ObservableObject {
    static let shared = BulkEmailTemplateStore()
    private let storageKey = "savedBulkEmailTemplatesList_v2"

    @Published var templates: [SavedBulkEmailTemplate] = []

    init() {
        loadTemplates()
    }

    func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedBulkEmailTemplate].self, from: data),
           !decoded.isEmpty {
            var merged = decoded
            for defaultTemplate in Self.defaultTemplates {
                if !merged.contains(where: { $0.id == defaultTemplate.id }) {
                    merged.append(defaultTemplate)
                }
            }
            self.templates = merged
        } else {
            self.templates = Self.defaultTemplates
            saveTemplates()
        }
    }

    func resetToDefaults() {
        self.templates = Self.defaultTemplates
        saveTemplates()
    }

    func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    @discardableResult
    func saveTemplate(
        name: String,
        subject: String,
        body: String,
        filterHint: String = "",
        filterCriteria: FilterCriteria? = nil,
        existingID: UUID? = nil
    ) -> SavedBulkEmailTemplate {
        if let existingID, let idx = templates.firstIndex(where: { $0.id == existingID }) {
            templates[idx].name = name
            templates[idx].subject = subject
            templates[idx].body = body
            if !filterHint.isEmpty {
                templates[idx].recommendedFilterHint = filterHint
            }
            if let filterCriteria {
                templates[idx].savedFilterCriteria = filterCriteria
            }
            saveTemplates()
            return templates[idx]
        } else {
            let newTemplate = SavedBulkEmailTemplate(
                id: UUID(),
                name: name,
                subject: subject,
                body: body,
                isBuiltIn: false,
                recommendedFilterHint: filterHint,
                savedFilterCriteria: filterCriteria,
                createdDate: Date()
            )
            templates.append(newTemplate)
            saveTemplates()
            return newTemplate
        }
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id && !$0.isBuiltIn }
        saveTemplates()
    }

    func duplicateTemplate(id: UUID) -> SavedBulkEmailTemplate? {
        guard let source = templates.first(where: { $0.id == id }) else { return nil }
        let copy = SavedBulkEmailTemplate(
            id: UUID(),
            name: "\(source.name) (Copy)",
            subject: source.subject,
            body: source.body,
            isBuiltIn: false,
            recommendedFilterHint: source.recommendedFilterHint,
            savedFilterCriteria: source.savedFilterCriteria,
            createdDate: Date()
        )
        templates.append(copy)
        saveTemplates()
        return copy
    }

    static var defaultTemplates: [SavedBulkEmailTemplate] {
        var usaFilter = FilterCriteria()
        usaFilter.useCountry = true
        usaFilter.selectedCountries = ["United States", "USA"]
        usaFilter.useConfirmation = true
        usaFilter.confirmationState = "Confirmed (Y)"
        usaFilter.useEmailPresence = true
        usaFilter.emailPresenceState = "Has Email"

        var unconfirmedFilter = FilterCriteria()
        unconfirmedFilter.useConfirmation = true
        unconfirmedFilter.confirmationState = "Unconfirmed (N/Blank)"
        unconfirmedFilter.useEmailPresence = true
        unconfirmedFilter.emailPresenceState = "Has Email"

        return [
            SavedBulkEmailTemplate(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "50 United States Award (SKED)",
                subject: "Question regarding 50 United States Award - {CALLSIGN} de {MY_CALL}",
                body: """
Hello {NAME},

I'm currently working toward the "50 United States Award", and I'm trying to get the required score to qualify. To complete my goal, I just need to connect with people from a few specific states:

- Alaska
- Colorado
- Hawaii
- Kansas
- Montana
- New Mexico
- Oklahoma and
- Wyoming

I was wondering if you happen to know anyone in these states? If you have any friends or contacts there, I would really appreciate it if you could mention this to them, or just share their email addresses so I can reach out to them directly.

Thanks so much in advance for your help! Let me know if anyone comes to mind.

Warm 73,
{MY_CALL}
""",
                isBuiltIn: true,
                recommendedFilterHint: "Country: United States · Confirmed: Y · Has Email",
                savedFilterCriteria: usaFilter
            ),
            SavedBulkEmailTemplate(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "General SKED Request",
                subject: "SKED Request on Amateur Radio - {CALLSIGN} de {MY_CALL}",
                body: """
Hello {NAME},

Thanks for our previous QSO on {BAND}! I would love to arrange another scheduled contact (SKED) with you on the air.

Please let me know if you are available and what bands/modes work best for your operating schedule.

Best 73,
{MY_CALL}
""",
                isBuiltIn: true,
                recommendedFilterHint: "Any Band / Any Mode · Has Email"
            ),
            SavedBulkEmailTemplate(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "QSL Confirmation & Direct Card",
                subject: "QSL Confirmation & Greetings - {CALLSIGN} de {MY_CALL}",
                body: """
Hello {NAME},

Thank you very much for our QSO! I am following up on our contact and would love to exchange QSL confirmations with you via LoTW, QRZ, or direct.

Hope to work you again soon on the bands.

Warm 73,
{MY_CALL}
""",
                isBuiltIn: true,
                recommendedFilterHint: "Unconfirmed Contacts · Has Email",
                savedFilterCriteria: unconfirmedFilter
            ),
            SavedBulkEmailTemplate(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "Grid / Zone Hunter SKED",
                subject: "SKED Request for Grid {GRID} - {CALLSIGN} de {MY_CALL}",
                body: """
Hello {NAME},

I noticed from your station info that you are active from {STATE} in Grid {GRID}. I am actively tracking awards for your zone and would appreciate the chance to coordinate a contact.

If you have specific times when you are active on {BAND}, please let me know.

Thank you & 73,
{MY_CALL}
""",
                isBuiltIn: true,
                recommendedFilterHint: "Filtered by Grid or CQ Zone"
            )
        ]
    }
}

// MARK: - Save Template Modal Sheet
struct SaveBulkEmailTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject var templateStore: BulkEmailTemplateStore

    @State var templateName: String = ""
    @State var subject: String
    @State var bodyText: String
    @State var linkCurrentFilter: Bool
    
    var onSaved: (SavedBulkEmailTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save As New Email Template")
                        .font(.headline)
                    Text("Save this email layout, subject, and filter criteria for quick reuse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Template Name:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                TextField("e.g. 50 US States SKED, DX SKED 20m, CQ Zone 14", text: $templateName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Email Subject:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                TextField("Email Subject", text: $subject)
                    .textFieldStyle(.roundedBorder)
            }

            // Filter Association Card
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Link current active filter criteria to this template", isOn: $linkCurrentFilter)
                    .font(.system(size: 12, weight: .medium))

                if linkCurrentFilter {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Filter Criteria:")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(appState.filterCriteria.isActive ? appState.filterCriteria.activeFilterSummary : "No active filter (all contacts with email)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.06)))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save Template") {
                    let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let saved = templateStore.saveTemplate(
                        name: trimmed,
                        subject: subject,
                        body: bodyText,
                        filterHint: linkCurrentFilter ? appState.filterCriteria.activeFilterSummary : "",
                        filterCriteria: linkCurrentFilter && appState.filterCriteria.isActive ? appState.filterCriteria : nil
                    )
                    onSaved(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}

