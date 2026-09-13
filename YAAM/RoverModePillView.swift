//
//  RoverModePillView.swift
//  YAAM
//
//  Top Navigation Bar Status Pill for Rover Mode
//  Displays real-time countdown, active rover grid, and glowing amber indicator.
//

import SwiftUI

public struct RoverModePillView: View {
    @ObservedObject private var roverEngine = RoverModeEngine.shared
    @EnvironmentObject private var appState: AppState
    @State private var isSheetPresented: Bool = false
    @State private var isHovered: Bool = false
    @State private var pulseAnimation: Bool = false

    public init() {}

    private var homeGrid: String {
        appState.activeStationProfile?.grid ?? "LM35"
    }

    public var body: some View {
        Button {
            isSheetPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                // Footprint / Rover Icon
                Image(systemName: roverEngine.isRoverActive ? "shoeprints.fill" : "figure.walk")
                    .font(.system(size: 11, weight: roverEngine.isRoverActive ? .bold : .medium))
                    .foregroundStyle(roverEngine.isRoverActive ? Color.orange : Color.secondary)

                if roverEngine.isRoverActive, let session = roverEngine.activeSession {
                    // Pulsing Status Dot
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6.5, height: 6.5)
                        .scaleEffect(pulseAnimation ? 1.35 : 1.0)
                        .opacity(pulseAnimation ? 0.6 : 1.0)

                    // Target Grid
                    Text("ROVER: \(session.targetGrid)")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.orange)

                    Divider()
                        .frame(height: 11)

                    // Countdown Timer
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)

                        Text(session.formattedRemainingTime)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                } else {
                    // Inactive State: Clean, compact, unobtrusive
                    Text("Rover")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, roverEngine.isRoverActive ? 9 : 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        roverEngine.isRoverActive
                            ? Color.orange.opacity(isHovered ? 0.22 : 0.13)
                            : Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.85 : 0.45)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        roverEngine.isRoverActive
                            ? Color.orange.opacity(0.65)
                            : Color.secondary.opacity(isHovered ? 0.35 : 0.18),
                        lineWidth: roverEngine.isRoverActive ? 1.2 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .help(
            roverEngine.isRoverActive
                ? "Tactical Rover Active: Grid \(roverEngine.activeSession?.targetGrid ?? ""). Click to adjust session or return home."
                : "Tactical Rover Mode: Temporarily project station to another grid for POTA/SOTA or propagation evaluation. Click to activate."
        )
        .sheet(isPresented: $isSheetPresented) {
            RoverModeControlSheet()
                .environmentObject(appState)
        }
    }
}
