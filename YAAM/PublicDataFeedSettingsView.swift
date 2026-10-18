import SwiftUI

struct PublicDataFeedSettingsView: View {
    @ObservedObject private var policy = PublicDataFeedPolicy.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Public data feeds", systemImage: "network")
                .font(.headline)
            Toggle("Allow satellite, NOAA and NASA data downloads", isOn: $policy.isEnabled)
            Text("Downloads start only while their map layers or solar-image pane are visible. Turning this off stops their timers and pending requests. Cached and bundled data remain available. Apple Maps and configured account services have separate connections.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
