import SwiftUI

struct NextCreditContent: View {
    let suggestions: [NextCreditSuggestion]
    let isLoading: Bool
    @Binding var countryBand: Double
    @Binding var grid: Double
    @Binding var award: Double
    @Binding var likelihood: Double
    @Binding var operational: Double
    let done: () -> Void
    let review: (UUID) -> Void
    @State var prioritiesExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Credit").font(.title2.bold())
                    Text("Prioritize your unconfirmed contacts").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { done() }
            }
            Text("Each credit is counted once across this queue. Scores are priorities, not probabilities. Review a contact before taking action; nothing is sent automatically.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Adjust priorities", isExpanded: $prioritiesExpanded) {
                VStack {
                    priority("Country-band", value: $countryBand)
                    priority("Grid", value: $grid)
                    priority("Award milestones", value: $award)
                    priority("Confirmation evidence", value: $likelihood)
                    priority("Follow-up effort & age", value: $operational)
                    Text("Award milestones cover DXCC countries, US states and CQ zones. Provider-specific award rules may differ. Route availability and prior confirmations are heuristic evidence only.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reset priorities") { countryBand = 5; grid = 3; award = 4; likelihood = 2; operational = 1 }
                }.padding(.top, 8)
            }
            if isLoading {
                ProgressView("Ranking contacts…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if suggestions.isEmpty {
                ContentUnavailableView("No follow-up priorities", systemImage: "checkmark.seal", description: Text("There are no eligible unconfirmed contacts with a positive score under these priorities."))
            } else {
                Text("Top \(suggestions.count) suggestions · active station log").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { offset, item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(offset + 1). \(item.contact.call)").font(.headline.monospaced())
                                    Text("\(item.contact.band.uppercased()) · \(item.contact.country)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(item.score, format: .number.precision(.fractionLength(1))).monospacedDigit().font(.headline)
                                    Button("Review QSO") { review(item.id) }
                                }
                                ForEach(item.reasons, id: \.self) { Text("• " + $0).font(.caption) }
                                Text(item.likelihood).font(.caption).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(20).frame(minWidth: 620, minHeight: 460)
    }
    private func priority(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: value, in: 0...10, step: 1)
            Text(value.wrappedValue, format: .number.precision(.fractionLength(0))).monospacedDigit().frame(width: 24)
        }
    }
}
