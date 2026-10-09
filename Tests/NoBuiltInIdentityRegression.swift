import Foundation

// No screen or field starts out with a callsign, locator, place or park that is not the operator's. The texts next
// to a field that the user fills in are neutral ("Your callsign", "Locator not set", "Park or summit reference"),
// and the example given in a prompt or a message is not a real callsign, locator, place or park. This test reads
// the sources of the app; it compiles with the shared check only to read the neutral texts. Build and run it from
// the repository root (DEVELOPER_DOCUMENTATION.md section 8.2):
//   swiftc -parse-as-library Tests/NoBuiltInIdentityRegression.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o /tmp/nbi && /tmp/nbi
// With the argument --list it prints, instead of the checks, what the app still holds on purpose (the tables below,
// file by file, with the line numbers found now); the notes of the patch take their list from there.
// Four groups of source-text checks:
//   - no file holds a built-in operator callsign, locator or place, except the listed credits, documentation,
//     reference data and demo content, and each listed file holds exactly the number of lines it is listed with;
//   - no text field prompt and no "such as" / "e.g." example in a message shows a callsign, locator, place or park
//     reference, and no field, setting or stored property starts out as one, in any letter case, with a locator of
//     4, 6, 8 or 10 characters, and no statement puts one into a field;
//   - the Field activation sheet and the other screens that had a park or a place as a starting value or an example
//     now start empty and say what to enter in generic words;
//   - the few shared displays that used to carry one say that the value is not set.

