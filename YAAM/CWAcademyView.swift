//
//  CWAcademyView.swift
//  YAAM
//
//  Interactive CW Learning Academy & Ear-Training Workstation
//  Koch Method 40-level progressive trainer, Farnsworth timing controls,
//  Callsign Sprint contest simulator, real-time accuracy scoring, and streaks.
//

import Combine
import SwiftUI

public struct CWAcademyView: View {
    @ObservedObject private var academy = CWAcademyEngine.shared
    @State private var userInput: String = ""
    @State private var lastResult: (isMatch: Bool, target: String, input: String)? = nil
    @FocusState private var isInputFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            topControlBar
            if academy.mode == .kochLessons {
                kochLevelProgressBanner
            }
            mainPracticeCard
            unlockedAlphabetRack
            statsRibbon
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(12)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 14) {
            // Training Mode Segmented Selector displaying full titles ("Koch Method (Levels 1–40)", etc.)
            HStack(spacing: 2) {
                ForEach(CWTrainingMode.allCases) { mode in
                    let isSelected = academy.mode == mode
                    Button {
                        if academy.mode != mode {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                academy.mode = mode
                                lastResult = nil
                                userInput = ""
                                academy.generateNewPrompt()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isSelected ? .white : .secondary)

                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ?
                                Color.accentColor :
                                Color.clear
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            // Character Sound Speed (WPM)
            HStack(spacing: 5) {
                Text("CHAR:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Stepper("\(academy.characterWPM) WPM", value: $academy.characterWPM, in: 14...45)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .help("Character Speed: The speed at which individual dits/dahs are sounded.")
            }

            Divider().frame(height: 18)

            // Farnsworth Effective Spacing Speed
            HStack(spacing: 5) {
                Text("SPACING:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Stepper("\(academy.effectiveWPM) WPM", value: $academy.effectiveWPM, in: 8...academy.characterWPM)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .help("Farnsworth Spacing: Overall effective speed with lengthened pauses between characters.")
            }

            Divider().frame(height: 18)

            // Audio Sidetone Pitch
            HStack(spacing: 5) {
                Text("TONE:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(Int(academy.sidetonePitchHz)) Hz")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 48)
                Slider(value: $academy.sidetonePitchHz, in: 400...900, step: 25)
                    .frame(width: 55)
                    .controlSize(.mini)
                    .help("Sidetone pitch frequency (400 - 900 Hz)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Koch Progression Level Banner

    private var kochLevelProgressBanner: some View {
        HStack(spacing: 12) {
            // Level Badge & Stepper
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .foregroundColor(.accentColor)
                Text("Koch Level \(academy.kochLevel) / 40")
                    .font(.subheadline.bold())

                Stepper("", value: $academy.kochLevel, in: 2...40)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: academy.kochLevel) { _, _ in
                        lastResult = nil
                        userInput = ""
                        academy.generateNewPrompt()
                    }
            }

            // Visual Progress Capsule
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 7)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(7, geo.size.width * CGFloat(academy.kochLevel) / 40.0), height: 7)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 120, height: 16)

            Spacer()

            // Unlock Status or Level-Up Button
            if academy.eligibleForLevelUp, let nextChar = academy.nextCharacterToUnlock {
                Button {
                    academy.advanceKochLevel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                        Text("Accuracy \u{2265} 90%! Unlock Letter '\(String(nextChar))'")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            } else if let nextChar = academy.nextCharacterToUnlock {
                HStack(spacing: 4) {
                    Text("Next to unlock:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("'\(String(nextChar))'")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Text("(maintains \u{2265}90% in 10 tests)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Main Practice Card

    private var mainPracticeCard: some View {
        VStack(spacing: 14) {
            // Audio Playback & Control Bar
            HStack(spacing: 12) {
                // Big Play Audio Button
                Button {
                    academy.playCurrentPrompt()
                    isInputFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: academy.isPlayingAudio ? "waveform" : "play.fill")
                            .font(.headline)
                        Text(academy.isPlayingAudio ? "PLAYING..." : "PLAY AUDIO")
                            .font(.headline.bold())
                    }
                    .frame(minWidth: 150)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(academy.isPlayingAudio ? .orange : .accentColor)
                .keyboardShortcut(.space, modifiers: [])
                .help("Play or replay the Morse sound (Spacebar or ⌘R)")

                Button {
                    academy.playCurrentPrompt()
                    isInputFocused = true
                } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    lastResult = (isMatch: false, target: academy.currentPrompt, input: "Revealed")
                } label: {
                    Label("Reveal", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    skipToNextPrompt()
                } label: {
                    HStack(spacing: 5) {
                        Text("Next")
                        Image(systemName: "forward.fill")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

            // Crystal-Clear High-Contrast Input Field (Custom Bezel to prevent font clipping)
            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.title3)
                    .foregroundColor(isInputFocused ? .accentColor : .secondary)

                ZStack(alignment: .leading) {
                    if userInput.isEmpty {
                        Text("Type what you hear and press Enter...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.secondary.opacity(0.65))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $userInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .focused($isInputFocused)
                        .onSubmit {
                            submitCurrentAnswer()
                        }
                }

                if !userInput.isEmpty {
                    Button {
                        userInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear text")
                }

                // High-Contrast Accent Submit Button
                Button {
                    submitCurrentAnswer()
                } label: {
                    HStack(spacing: 5) {
                        Text("SUBMIT")
                            .font(.system(size: 12, weight: .heavy))
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isInputFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isInputFocused ? 2 : 1)
            )

            // Real-Time Feedback Card
            if let res = lastResult {
                HStack(spacing: 12) {
                    Image(systemName: res.isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(res.isMatch ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(res.isMatch ? "EXCELLENT! Correct copy." : "MISSED:")
                            .font(.caption.bold())
                            .foregroundColor(res.isMatch ? .green : .red)

                        HStack(spacing: 8) {
                            Text("Target: [\(res.target)]")
                                .font(.system(.body, design: .monospaced).bold())
                                .foregroundColor(.primary)

                            if !res.isMatch {
                                Text("You typed: [\(res.input)]")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if res.isMatch {
                        Text("+1 Streak 🔥")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background((res.isMatch ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Unlocked Alphabet Rack

    private var unlockedAlphabetRack: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTIVE ALPHABET (\(academy.activeCharacters.count) characters):")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(academy.activeCharacters, id: \.self) { char in
                        let morse = CWKeyerService.morseAlphabet[char] ?? ""
                        VStack(spacing: 2) {
                            Text(String(char))
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(.primary)
                            Text(morse)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.14))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Statistics Ribbon

    private var statsRibbon: some View {
        HStack(spacing: 20) {
            // Accuracy
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                Text("Accuracy:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f%%", academy.accuracyPercentage))
                    .font(.headline.monospacedDigit().bold())
                    .foregroundColor(academy.accuracyPercentage >= 90.0 ? .green : (academy.accuracyPercentage >= 70.0 ? .primary : .orange))
            }

            Divider().frame(height: 20)

            // Current Streak
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Streak:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(academy.currentStreak)")
                    .font(.headline.monospacedDigit().bold())
                    .foregroundColor(.orange)
            }

            Divider().frame(height: 20)

            // Best Streak
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                Text("Best:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(academy.bestStreak)")
                    .font(.headline.monospacedDigit().bold())
            }

            Divider().frame(height: 20)

            // Total Trials
            HStack(spacing: 6) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.secondary)
                Text("Trials:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(academy.correctCount) / \(academy.trialsCount)")
                    .font(.headline.monospacedDigit().bold())
            }

            Spacer()

            Button {
                academy.resetLessonProgress()
                lastResult = nil
            } label: {
                Label("Reset Stats", systemImage: "arrow.counterclockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func submitCurrentAnswer() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isMatch = academy.submitAnswer(trimmed)
        lastResult = (isMatch: isMatch, target: academy.currentPrompt, input: trimmed)
        userInput = ""

        if isMatch {
            // Auto advance prompt and play after brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                academy.generateNewPrompt()
                if academy.autoPlayNext {
                    academy.playCurrentPrompt()
                }
                isInputFocused = true
            }
        } else {
            isInputFocused = true
        }
    }

    private func skipToNextPrompt() {
        userInput = ""
        lastResult = nil
        academy.generateNewPrompt()
        academy.playCurrentPrompt()
        isInputFocused = true
    }
}
