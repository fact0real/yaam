//
//  ActivityConsoleView.swift
//  YAAM
//

import AppKit
import SwiftUI

struct ActivityConsoleView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var searchText = ""
    @State private var showingClearConfirmation = false

    private struct ConsoleLine: Identifiable {
        let id: Int
        let text: String
    }

    private var allLines: [ConsoleLine] {
        appState.logText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { ConsoleLine(id: $0.offset, text: String($0.element)) }
    }

    private var visibleLines: [ConsoleLine] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allLines
        }
        return allLines.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            console
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Clear the activity console?",
            isPresented: $showingClearConfirmation
        ) {
            Button("Clear Console", role: .destructive) {
                appState.clearActivityLog()
            }
        } message: {
            Text("This clears the visible session log only. Saved QSOs and audit history are not changed.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text("Activity Console")
                    .font(.headline)
                Text("Import, synchronization, enrichment, and diagnostic events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Find in console", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)

            Button {
                copyVisibleLog()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(visibleLines.isEmpty)

            Button {
                showingClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .padding(14)
    }

    private var console: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(visibleLines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: line.text))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                    .frame(
                        minWidth: max(0, geometry.size.width - 24),
                        alignment: .leading
                    )
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onAppear {
                    scrollToLatest(using: proxy)
                }
                .onChange(of: appState.logText) { _, _ in
                    guard searchText.isEmpty else { return }
                    scrollToLatest(using: proxy)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(searchText.isEmpty
                 ? "\(allLines.count) lines"
                 : "\(visibleLines.count) of \(allLines.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Close") {
                dismissWindow(id: YAAMWindowID.console)
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let lastID = visibleLines.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func copyVisibleLog() {
        let text = visibleLines.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func color(for line: String) -> Color {
        let lowercased = line.lowercased()
        if lowercased.contains("error") || lowercased.contains("failed") {
            return .red
        }
        if lowercased.contains("warning") || lowercased.contains("skipped") {
            return .orange
        }
        if lowercased.contains("complete") || lowercased.contains("saved") {
            return .green
        }
        return .primary
    }
}
