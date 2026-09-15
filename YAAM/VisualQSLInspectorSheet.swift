//
//  VisualQSLInspectorSheet.swift
//  YAAM
//
//  High-Resolution Visual QSL Card & Shack Photo Inspector with QSL Routing Details.
//

import AppKit
import Foundation
import SwiftUI

struct VisualQSLInspectorSheet: View {
    let report: CallIntelligenceReport
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: NSImage? = nil
    @State private var isLoading = true
    @State private var isCopiedAddress = false

    var lookup: CallsignLookupResult? {
        report.lookupData
    }

    var formattedMailingAddress: String {
        guard let lookup else { return "" }
        var lines: [String] = []
        if !lookup.name.isEmpty { lines.append(lookup.name) }
        lines.append(lookup.callsign)
        if !lookup.address1.isEmpty { lines.append(lookup.address1) }
        let cityStateZip = [lookup.qth, lookup.state, lookup.zip]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !cityStateZip.isEmpty { lines.append(cityStateZip) }
        if !lookup.country.isEmpty { lines.append(lookup.country.uppercased()) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Text(report.dxcc.flagEmoji)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(report.callsign)
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                        if let lic = lookup?.licenseClass, !lic.isEmpty {
                            Text(lic.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.18), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }

                    if !report.operatorName.isEmpty {
                        Text(report.operatorName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // Photo Display Frame
                    if let imageURL = lookup?.imageURL, !imageURL.isEmpty {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.4))
                                .frame(minHeight: 280, maxHeight: 380)

                            if let fullImage {
                                Image(nsImage: fullImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 380)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                            } else if isLoading {
                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading high-resolution QSL photo...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(height: 280)
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    Text("Unable to load full photo from \(imageURL)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(height: 280)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    }

                    // Tactical QSL Manager & Routing Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("TACTICAL QSL & ROUTING INTELLIGENCE", systemImage: "envelope.badge.shield.half.filled.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let views = lookup?.profileViews, views > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "eye.fill").font(.system(size: 8.5))
                                    Text("\(views.formatted()) Views")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }

                        if let qslmgr = lookup?.qslManager, !qslmgr.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.rectangle.stack.fill")
                                    .font(.title3)
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("QSL MANAGER / ROUTE:")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text(qslmgr)
                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                        .foregroundStyle(.yellow)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                        }

                        // Delivery Matrix
                        HStack(spacing: 8) {
                            deliveryPill(
                                title: "LoTW",
                                isActive: (lookup?.qslViaLotw == true) || report.isLoTWUser,
                                activeColor: .green,
                                icon: "checkmark.seal.fill"
                            )
                            deliveryPill(
                                title: "eQSL",
                                isActive: lookup?.qslViaEqsl == true,
                                activeColor: .blue,
                                icon: "envelope.fill"
                            )
                            deliveryPill(
                                title: "Direct / Bureau",
                                isActive: lookup?.qslViaMail == true || (lookup?.qslManager.isEmpty == false),
                                activeColor: .orange,
                                icon: "paperplane.fill"
                            )
                        }

                        // Geographic & Awards Badges
                        HStack(spacing: 6) {
                            if let state = lookup?.state, !state.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "map.fill").font(.system(size: 8.5))
                                    Text("State: \(state)")
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.cyan)
                            }

                            if let county = lookup?.county, !county.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "building.2.fill").font(.system(size: 8.5))
                                    Text("County: \(county)")
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.teal)
                            }

                            if let iota = lookup?.iota, !iota.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "water.waves").font(.system(size: 8.5))
                                    Text("IOTA: \(iota)")
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.mint)
                            }

                            if let born = lookup?.birthYear, !born.isEmpty {
                                Text("Born: \(born)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Mailing Address & Copy Box
                        if !formattedMailingAddress.isEmpty {
                            Divider().opacity(0.5)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("POSTAL MAILING ADDRESS (FOR DIRECT SASE):")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(formattedMailingAddress, forType: .string)
                                        withAnimation { isCopiedAddress = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { isCopiedAddress = false }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: isCopiedAddress ? "checkmark" : "doc.on.doc.fill")
                                                .font(.system(size: 9))
                                            Text(isCopiedAddress ? "Copied!" : "Copy for Envelope")
                                                .font(.system(size: 9.5, weight: .bold))
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(isCopiedAddress ? Color.green.opacity(0.2) : Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(isCopiedAddress ? .green : .blue)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(formattedMailingAddress)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 14)
            }

            Divider()

            // Bottom Actions Bar
            HStack {
                Button {
                    if let url = URL(string: "https://www.qrz.com/db/\(report.callsign)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("Open \(report.callsign) on QRZ.com")
                    }
                    .font(.caption.weight(.semibold))
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 500, maxWidth: 560, minHeight: 480, maxHeight: 620)
        .task {
            if let imageURL = lookup?.imageURL, !imageURL.isEmpty {
                fullImage = await VisualQSLPhotoManager.shared.loadImage(from: imageURL)
                isLoading = false
            }
        }
    }

    private func deliveryPill(title: String, isActive: Bool, activeColor: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isActive ? icon : "xmark.circle")
                .font(.system(size: 9))
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .frame(maxWidth: .infinity)
        .background(isActive ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(isActive ? activeColor : .secondary)
    }
}
