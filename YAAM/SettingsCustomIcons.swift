//
//  SettingsCustomIcons.swift
//  YAAM
//
//  Custom vector brand and intelligent badge icons for Settings & Tools.
//

import SwiftUI
import AppKit

// MARK: - Lab599 Official Brand Logo View
struct Lab599LogoView: View {
    var height: CGFloat = 16

    var body: some View {
        Image("lab599_logo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

// MARK: - Busted Callsign Intelligence & Verification Icon View
struct BustedCallsignIconView: View {
    var size: CGFloat = 16
    var isSelected: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Verification Shield with high-contrast Checkmark
            Image(systemName: "checkmark.shield.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Color.white,
                    isSelected ? Color.accentColor : Color.secondary
                )
                .font(.system(size: size, weight: .semibold))

            // Amber Detection / Alert Badge in corner
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.orange)
                .font(.system(size: size * 0.58, weight: .heavy))
                .offset(x: size * 0.22, y: -size * 0.16)
        }
        .frame(width: size * 1.15, height: size)
    }
}
