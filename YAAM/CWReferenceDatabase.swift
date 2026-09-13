//
//  CWReferenceDatabase.swift
//  YAAM
//
//  Structured Amateur Radio CW Reference Library
//  Full catalog of Q-Codes, Prosigns, and Abbreviations with Morse strings,
//  formal definitions, usage examples, and interactive quiz models.
//

import Foundation

public enum CWReferenceCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All Items"
    case qCode = "Q-Codes"
    case prosign = "Prosigns"
    case abbreviation = "Abbreviations"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .qCode: return "questionmark.circle.fill"
        case .prosign: return "character.bubble.fill"
        case .abbreviation: return "textformat.abc"
        }
    }
}

public struct CWReferenceItem: Identifiable, Sendable {
    public let id = UUID()
    public let code: String
    public let morseCode: String
    public let category: CWReferenceCategory
    public let meaning: String
    public let example: String

    public init(
        code: String,
        morseCode: String,
        category: CWReferenceCategory,
        meaning: String,
        example: String
    ) {
        self.code = code
        self.morseCode = morseCode
        self.category = category
        self.meaning = meaning
        self.example = example
    }
}

public struct CWQuizQuestion: Identifiable, Sendable {
    public let id = UUID()
    public let item: CWReferenceItem
    public let options: [String]
    public let correctOptionIndex: Int
}

public final class CWReferenceDatabase {
    public static let shared = CWReferenceDatabase()

