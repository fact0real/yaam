//
//  MorseTiming.swift
//  YAAM
//
//  The Morse timing of a text and the cut of a text into Kenwood KY pieces, for the drivers that key CW through
//  the radio's own keyer (Lab599TX500Driver, FX4CRDriver).
//

import Foundation

nonisolated enum MorseTiming {
    static let maximumTextLength = 1024

    static func normalizedText(_ text: String) -> (text: String, unsendable: String) {
        var result = ""
        var rejected: [String] = []
        for character in text {
            if [" ", "\t", "\r", "\n", "\r\n"].contains(String(character)) {
                result.append(" ")
                continue
            }
            let plain = character.isASCII ? String(character) : String(character).folding(options: .diacriticInsensitive, locale: nil)
            if !plain.isEmpty, plain.allSatisfy(\.isASCII), plain.uppercased().allSatisfy({ alphabet[$0] != nil }) {
                result += plain
            } else {
                let name = character.unicodeScalars.allSatisfy({ $0.value > 0x20 && !$0.properties.isDefaultIgnorableCodePoint && !$0.properties.isWhitespace })
                    ? String(character)
                    : character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                if !rejected.contains(name) { rejected.append(name) }
            }
        }
        return (result.split(separator: " ").joined(separator: " "), rejected.joined(separator: ", "))
    }

    static func safeText(_ text: String) -> String? {
        guard text.utf8.count <= maximumTextLength else { return nil }
        let normalized = normalizedText(text)
        guard normalized.unsendable.isEmpty, !normalized.text.isEmpty else { return nil }
        return normalized.text.uppercased()
    }
    /// The same table as CWKeyerService.morseAlphabet, copied so that the radio drivers do not need the keyer service.
    static let alphabet: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "0": "-----", "/": "-..-.", "?": "..--..", "=": "-...-", ",": "--..--",
        ".": ".-.-.-", "!": "-.-.--", "-": "-....-", "@": ".--.-."
    ]

    /// Seconds from the first key-down to the last key-up of the text at this speed (PARIS timing: one unit is
    /// 1.2 / wpm s; a dit is 1 unit, a dah 3, with 1 unit between the elements of a character, 3 between characters
    /// and 7 between words). A character not in the table counts 0, as the sidetone skips it.
    static func duration(of text: String, wpm: Int) -> TimeInterval {
        let unit = 1.2 / Double(max(1, wpm))
        let words = text.uppercased().split(separator: " ").map { word in word.compactMap { alphabet[$0] } }
            .filter { !$0.isEmpty }
        var units = 0
        for (w, codes) in words.enumerated() {
            if w > 0 { units += 7 }
            for (c, code) in codes.enumerated() {
                if c > 0 { units += 3 }
                units += code.reduce(0) { $0 + ($1 == "." ? 1 : 3) } + (code.count - 1)
            }
        }
        return Double(units) * unit
    }

    /// The text cut into pieces of at most `limit` characters, at spaces: words are joined while the piece stays
    /// within the limit; a single word longer than the limit is cut at the limit. No piece starts or ends with a space.
    static func chunks(of text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var pieces: [String] = []
        var current = ""
        for word in text.split(separator: " ").map(String.init) {
            var word = word
            while word.count > limit {
                if !current.isEmpty { pieces.append(current); current = "" }
                pieces.append(String(word.prefix(limit)))
                word = String(word.dropFirst(limit))
            }
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                pieces.append(current)
                current = word
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// The time left between the computed end of one KY piece and the next: a word gap (7 units), and at least
    /// 0.3 s, so that the radio has finished keying the piece before the next one reaches it.
    static func handover(wpm: Int) -> TimeInterval {
        max(0.3, 7 * 1.2 / Double(max(1, wpm)))
    }
}
