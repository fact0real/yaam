import SwiftUI

struct StatisticsDXCCIssuesView: View {
    let issues: [DXCCStatisticsSummary.Issue]
    let records: [QSORecordModel]
    let onShowInLog: (QSORecordModel) -> Void
    @Environment(\.dismiss) private var dismiss

    private var recordsByID: [UUID: QSORecordModel] {
        Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let indexed = recordsByID
        VStack(alignment: .leading, spacing: 12) {
            Text("Review DXCC identities").font(.title3.bold())
            Text("A recorded DXCC code takes precedence over a conflicting country name. Unresolved contacts stay outside DXCC totals. Original ADIF values are retained; review the actual contact before editing.")
                .font(.callout).foregroundStyle(.secondary)
            List(issues) { issue in
                if let record = indexed[issue.id] {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record["CALL"]).font(.headline.monospaced())
                            Text(record["QSO_DATE"]).font(.caption)
                            Spacer()
                            Button("Show in Log") { dismiss(); onShowInLog(record) }
                        }
                        Text(issue.reason).font(.caption).foregroundStyle(.orange)
                        Text("Recorded country: \(record["COUNTRY"].isEmpty ? "—" : record["COUNTRY"]) · DXCC: \(record["DXCC"].isEmpty ? "—" : record["DXCC"]) · Used: \(LogDXCCEntity.resolve(record.fields).entity?.name ?? "Unresolved / no entity")")
                            .font(.caption).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 380)
    }
}
