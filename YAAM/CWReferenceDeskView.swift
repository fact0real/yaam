//
//  CWReferenceDeskView.swift
//  YAAM
//
//  Interactive Amateur Radio Q-Codes, Prosigns, and Abbreviations Reference Desk
//  Features live Morse audio playback for every entry, search & filter,
//  Persian/English dual explanations, and an interactive Flashcard Quiz mode.
//

import Combine
import SwiftUI

public struct CWReferenceDeskView: View {
    @ObservedObject private var keyer = CWKeyerService.shared
    @State private var selectedCategory: CWReferenceCategory = .all
    @State private var searchText: String = ""
    @State private var previewWPM: Int = 22
    @State private var showQuizSheet: Bool = false

    private let db = CWReferenceDatabase.shared

    public init() {}

    private var filteredItems: [CWReferenceItem] {
        db.items.filter { item in
            let matchesCategory = (selectedCategory == .all || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty ||
                item.code.localizedCaseInsensitiveContains(searchText) ||
                item.meaning.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            topControlBar
            itemsScrollView
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(12)
        .sheet(isPresented: $showQuizSheet) {
            CWQuizSheetView()
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Category Filter Picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(CWReferenceCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search code or meaning...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 240)

            Spacer()

            // Preview Speed Stepper
            HStack(spacing: 4) {
                Text("SPEED:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Stepper("\(previewWPM) WPM", value: $previewWPM, in: 10...45)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }

            Divider().frame(height: 18)

            // Flashcard Quiz Button
            Button {
                showQuizSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.accentColor)
                    Text("Interactive Quiz")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Items Scroll View

    private var itemsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    ReferenceItemCard(item: item, previewWPM: previewWPM)
                }
            }
        }
    }
}

// MARK: - Reference Item Card

private struct ReferenceItemCard: View {
    let item: CWReferenceItem
    let previewWPM: Int

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Audio Play Button
            Button {
                let cleanMorse = item.code.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                CWAcademyEngine.shared.playMorseAudio(text: cleanMorse, wpm: previewWPM)
            } label: {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Listen to '\(item.code)' in Morse code at \(previewWPM) WPM")

            // Code Badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.code)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    categoryBadge(for: item.category)
                }

                Text(item.morseCode)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)

            Divider().frame(height: 34)

            // Meaning Definition
            VStack(alignment: .leading, spacing: 2) {
                Text(item.meaning)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Usage Example
            VStack(alignment: .trailing, spacing: 2) {
                Text("Example:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(item.example)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: 240, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private func categoryBadge(for cat: CWReferenceCategory) -> some View {
        let (title, color) = categoryMetadata(cat)
        Text(title)
            .font(.system(size: 8.5, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(3)
    }

    private func categoryMetadata(_ cat: CWReferenceCategory) -> (String, Color) {
        switch cat {
        case .all: return ("All", .secondary)
        case .qCode: return ("Q-Code", .blue)
        case .prosign: return ("Prosign", .purple)
        case .abbreviation: return ("Abbr", .teal)
        }
    }
}

// MARK: - Interactive Flashcard Quiz Sheet

private struct CWQuizSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentQuestion: CWQuizQuestion? = nil
    @State private var selectedAnswerIndex: Int? = nil
    @State private var score: Int = 0
    @State private var totalQuestions: Int = 0

    private let db = CWReferenceDatabase.shared

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.accentColor)
                    Text("CW Knowledge Quiz")
                        .font(.headline.bold())
                }

                Spacer()

                Text("Score: \(score) / \(totalQuestions)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundColor(.secondary)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            if let q = currentQuestion {
                VStack(spacing: 14) {
                    // Question Prompt
                    VStack(spacing: 6) {
                        Text("What is the meaning of this code?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            Text(q.item.code)
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(.accentColor)

                            Button {
                                let cleanCode = q.item.code.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                                CWAcademyEngine.shared.playText(cleanCode)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .help("Listen in Morse")
                        }

                        Text(q.item.morseCode)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 4 Options
                    VStack(spacing: 8) {
                        ForEach(0..<q.options.count, id: \.self) { index in
                            Button {
                                checkAnswer(index: index)
                            } label: {
                                HStack {
                                    Text(verbatim: "\(Character(UnicodeScalar(65 + index)!)).")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(q.options[index])
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()

                                    if let selected = selectedAnswerIndex {
                                        if index == q.correctOptionIndex {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        } else if index == selected {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(optionBackgroundColor(index: index, correctIndex: q.correctOptionIndex))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedAnswerIndex != nil)
                        }
                    }

                    // Next Question Button
                    if selectedAnswerIndex != nil {
                        Button("Next Question \u{2192}") {
                            loadNextQuestion()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            loadNextQuestion()
        }
    }

    private func loadNextQuestion() {
        selectedAnswerIndex = nil
        currentQuestion = db.generateQuizQuestion()
    }

    private func checkAnswer(index: Int) {
        selectedAnswerIndex = index
        totalQuestions += 1
        if let q = currentQuestion, index == q.correctOptionIndex {
            score += 1
        }
    }

    private func optionBackgroundColor(index: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswerIndex else {
            return Color(NSColor.controlBackgroundColor)
        }
        if index == correctIndex {
            return Color.green.opacity(0.18)
        } else if index == selected {
            return Color.red.opacity(0.18)
        }
        return Color(NSColor.controlBackgroundColor)
    }
}