    public let items: [CWReferenceItem] = [
        // MARK: - Standard Amateur Radio Q-Codes
        CWReferenceItem(
            code: "QRL?",
            morseCode: "--.- .-. .-.. ..--..",
            category: .qCode,
            meaning: "Are you busy? / Is this frequency in use?",
            example: "QRL? DE EP2AES (Wait and ask before calling CQ)"
        ),
        CWReferenceItem(
            code: "QRM",
            morseCode: "--.- .-. --",
            category: .qCode,
            meaning: "Man-made interference / Other station on frequency",
            example: "SRI QRM PSE AGN (Sorry, interference on frequency, please repeat)"
        ),
        CWReferenceItem(
            code: "QRN",
            morseCode: "--.- .-. -.",
            category: .qCode,
            meaning: "Atmospheric or static noise",
            example: "HVY QRN HR DUE TO STORM"
        ),
        CWReferenceItem(
            code: "QRO",
            morseCode: "--.- .-. ---",
            category: .qCode,
            meaning: "Increase transmitter power / High power (>100W)",
            example: "RUNNING QRO 500W"
        ),
        CWReferenceItem(
            code: "QRP",
            morseCode: "--.- .-. .--.",
            category: .qCode,
            meaning: "Decrease power / Low power operation (<= 5W)",
            example: "RIG HR YAESU FT-817 QRP 5W"
        ),
        CWReferenceItem(
            code: "QRT",
            morseCode: "--.- .-. -",
            category: .qCode,
            meaning: "Stop sending / Cease operation / Going off the air",
            example: "GOING QRT FER DINNER 73"
        ),
        CWReferenceItem(
            code: "QRZ?",
            morseCode: "--.- .-. --.. ..--..",
            category: .qCode,
            meaning: "Who is calling me? / Station identification query",
            example: "QRZ? DE EP2AES K"
        ),
        CWReferenceItem(
            code: "QSB",
            morseCode: "--.- ... -...",
            category: .qCode,
            meaning: "Signal fading / Signal strength fluctuating",
            example: "UR SIG HAS HVY QSB"
        ),
        CWReferenceItem(
            code: "QSL",
            morseCode: "--.- ... .-..",
            category: .qCode,
            meaning: "I acknowledge receipt / Confirming contact",
            example: "CFM QSL VIA LOTW"
        ),
        CWReferenceItem(
            code: "QSO",
            morseCode: "--.- ... ---",
            category: .qCode,
            meaning: "Two-way amateur radio contact",
            example: "TNX FER FB QSO"
        ),
        CWReferenceItem(
            code: "QSY",
            morseCode: "--.- ... -.--",
            category: .qCode,
            meaning: "Change operating frequency",
            example: "PSE QSY UP 5 KHZ"
        ),
        CWReferenceItem(
            code: "QTH",
            morseCode: "--.- - ....",
            category: .qCode,
            meaning: "Location / Station geographic position",
            example: "MY QTH IS TEHRAN"
        ),
        CWReferenceItem(
            code: "QTR",
            morseCode: "--.- - .-.",
            category: .qCode,
            meaning: "Exact UTC time",
            example: "QTR HR 1230Z"
        ),
        CWReferenceItem(
            code: "QRX",
            morseCode: "--.- .-. -..-",
            category: .qCode,
            meaning: "Wait / Stand by for a short time",
            example: "QRX 5 MIN PSE"
        ),

        // MARK: - Procedural Signals (Prosigns)
        CWReferenceItem(
            code: "<AR>",
            morseCode: ".-.-.",
            category: .prosign,
            meaning: "End of transmission / Out",
            example: "73 DE EP2AES <AR>"
        ),
        CWReferenceItem(
            code: "<SK>",
            morseCode: "...-.-",
            category: .prosign,
            meaning: "Final end of contact / Silent Key",
            example: "TNX FER QSO 73 <SK> TU"
        ),
        CWReferenceItem(
            code: "<BT>",
            morseCode: "-...-",
            category: .prosign,
            meaning: "Separator / Break / Double hyphen (=)",
            example: "UR RST 599 <BT> NAME HR ALI <BT> QTH TEHRAN"
        ),
        CWReferenceItem(
            code: "<AS>",
            morseCode: ".-...",
            category: .prosign,
            meaning: "Wait / Stand by for a moment",
            example: "<AS> QRX PSE"
        ),
        CWReferenceItem(
            code: "<KN>",
            morseCode: "-.--.",
            category: .prosign,
            meaning: "Go ahead, named station only",
            example: "W1AW DE EP2AES <KN>"
        ),
        CWReferenceItem(
            code: "<HH>",
            morseCode: "........",
            category: .prosign,
            meaning: "Correction / Error in sending (8 dits)",
            example: "UR NA <HH> UR NAME HR ALI"
        ),

        // MARK: - Standard Ham Radio Abbreviations
        CWReferenceItem(
            code: "73",
            morseCode: "--... ...--",
            category: .abbreviation,
            meaning: "Best regards / Warmest wishes",
            example: "73 ES CU AGN DE EP2AES"
        ),
        CWReferenceItem(
            code: "88",
            morseCode: "---.. ---..",
            category: .abbreviation,
            meaning: "Love and kisses (traditionally to YL operators)",
            example: "88 TO UR XYL"
        ),
        CWReferenceItem(
            code: "5NN",
            morseCode: "..... -. -.",
            category: .abbreviation,
            meaning: "Contest shorthand for 599 (N = 9)",
            example: "UR 5NN 014"
        ),
        CWReferenceItem(
            code: "AGN",
            morseCode: ".- --. -.",
            category: .abbreviation,
            meaning: "Again",
            example: "PSE CALL AGN"
        ),
        CWReferenceItem(
            code: "BK",
            morseCode: "-... -.-",
            category: .abbreviation,
            meaning: "Break / Handing over control",
            example: "HW CPY? BK"
        ),
        CWReferenceItem(
            code: "CFM",
            morseCode: "-.-. ..-. --",
            category: .abbreviation,
            meaning: "Confirm / I confirm",
            example: "CFM 14.025 MHZ"
        ),
        CWReferenceItem(
            code: "CUL",
            morseCode: "-.-. ..- .-..",
            category: .abbreviation,
            meaning: "See you later",
            example: "CUL OM 73"
        ),
        CWReferenceItem(
            code: "DE",
            morseCode: "-.. .",
            category: .abbreviation,
            meaning: "From / This is",
            example: "CQ CQ DE EP2AES"
        ),
        CWReferenceItem(
            code: "ES",
            morseCode: ". ...",
            category: .abbreviation,
            meaning: "And (&)",
            example: "TU ES 73"
        ),
        CWReferenceItem(
            code: "FB",
            morseCode: "..-. -...",
            category: .abbreviation,
            meaning: "Fine business / Excellent / Great",
            example: "UR SIG FB HR"
        ),
        CWReferenceItem(
            code: "HW?",
            morseCode: ".... .-- ..--..",
            category: .abbreviation,
            meaning: "How do you copy? / How was that?",
            example: "NAME IS ALI HW?"
        ),
        CWReferenceItem(
            code: "OM",
            morseCode: "--- --",
            category: .abbreviation,
            meaning: "Old man (friendly term for male operator)",
            example: "TNX FB QSO OM"
        ),
        CWReferenceItem(
            code: "PSE",
            morseCode: ".--. ... .",
            category: .abbreviation,
            meaning: "Please",
            example: "PSE K"
        ),
        CWReferenceItem(
            code: "TU",
            morseCode: "- ..-",
            category: .abbreviation,
            meaning: "Thank you",
            example: "TU FER CALL 73"
        ),
        CWReferenceItem(
            code: "WX",
            morseCode: ".-- -..-",
            category: .abbreviation,
            meaning: "Weather conditions",
            example: "WX HR SUNNY 28C"
        )
    ]

    // MARK: - Quiz Generator

    public func generateQuizQuestion() -> CWQuizQuestion? {
        guard items.count >= 4, let target = items.randomElement() else { return nil }

        var wrongOptions: [String] = []
        let otherItems = items.filter { $0.id != target.id }.shuffled()
        for item in otherItems {
            if wrongOptions.count < 3 {
                wrongOptions.append(item.meaning)
            }
        }

        var options = wrongOptions
        let correctOption = target.meaning
        let insertIndex = Int.random(in: 0...options.count)
        options.insert(correctOption, at: insertIndex)

        return CWQuizQuestion(
            item: target,
            options: options,
            correctOptionIndex: insertIndex
        )
    }
}
