import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SKEDDirectoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var countryISO = "ir"
    @State private var category = "qso"
    @State private var refreshID = 0
    @State private var directory: SKEDDirectory?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var notice: String?

    private var countries: [QRZCountrySummary] {
        let available = appState.qrzRankCountries
            .filter { $0.iso.count == 2 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !available.isEmpty { return available }
        return Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.compactMap { iso -> QRZCountrySummary? in
            guard let name = Locale(identifier: "en_US").localizedString(forRegionCode: iso) else { return nil }
            return QRZCountrySummary(iso: iso.lowercased(), name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let directory {
                        summary(directory)
                        if directory.operators.isEmpty {
                            ContentUnavailableView("No operators found", systemImage: "antenna.radiowaves.left.and.right.slash",
                                                   description: Text("Try another country or ranking category."))
                                .frame(maxWidth: .infinity, minHeight: 250)
                        } else {
                            operatorTable(directory)
                        }
                    } else if isLoading {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text("Loading the top 19 SKED contacts…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        ContentUnavailableView("Directory unavailable", systemImage: "wifi.exclamationmark",
                                               description: Text("Refresh to try the SKED service again."))
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(22)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear { appState.fetchQRZRankCountries() }
        .task(id: "\(countryISO)-\(category)-\(refreshID)") { await load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 48, height: 48)
                .background(.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("SKED Directory")
                    .font(.title2.weight(.bold))
                Text("Top 19 operators by confirmed activity · QRZ Rank")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filters
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 10) {
                filters
                actions
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Country", selection: $countryISO) {
                ForEach(countries) { country in
                    Text("\(flagForCountryIso(country.iso)) \(country.name) (\(country.iso.uppercased()))")
                        .tag(country.iso.lowercased())
                }
            }
            .frame(width: 265)

            Picker("Rank by", selection: $category) {
                Text("Confirmed QSOs").tag("qso")
                Text("DXCC countries").tag("countries")
                Text("Band slots").tag("band")
            }
            .frame(width: 235)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.down")
            }
            .disabled(directory?.operators.isEmpty != false)

            Button {
                if let emails = directory?.allEmails, !emails.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(emails, forType: .string)
                    notice = "Copied \(directory?.emailCount ?? 0) email addresses."
                }
            } label: {
                Label("Copy all emails", systemImage: "doc.on.doc")
            }
            .disabled(directory?.allEmails.isEmpty != false)

            Button {
                refreshID += 1
            } label: {
                Label("Sync QRZ", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isLoading)
            .help("Refresh rankings and look up missing contact details on QRZ")
        }
    }

    private func summary(_ directory: SKEDDirectory) -> some View {
        HStack(spacing: 16) {
            Text(flagForCountryIso(directory.countryISO))
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 3) {
                Text(directory.countryName)
                    .font(.title3.weight(.bold))
                Text("\(directory.operators.count) ranked operators")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(directory.emailCount) / \(directory.operators.count)")
                    .font(.headline.monospacedDigit())
                Text("emails available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.accentColor.opacity(0.18)))
    }

    private func operatorTable(_ directory: SKEDDirectory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("#").frame(width: 35, alignment: .leading)
                Text("CALLSIGN").frame(width: 110, alignment: .leading)
                Text("OPERATOR").frame(maxWidth: .infinity, alignment: .leading)
                Text("EMAIL").frame(maxWidth: .infinity, alignment: .leading)
                Text(category == "qso" ? "QSOS" : category == "countries" ? "DXCC" : "BANDS")
                    .frame(width: 86, alignment: .trailing)
                Text("CONTACT").frame(width: 86, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            ForEach(directory.operators) { item in
                HStack(spacing: 12) {
                    Text(String(item.rank))
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .leading)
                    Text(item.callsign)
                        .fontWeight(.semibold)
                        .foregroundStyle(.cyan)
                        .frame(width: 110, alignment: .leading)
                    Text(item.name ?? "Name unavailable")
                        .foregroundStyle(item.name == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.validEmail ?? "Not available")
                        .foregroundStyle(item.validEmail == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.score.map { $0.formatted() } ?? "—")
                        .monospacedDigit()
                        .frame(width: 86, alignment: .trailing)
                    Button("Email") { openEmail(item) }
                        .buttonStyle(.bordered)
                        .disabled(item.validEmail == nil)
                        .frame(width: 86, alignment: .trailing)
                }
                .font(.callout)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
        .overlay(alignment: .bottomLeading) {
            if let notice {
                Text(notice)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        notice = nil
        directory = nil
        do {
            let token = CredentialVault.value(for: .qrzRankAPIToken)
            let result = try await SKEDDirectoryService.shared.fetch(
                countryISO: countryISO, category: category, enrich: true,
                token: token, userAgent: "YAAM-macOS/\(appState.currentVersion)"
            )
            guard !Task.isCancelled else { return }
            directory = result
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openEmail(_ item: SKEDOperator) {
        guard let email = item.validEmail else { return }
        if let prepared = item.mailto,
           let components = URLComponents(url: prepared, resolvingAgainstBaseURL: false),
           components.scheme?.lowercased() == "mailto",
           components.path.caseInsensitiveCompare(email) == .orderedSame {
            NSWorkspace.shared.open(prepared)
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "SKED request — \(item.callsign)")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func exportCSV() {
        guard let directory, !directory.operators.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export SKED directory"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SKED_\(directory.countryISO.uppercased())_top19_\(category).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try directory.csv.write(to: url, options: .atomic)
            notice = "CSV saved to \(url.lastPathComponent)."
        } catch {
            errorMessage = "Could not save CSV: \(error.localizedDescription)"
        }
    }
}
