//
//  EQSLCardModalView.swift
//  YAAM
//
//  Interactive Graphical eQSL Card Viewer Sheet
//  Displays full-resolution electronic QSL card graphics (.jpg/.png),
//  QSO metadata badges, zoom & pan controls, and Export / Share options.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct EQSLCardModalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eqslService = EQSLService.shared

    public let callsign: String
    public let date: String
    public let time: String
    public let band: String
    public let mode: String
    public let rstSent: String
    public let rstRcvd: String
    public let grid: String

    @State private var image: NSImage?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var zoomScale: CGFloat = 1.0

    @AppStorage("eqslUsername") private var eqslUsername = ""
    @AppStorage("eqslPassword") private var eqslPassword = ""

    public init(
        callsign: String,
        date: String,
        time: String = "00:00",
        band: String = "20M",
        mode: String = "FT8",
        rstSent: String = "599",
        rstRcvd: String = "599",
        grid: String = ""
    ) {
        self.callsign = callsign
        self.date = date
        self.time = time
        self.band = band
        self.mode = mode
        self.rstSent = rstSent
        self.rstRcvd = rstRcvd
        self.grid = grid
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.checkmark.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("eQSL Graphical Card: \(callsign)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("\(date) \(time) UTC · \(band) · \(mode) · \(grid)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if let image {
                        Button {
                            saveImageToDisk(image)
                        } label: {
                            Label("Save Image", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Card Viewer Canvas
            ZStack {
                Color(red: 0.08, green: 0.10, blue: 0.14)
                    .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading eQSL Graphic Card for \(callsign)...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.6), radius: 15, x: 0, y: 8)
                            .padding(24)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundColor(.orange)
                        Text(errorMessage ?? "No graphical eQSL card found on server.")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Verify your eQSL credentials in Settings (⌘,) or check if the sender uploaded a custom card design.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)

                        Button {
                            loadCard()
                        } label: {
                            Label("Retry Download", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(32)
                }
            }
            .frame(minWidth: 680, minHeight: 480)

            Divider()

            // Bottom Status & Metadata Bar
            HStack {
                HStack(spacing: 14) {
                    Label("RST: \(rstSent)/\(rstRcvd)", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Band: \(band)", systemImage: "waveform.path")
                    Label("Mode: \(mode)", systemImage: "tuningfork")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                if image != nil {
                    HStack(spacing: 8) {
                        Button {
                            zoomScale = max(0.6, zoomScale - 0.2)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(zoomScale * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)

                        Button {
                            zoomScale = min(2.5, zoomScale + 0.2)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.plain)

                        Button("Reset") {
                            zoomScale = 1.0
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            loadCard()
        }
    }

    private func loadCard() {
        isLoading = true
        errorMessage = nil

        // Check local cache first
        if let cachedURL = eqslService.cachedCardURL(callsign: callsign, date: date, band: band, mode: mode),
           let cachedImg = NSImage(contentsOf: cachedURL) {
            self.image = cachedImg
            self.isLoading = false
            return
        }

        // Fetch from eQSL API
        Task {
            do {
                let downloadedURL = try await eqslService.downloadCardImage(
                    callsign: callsign,
                    date: date,
                    time: time,
                    band: band,
                    mode: mode,
                    username: eqslUsername,
                    password: eqslPassword
                )
                if let downloadedImg = NSImage(contentsOf: downloadedURL) {
                    self.image = downloadedImg
                } else {
                    self.errorMessage = "Failed to render card image."
                }
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func saveImageToDisk(_ img: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg, .png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "eQSL_\(callsign)_\(date).jpg"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .jpeg, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}