@main
struct NoBuiltInIdentityRegression {
    nonisolated(unsafe) static var failures = 0
    static func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL") \(name)")
        if !ok { failures += 1 }
    }

    // MARK: - Shapes. Every match is made without regard to letter case, so "dl1abc" and "fn54vi" are found too.

    // A callsign: prefix, one digit, suffix of 1 to 4 letters.
    static let callsignCore = #"(?:[A-Z]{1,2}|[0-9][A-Z]|[A-Z][0-9])[0-9][A-Z]{1,4}"#
    // A Maidenhead locator of 4, 6, 8 or 10 characters.
    static let locatorCore = #"[A-R]{2}[0-9]{2}(?:[A-X]{2}(?:[0-9]{2}(?:[A-X]{2})?)?)?"#
    // A park or summit reference such as K-0001.
    static let parkCore = #"[A-Z]{1,2}-[0-9]{4,5}"#
    static let callsignShape = #"(?<![A-Za-z0-9/])"# + callsignCore + #"(?![A-Za-z0-9])"#
    static let locatorShape = #"(?<![A-Za-z0-9])"# + locatorCore + #"(?![A-Za-z0-9])"#
    static let parkShape = #"(?<![A-Za-z0-9])"# + parkCore + #"(?![A-Za-z0-9])"#
    // Places that must not appear as an example or a starting value.
    static let placeWords = ["Tehran", "Iran", "Kish", "Lar National Park", "EP-0005"]
    static let placeShape = #"(?<![A-Za-z])("# + placeWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")(?![A-Za-z])"#
    // A whole value that is a callsign (also with a portable suffix), a locator or a park reference.
    static let wholeIdentity = "^(?:" + callsignCore + #"(?:/[A-Z0-9]{1,4})?|"# + locatorCore + "|" + parkCore + ")$"
    // Names of programs that look like callsigns are not examples of callsigns.
    static let programNames: Set<String> = ["N1MM"]

    /// True when `pattern` matches `text`, in any letter case.
    nonisolated static func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True when the text shows a callsign, a locator, a park reference or one of the place words.
    nonisolated static func showsIdentity(_ text: String) -> Bool {
        !wordsMatching(callsignShape, in: text).filter { !programNames.contains($0.uppercased()) }.isEmpty
            || has(text, locatorShape) || has(text, parkShape) || has(text, placeShape)
    }

    static func main() {
        if CommandLine.arguments.contains("--list") {
            printList()
            return
        }
        neutralTexts()
        builtInValues()
        examplesAndDefaults()
        fieldScreens()
        displays()

        if failures > 0 {
            print("No built-in identity regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("No built-in identity regression passed")
    }

    // MARK: - The neutral texts

    static func neutralTexts() {
        let texts = [TransmitIdentity.callsignPlaceholder, TransmitIdentity.locatorPlaceholder, TransmitIdentity.callsignNotSetLabel,
                     TransmitIdentity.locatorNotSetLabel, TransmitIdentity.callsignPreviewToken]
        check("the neutral texts are generic: none is a callsign or a locator",
              texts.allSatisfy { !TransmitIdentity.isValidCallsign($0) && !TransmitIdentity.isValidLocator($0) })
        check("the neutral texts name no callsign, locator, park or place in them",
              texts.allSatisfy { !showsIdentity($0) })
        check("the preview token is a placeholder word, so the keyer refuses it",
              TransmitIdentity.callsignRefusal(TransmitIdentity.callsignPreviewToken) == TransmitIdentity.callsignMissingMessage)
        // The shapes themselves: what the scan below is able to see.
        let seen = ["ea3jic", "EA3JIC", "JN11", "jn11", "fn54vi", "Fn54VI44", "FN54VI44TA", "K-0001", "ep-0005", "EP-0005", "Lar National Park",
                    "Tehran", "iran", "Kish Island"]
        check("the scan sees callsigns, locators of 4 to 10 characters, park references and the place words in any letter case: \(seen.filter { !showsIdentity($0) })",
              seen.allSatisfy { showsIdentity($0) })
        let unseen = ["Your callsign", "Locator not set", "Park or summit reference", "DXCC entity", "Search park reference or name", "FT8", "FN54VI4", "Irani"]
        check("the scan leaves ordinary words, a 7-character locator and \"Irani\" alone: \(unseen.filter { showsIdentity($0) })",
              unseen.allSatisfy { !showsIdentity($0) })
    }

    // MARK: - What the app still holds on purpose: three tables

    struct Held {
        let file: String
        let lines: Int
        let group: String
        let what: String
    }

    // Table 1: an operator callsign, a locator or a place as a quoted string (and the callsigns EP2AES, EP2YAAM and
    // EA3JIC anywhere in code). Credits, documentation, reference data and demo content are listed with the number of
    // lines each holds; any other file must hold none, and a listed file must hold exactly that number.
    // The squares the app used as its own (four characters), and the same squares with a subsquare (two more letters).
    static let identityPattern = #"EP2AES|EP2YAAM|EA3JIC|"(LM55|LL35|LL45|LM35|JN11|LL46|KM32)"|"(LM55|LL35|LN35|FN31)[a-x]{2}"|Tehran"#
    static let identityHeld: [Held] = [
        Held(file: "AboutView.swift", lines: 2, group: "credits", what: "the author's credit"),
        Held(file: "ADIFParser.swift", lines: 1, group: "credits", what: "credit in the header of an exported log"),
        Held(file: "HelpView.swift", lines: 12, group: "documentation examples", what: "in-app help and its illustrations"),
        Held(file: "CWReferenceDatabase.swift", lines: 6, group: "documentation examples", what: "Morse reference examples"),
        Held(file: "ClubMembershipEngine.swift", lines: 7, group: "reference data with a callsign and a first name", what: "club member data"),
        Held(file: "CallHistoryLookupEngine.swift", lines: 3, group: "reference data with a callsign and a first name", what: "call history data"),
        Held(file: "SuperCheckPartialEngine.swift", lines: 1, group: "reference data", what: "callsign list"),
        Held(file: "BustedCallsignEngine.swift", lines: 1, group: "reference data", what: "callsign list"),
        Held(file: "POTAParkDirectory.swift", lines: 3, group: "reference data", what: "park directory entries"),
        Held(file: "SixMeterPropagationEngine.swift", lines: 1, group: "reference data", what: "an ionosonde station"),
        Held(file: "CWAudioDecoderEngine.swift", lines: 1, group: "demo and canned content", what: "decoder sample text"),
        Held(file: "POTASpotsClient.swift", lines: 1, group: "demo and canned content", what: "sample spots"),
        Held(file: "BandmapEngine.swift", lines: 1, group: "demo and canned content", what: "demo spots"),
        Held(file: "CompetitorTrackingEngine.swift", lines: 1, group: "demo and canned content", what: "demo competitors"),
        Held(file: "SyntheticRFSignalEngine.swift", lines: 3, group: "demo and canned content", what: "canned test signals"),
        Held(file: "NetworkTransceiverEmulatorView.swift", lines: 8, group: "demo and canned content", what: "canned test signals"),
        Held(file: "RoverModeEngine.swift", lines: 1, group: "built-in place", what: "rover preset"),
        Held(file: "QSLCardView.swift", lines: 3, group: "built-in place", what: "QSL card template name, flag and card text")
    ]

    // Table 2: the home position and the home continent that are used when no station position is known.
    static let placePattern = #"35\.6892|51\.3890|latitude: 35\.7, longitude: 51\.4|stationLongitude: Double = 51\.4|homeContinent = "AS""#
    static let placeHeld: [Held] = [
        Held(file: "AppStatePersistence.swift", lines: 2, group: "home position", what: "fallback when the profile has none"),
        Held(file: "FieldParkMapView.swift", lines: 1, group: "home position", what: "map centre"),
        Held(file: "HamClockShackView.swift", lines: 1, group: "home position", what: "fallback"),
        Held(file: "GridMapViews.swift", lines: 1, group: "home position", what: "fallback"),
        Held(file: "HamTrackerEngine.swift", lines: 1, group: "home position", what: "starting value"),
        Held(file: "OnTheAirMonitorService.swift", lines: 2, group: "home position", what: "starting values"),
        Held(file: "SatelliteTrackingEngine.swift", lines: 1, group: "home position", what: "starting value"),
        Held(file: "SignalFootprintEngine.swift", lines: 1, group: "home position", what: "starting value"),
        Held(file: "SixMeterPropagationEngine.swift", lines: 3, group: "home position", what: "starting values, and the ionosonde of table 1"),
        Held(file: "VisualAnalyticsView.swift", lines: 1, group: "home position", what: "fallback"),
        Held(file: "ShackClockEngine.swift", lines: 1, group: "home position", what: "starting longitude"),
        Held(file: "BandmapView.swift", lines: 1, group: "home position", what: "position of a spot's station when none is known"),
        Held(file: "ContestWorkspace.swift", lines: 1, group: "home continent", what: "homeContinent is \"AS\": every operator is scored as being in Asia")
    ]

    // Table 3: other built-in content, found by a literal of its own.
    struct Literal {
        let file: String
        let pattern: String
        let lines: Int
        let group: String
        let what: String
    }
    static let otherHeld: [Literal] = [
        Literal(file: "APRSBalloonTrackingEngine.swift", pattern: #"W3BC-11|HAB-IRAN-1|Alborz"#, lines: 4, group: "demo and canned content",
                what: "demo balloons; W3BC-11 is the one selected at start"),
        Literal(file: "AppState.swift", pattern: #"return call\.isEmpty \? "DEFAULT" : call"#, lines: 1, group: "placeholder callsign",
                what: "the DX cluster login uses DEFAULT when no callsign is set"),
        Literal(file: "AppState.swift", pattern: #"selectedNationalCountryIso: String = "ir""#, lines: 1, group: "starting country",
                what: "the national rankings start with Iran"),
        Literal(file: "SKEDDirectoryView.swift", pattern: #"@State private var countryISO = "ir""#, lines: 1, group: "starting country",
                what: "the SKED country picker starts with Iran"),
        Literal(file: "NationalLeaderboardViews.swift", pattern: #"Load Iranian \(EP\) Standings"#, lines: 1, group: "starting country",
                what: "the empty rankings page offers the standings of Iran")
    ]

    // Table 4: examples in the English manual (the Persian manual is not read here and is not edited).
    static let manualPattern = #"EP2AES|EA3JIC|Tehran|Iran|Kish|(LL25|FN31)[a-x]{2}"#
    static let manualHeld = Held(file: "USER_MANUAL.md", lines: 7, group: "documentation examples",
                                 what: "TQSL station location examples, and the default country of the SKED tab")

    /// The numbers of the lines of a plain text (no comments to remove) whose text matches `pattern`.
    nonisolated static func plainHitLines(_ text: String, _ pattern: String) -> [Int] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .filter { $0.element.range(of: pattern, options: .regularExpression) != nil }.map { $0.offset + 1 }
    }

    /// The lines (numbers) of `text` whose code (comments removed) matches `pattern`.
    nonisolated static func hitLines(_ text: String, _ pattern: String) -> [Int] {
        codeLines(text).filter { $0.code.range(of: pattern, options: .regularExpression) != nil }.map { $0.number }
    }

    static func builtInValues() {
        let sources = allSources()
        for (name, pattern, table) in [("an operator callsign, locator or place", identityPattern, identityHeld),
                                       ("the home position or home continent", placePattern, placeHeld)] {
            var offenders: [String] = []
            var differs: [String] = []
            let listed = Dictionary(uniqueKeysWithValues: table.map { ($0.file, $0) })
            for (file, text) in sources.sorted(by: { $0.key < $1.key }) {
                let hits = hitLines(text, pattern)
                if let held = listed[file] {
                    if hits.count != held.lines { differs.append("\(file) has \(hits.count), the list says \(held.lines)") }
                } else {
                    offenders += hits.map { "\(file):\($0)" }
                }
            }
            let missing = table.filter { sources[$0.file] == nil }.map { $0.file }
            check("no file outside the list holds \(name) \(offenders)", offenders.isEmpty)
            check("every listed file holds exactly the listed number of lines with \(name), and exists \(differs + missing)", differs.isEmpty && missing.isEmpty)
        }
        var otherDiffers: [String] = []
        for held in otherHeld {
            let count = sources[held.file].map { hitLines($0, held.pattern).count } ?? -1
            if count != held.lines { otherDiffers.append("\(held.file) has \(count), the list says \(held.lines)") }
        }
        check("every other listed built-in is still where the list says, and in that number \(otherDiffers)", otherDiffers.isEmpty)
        let manualHits = plainHitLines(sourceText("USER_MANUAL.md") ?? "", manualPattern)
        check("the English manual holds exactly the listed lines with an example callsign, locator or place \(manualHits)", manualHits.count == manualHeld.lines)
    }

    /// --list: the three tables with the line numbers found now, one entry per line.
    static func printList() {
        let sources = allSources()
        func lines(_ file: String, _ pattern: String) -> String {
            (sources[file].map { hitLines($0, pattern) } ?? []).map(String.init).joined(separator: ",")
        }
        for held in identityHeld { print("HELD | \(held.group) | \(held.file):\(lines(held.file, identityPattern)) | \(held.what)") }
        for held in placeHeld { print("HELD | \(held.group) | \(held.file):\(lines(held.file, placePattern)) | \(held.what)") }
        for held in otherHeld { print("HELD | \(held.group) | \(held.file):\(lines(held.file, held.pattern)) | \(held.what)") }
        let manualLines = plainHitLines(sourceText("USER_MANUAL.md") ?? "", manualPattern).map(String.init).joined(separator: ",")
        print("HELD | \(manualHeld.group) | \(manualHeld.file):\(manualLines) | \(manualHeld.what)")
    }

    // MARK: - Examples in prompts and messages, and starting values

    static func examplesAndDefaults() {
        let sources = allSources()
        // The in-app documentation and the credits may give examples.
        let documentation: Set<String> = ["HelpView.swift", "AboutView.swift", "CWReferenceDatabase.swift"]

        // 1. Text fields: the prompt of a field the user fills in shows no example callsign, locator, park or place.
        var prompts: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) where !documentation.contains(file) {
            let lines = codeLines(text)
            for (index, line) in lines.enumerated() {
                guard let open = line.code.range(of: #"(TextField|SecureField)\("#, options: .regularExpression) else { continue }
                // The prompt is the first string after the opening bracket, on this line or the next one.
                var tail = String(line.code[open.upperBound...])
                if !tail.contains("\"") && index + 1 < lines.count { tail = lines[index + 1].code }
                guard let prompt = firstStringLiteral(in: tail) else { continue }
                if showsIdentity(prompt) { prompts.append("\(file):\(line.number) \"\(prompt)\"") }
            }
        }
        check("no text field prompt shows an example callsign, locator, park reference or place \(prompts)", prompts.isEmpty)

        // 2. Messages and labels: no "such as ..." / "e.g. ..." / "for example ..." in a string gives one.
        var examples: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) where !documentation.contains(file) {
            for line in codeLines(text) {
                for literal in stringLiterals(in: line.code) {
                    guard let marker = literal.range(of: #"(e\.g\.|such as|for example|for instance|like)\s"#, options: [.regularExpression, .caseInsensitive]) else { continue }
                    if showsIdentity(String(literal[marker.upperBound...])) { examples.append("\(file):\(line.number) \"\(literal)\"") }
                }
            }
        }
        check("no message or label gives an example callsign, locator, park reference or place after \"such as\" or \"e.g.\" \(examples)", examples.isEmpty)

        // 3. State the user fills in does not start out as one.
        let declaration = #"^(\s*)((?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:public|private|fileprivate|internal|static|nonisolated|final)\s+)*(var|let)\s+\w+\s*(?::\s*String)?\s*=\s*"([^"\\]*)""#
        var defaults: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) {
            for line in codeLines(text) {
                guard let regex = try? NSRegularExpression(pattern: declaration),
                      let match = regex.firstMatch(in: line.code, range: NSRange(line.code.startIndex..., in: line.code)),
                      let indentRange = Range(match.range(at: 1), in: line.code),
                      let wrapperRange = Range(match.range(at: 2), in: line.code),
                      let keywordRange = Range(match.range(at: 3), in: line.code),
                      let valueRange = Range(match.range(at: 4), in: line.code) else { continue }
                let value = String(line.code[valueRange]).trimmingCharacters(in: .whitespaces)
                guard has(value, wholeIdentity) || has(value, placeShape) else { continue }
                let wrappers = String(line.code[wrapperRange])
                let stateOfAView = ["@State", "@AppStorage", "@Published", "@SceneStorage", "@Binding"].contains { wrappers.contains($0) }
                let storedProperty = line.code[keywordRange] == "var" && line.code[indentRange].count == 4
                if stateOfAView || storedProperty { defaults.append("\(file):\(line.number) \"\(value)\"") }
            }
        }
        check("no field, setting or stored property starts out as a callsign, locator (4 to 10 characters), park reference or place, in any letter case \(defaults)", defaults.isEmpty)

        // 4. No statement puts a callsign, locator, park reference or place into a property: name = "W1AW".
        let assignment = #"^\s*(?:self\.)?[A-Za-z_][A-Za-z0-9_.]*\s*=\s*"([^"\\]*)"\s*$"#
        var assigned: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) where !documentation.contains(file) {
            for line in codeLines(text) {
                guard let regex = try? NSRegularExpression(pattern: assignment),
                      let match = regex.firstMatch(in: line.code, range: NSRange(line.code.startIndex..., in: line.code)),
                      let valueRange = Range(match.range(at: 1), in: line.code) else { continue }
                let value = String(line.code[valueRange]).trimmingCharacters(in: .whitespaces)
                if has(value, wholeIdentity) || has(value, placeShape) { assigned.append("\(file):\(line.number) \"\(value)\"") }
            }
        }
        check("no statement puts a callsign, locator, park reference or place into a property \(assigned)", assigned.isEmpty)
    }

    // MARK: - The screens that had a park, a place or a callsign as a starting value or an example

    static func fieldScreens() {
        let field = sourceText("YAAM/FieldPileupLoggerView.swift") ?? ""
        check("the Field activation sheet starts with no park reference and no park name",
              field.contains("@State private var sessionParkRef: String = \"\"") && field.contains("@State private var sessionParkName: String = \"\"")
              && !has(field, #"sessionPark(Ref|Name)[^\n]*=\s*"[^"]"#))
        check("the Field activation sheet asks for the reference in generic words and gives no example",
              field.contains("TextField(\"Park or summit reference:\", text: $sessionParkRef)"))
        let disabledAt = field.range(of: ".disabled(sessionParkRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        let buttonAt = field.range(of: "Button(\"Start Activation\")")
        check("Start Activation stays disabled until a reference is entered",
              disabledAt != nil && buttonAt != nil && disabledAt!.lowerBound > buttonAt!.lowerBound
              && field.distance(from: buttonAt!.lowerBound, to: disabledAt!.lowerBound) < 900)
        check("the prompt for the reference of the station worked (park to park, summit to summit) gives no example",
              field.contains("TextField(\"Reference\", text: $inputContactedRef)"))
        check("the park search prompt of the Field map is generic",
              sourceText("YAAM/FieldParkMapView.swift")?.contains("TextField(\"Search park reference or name\", text: $searchQuery)") == true)
        check("the DXCC rule prompt is generic",
              sourceText("YAAM/OperatorDeskView.swift")?.contains("TextField(\"DXCC entity\", text: $rule.dxccEntity)") == true)
        let sstv = sourceText("YAAM/SSTVEngine.swift") ?? ""
        let startAt = sstv.range(of: "public func startSimulation()")
        let timerAt = sstv.range(of: "simTimer = Timer.scheduledTimer")
        let startBody = (startAt != nil && timerAt != nil && startAt!.lowerBound < timerAt!.lowerBound) ? String(sstv[startAt!.lowerBound..<timerAt!.lowerBound]) : ""
        check("the SSTV test card puts nothing into the CALL field when it starts", !startBody.isEmpty && !startBody.contains("targetCallsign"))
        let manual = sourceText("USER_MANUAL.md") ?? ""
        check("the manual's sentence on the park search names no park reference",
              manual.contains("with instant sub-millisecond search by reference, name, or country.") && !manual.contains("`EP-0005`") && !manual.contains("`K-0001`"))
    }

    // MARK: - Displays

    static func displays() {
        let tracker = sourceText("YAAM/HamTrackerWorkspaceView.swift") ?? ""
        check("the WebSDR header says the locator is not set instead of showing a built-in one",
              tracker.contains("WEBSDR FT8 · ") && tracker.contains("TransmitIdentity.locatorNotSetLabel") && !tracker.contains("\"LM55"))
        let shack = sourceText("YAAM/HamClockShackView.swift") ?? ""
        check("the HamClock DX card starts empty, shows dashes and keeps the rotator buttons off until a DX locator is known",
              shack.contains("@State private var dxGridInput: String = \"\"") && shack.contains("@State private var dxCallsignInput: String = \"\"")
              && shack.contains("private var hasDX: Bool") && shack.components(separatedBy: ".disabled(!hasDX)").count - 1 == 2)
        let page = sourceText("YAAM/HamClockRemoteWebServer.swift") ?? ""
        check("the HamClock remote page names no station and shows no sample figures for a path",
              !page.contains("W1AW") && !page.contains("9,554") && !page.contains("321°") && !page.contains("141°") && !page.contains("EP2AES")
              && page.contains("<span id=\"dxCall\">—</span>") && page.contains("id=\"dxDist\">—</span>")
              && page.contains("\"dxDistance\": \"—\"") && page.contains("\"deCall\": \"—\""))
        check("the Stations screen's locator message gives no example locator",
              sourceText("YAAM/StationProfile.swift")?.contains("such as") == false)
        check("the CW previews use the neutral tokens, never a callsign",
              sourceText("YAAM/CWESMEngine.swift")?.contains("?? TransmitIdentity.callsignPreviewToken") == true
              && sourceText("YAAM/CWKeyerView.swift")?.contains("?? TransmitIdentity.callsignPreviewToken") == true
              && sourceText("YAAM/CWKeyerView.swift")?.contains("? \"DXCALL\" :") == true)
        check("the QSL label sheets and the QSL PDF file name use the neutral texts",
              sourceText("YAAM/QSLLabelEngine.swift")?.contains("TransmitIdentity.callsignNotSetLabel") == true
              && sourceText("YAAM/QSLLabelEngine.swift")?.contains("var stationQTH: String = \"\"") == true
              && sourceText("YAAM/AppState.swift")?.contains("TransmitIdentity.callsignPreviewToken") == true)
        check("the weather request is not made for a place that is not the station's",
              sourceText("YAAM/StationWeatherSafetyEngine.swift")?.contains("let effectiveGrid = targetGrid.isEmpty ? \"LM55\"") == false)
        check("the Settings prompt for the LoTW station location gives no callsign",
              sourceText("YAAM/SettingsView.swift")?.contains("Default Station Location (e.g. Home):") == true)
    }

    // MARK: - Source-text helpers

    /// The lines of a source file with // comments removed (a // inside a URL stays), with their numbers.
    nonisolated private static func codeLines(_ text: String) -> [(number: Int, code: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            var code = String(line)
            var from = code.startIndex
            while let slashes = code.range(of: "//", range: from..<code.endIndex) {
                if slashes.lowerBound > code.startIndex, code[code.index(before: slashes.lowerBound)] == ":" {
                    from = slashes.upperBound
                    continue
                }
                code = String(code[..<slashes.lowerBound])
                break
            }
            return (index + 1, code)
        }
    }

    /// The words of `text` that match the pattern, in any letter case.
    nonisolated private static func wordsMatching(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// The first "..." in a line, without the quotes; nil when there is none.
    nonisolated private static func firstStringLiteral(in text: String) -> String? {
        stringLiterals(in: text).first
    }

    /// Every "..." in a line, without the quotes. A backslash keeps the next character inside the string.
    nonisolated private static func stringLiterals(in text: String) -> [String] {
        var result: [String] = []
        var current: String?
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if current != nil {
                if ch == "\\" {
                    current?.append(ch)
                    index = text.index(after: index)
                    if index < text.endIndex { current?.append(text[index]) }
                } else if ch == "\"" {
                    result.append(current ?? "")
                    current = nil
                } else {
                    current?.append(ch)
                }
            } else if ch == "\"" {
                current = ""
            }
            index = text.index(after: index)
        }
        return result
    }

    /// A source file of the checkout, found from this file's location or the working directory.
    nonisolated private static func sourceText(_ path: String) -> String? {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let roots = [here, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        let text = roots.lazy.compactMap { try? String(contentsOf: $0.appendingPathComponent(path), encoding: .utf8) }.first
        if text == nil { print("cannot read \(path); run from the repository root") }
        return text
    }

    /// Every Swift source of the app, by file name.
    nonisolated private static func allSources() -> [String: String] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let roots = [here, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        for root in roots {
            let dir = root.appendingPathComponent("YAAM")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            var all: [String: String] = [:]
            for name in names where name.hasSuffix(".swift") {
                all[name] = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            }
            if !all.isEmpty { return all.compactMapValues { $0 } }
        }
        print("cannot list YAAM/; run from the repository root")
        return [:]
    }
}
