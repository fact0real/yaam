import SwiftUI

struct BandmapProvenanceNotice: View {
    let spotCount: Int
    let includesSimulation: Bool
    let catConnected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(spotCount == 0 ? "No spot data on this band" : "Illustration from \(spotCount) DX spots", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
            Text("Not received RF, signal strength or a measured waterfall history. \(catConnected ? "CAT supplies tuning only." : "Radio CAT is offline.")")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if includesSimulation {
                Label("Includes simulated spots", systemImage: "testtube.2").font(.caption).foregroundStyle(.orange)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
