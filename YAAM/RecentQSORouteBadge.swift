import SwiftUI

struct RecentQSORouteBadge: View {
    let source: String
    let destination: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "location.north.line.fill")
                .font(.title3.bold()).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("LATEST CONTACT · WITHIN 15 MIN")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(source)
                    Image(systemName: "arrow.right").foregroundStyle(.teal)
                    Text(destination)
                }
                .font(.system(.callout, design: .monospaced).bold())
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.teal.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Latest contact, from \(source) to \(destination), within the last 15 minutes")
    }
}
