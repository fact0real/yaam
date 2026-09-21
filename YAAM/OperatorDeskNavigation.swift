// One navigation catalog for the desk, its tool finder, and the macOS Tools menu.
// Legacy section numbers remain stable for saved sessions and existing in-app links.
import Foundation

nonisolated enum OperatorDeskGroup: String, CaseIterable, Identifiable {
    case operating, dxActivity, radioDigital, cw, contests, qslData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operating: "Operating"
        case .dxActivity: "DX Activity"
        case .radioDigital: "Radio & Digital"
        case .cw: "CW Workstation"
        case .contests: "Contest & Awards"
        case .qslData: "QSL & Data"
        }
    }

    var subtitle: String {
        switch self {
        case .operating: "Log • Clock • Portable"
        case .dxActivity: "Spots • Maps • News"
        case .radioDigital: "CAT • FT8 • Modes"
        case .cw: "Keyer • Learn • Setup"
        case .contests: "Sessions • Calendar"
        case .qslData: "Cards • Logs • Cloud"
        }
    }

    var icon: String {
        switch self {
        case .operating: "antenna.radiowaves.left.and.right"
        case .dxActivity: "globe.europe.africa.fill"
        case .radioDigital: "waveform"
        case .cw: "tuningfork"
        case .contests: "flag.checkered"
        case .qslData: "tray.2.fill"
        }
    }

    var destinations: [OperatorDeskDestination] {
        switch self {
        case .operating: [.quickLog, .shackClock, .portable]
        case .dxActivity: [.dxCluster, .clubLogSpots, .bandmap, .callRoster, .globeGrids, .sixMeter, .dxNews, .on4kst]
        case .radioDigital: [.radioBridge, .flrig, .tci, .rotator, .ft8, .multiRigFT8, .digitalSuite, .emulator]
        case .cw: [.cwKeyer, .cwAcademy, .cwReference, .cwDecoder, .cwPileup, .cwHardware]
        case .contests: [.contest, .calendar, .awards, .clubs]
        case .qslData: [.qslHub, .qslLabels, .logSources, .cloudCompanion]
        }
    }

    var defaultDestination: OperatorDeskDestination { destinations[0] }

    func restoredDestination(_ savedValue: String?) -> OperatorDeskDestination {
        guard let savedValue, let destination = OperatorDeskDestination(rawValue: savedValue),
              destinations.contains(destination) else { return defaultDestination }
        return destination
    }
}

nonisolated enum OperatorDeskDestination: String, CaseIterable, Identifiable {
    case quickLog, shackClock, portable
    case dxCluster, clubLogSpots, bandmap, callRoster, globeGrids, sixMeter, dxNews, on4kst
    case radioBridge, flrig, tci, rotator, ft8, multiRigFT8, digitalSuite, emulator
    case cwKeyer, cwAcademy, cwReference, cwDecoder, cwPileup, cwHardware
    case contest, calendar, awards, clubs
    case qslHub, qslLabels, logSources, cloudCompanion

    var id: String { rawValue }

    var group: OperatorDeskGroup {
        switch self {
        case .quickLog, .shackClock, .portable: .operating
        case .dxCluster, .clubLogSpots, .bandmap, .callRoster, .globeGrids, .sixMeter, .dxNews, .on4kst: .dxActivity
        case .radioBridge, .flrig, .tci, .rotator, .ft8, .multiRigFT8, .digitalSuite, .emulator: .radioDigital
        case .cwKeyer, .cwAcademy, .cwReference, .cwDecoder, .cwPileup, .cwHardware: .cw
        case .contest, .calendar, .awards, .clubs: .contests
        case .qslHub, .qslLabels, .logSources, .cloudCompanion: .qslData
        }
    }

    var title: String {
        switch self {
        case .quickLog: "Quick Log"
        case .shackClock: "Shack Clock"
        case .portable: "Portable"
        case .dxCluster: "DX Cluster"
        case .clubLogSpots: "Club Log Spots"
        case .bandmap: "Bandmap"
        case .callRoster: "Call Roster"
        case .globeGrids: "Globe & Grids"
        case .sixMeter: "6m Watch"
        case .dxNews: "DX News"
        case .on4kst: "ON4KST Chat"
        case .radioBridge: "Radio Bridge"
        case .flrig: "FLRig"
        case .tci: "TCI SDR"
        case .rotator: "Rotator"
        case .ft8: "FT8 Station"
        case .multiRigFT8: "Multi-Rig FT8"
        case .digitalSuite: "Digital Suite"
        case .emulator: "Emulator"
        case .cwKeyer: "Keyer & Memories"
        case .cwAcademy: "Academy"
        case .cwReference: "Q-Codes & Prosigns"
        case .cwDecoder: "Audio Decoder"
        case .cwPileup: "Pileup Trainer"
        case .cwHardware: "WinKeyer & Hardware"
        case .contest: "Contest Operations"
        case .calendar: "Contest Calendar"
        case .awards: "Awards"
        case .clubs: "Club Memberships"
        case .qslHub: "QSL Hub"
        case .qslLabels: "Labels & Printing"
        case .logSources: "Log Sources & Automation"
        case .cloudCompanion: "Cloud & Companion"
        }
    }

    var detail: String {
        switch self {
        case .quickLog: "Enter contacts, review worked history, and use contest ESM."
        case .shackClock: "Station clocks, propagation, satellites, and mission control."
        case .portable: "Review POTA, SOTA, IOTA, and VUCC activities; export ADIF."
        case .dxCluster: "Connect to DX nodes and discover live spots."
        case .clubLogSpots: "Personal Club Log spots and band opportunities."
        case .bandmap: "View spots by frequency, tune your radio, and inspect the spectrum."
        case .callRoster: "Prioritize needed FT8/FT4 decodes from WSJT-X and the internal modem."
        case .globeGrids: "Explore live activity, grid squares, and antenna bearings."
        case .sixMeter: "Monitor 6-meter openings, propagation evidence, and alerts."
        case .dxNews: "DXpeditions, live news, and weekly bulletins in one place."
        case .on4kst: "Chat with operators and coordinate on-air skeds."
        case .radioBridge: "Hamlib CAT, WSJT-X/JTDX live decodes, and digital QSO review."
        case .flrig: "Connect and control a transceiver through FLRig."
        case .tci: "ExpertSDR / Thetis control, VFO telemetry, and SDR spot streaming."
        case .rotator: "Connect your antenna rotator and set a target azimuth."
        case .ft8: "Operate the native single-radio FT8/FT4 station."
        case .multiRigFT8: "Operate independent FT8 stations across multiple radios."
        case .digitalSuite: "RTTY, PSK, Feld Hell, Olivia, JS8, and SSTV workstations."
        case .emulator: "Test radio clients with a simulated network transceiver."
        case .cwKeyer: "Transmit Morse with memories, live typing, and Auto-CQ."
        case .cwAcademy: "Practice Morse with guided lessons and adaptive training."
        case .cwReference: "Look up Q-codes and Morse prosigns."
        case .cwDecoder: "Decode received CW audio and inspect the signal."
        case .cwPileup: "Practice callsign copying in a simulated pileup."
        case .cwHardware: "Configure CW hardware and inspect WinKeyer diagnostics."
        case .contest: "Manage contest sessions, scoring, multipliers, and Cabrillo export."
        case .calendar: "Plan upcoming contests and start an operating session."
        case .awards: "Track local worked, confirmed, credited, and granted award progress."
        case .clubs: "Look up memberships and exchange numbers."
        case .qslHub: "Sync online confirmations, match incoming cards, and manage paper QSLs."
        case .qslLabels: "Design, calibrate, print, and export adhesive QSL labels."
        case .logSources: "Import logger updates, sync Wavelog, and manage the automatic schedule."
        case .cloudCompanion: "Cloud folder packages, mobile web companion, and local REST API."
        }
    }

    var icon: String {
        switch self {
        case .quickLog: "plus.circle.fill"
        case .shackClock: "deskclock.fill"
        case .portable: "figure.hiking"
        case .dxCluster: "dot.radiowaves.left.and.right"
        case .clubLogSpots: "person.3.fill"
        case .bandmap: "waveform.path.ecg.rectangle"
        case .callRoster: "waveform.and.person.filled"
        case .globeGrids: "globe.americas.fill"
        case .sixMeter: "bolt.badge.clock.fill"
        case .dxNews: "newspaper.fill"
        case .on4kst: "bubble.left.and.bubble.right.fill"
        case .radioBridge: "wave.3.right.circle"
        case .flrig: "slider.horizontal.3"
        case .tci: "antenna.radiowaves.left.and.right"
        case .rotator: "location.north.line.fill"
        case .ft8: "waveform.path"
        case .multiRigFT8: "square.stack.3d.up.fill"
        case .digitalSuite: "teletype"
        case .emulator: "server.rack"
        case .cwKeyer: "tuningfork"
        case .cwAcademy: "graduationcap.fill"
        case .cwReference: "book.closed.fill"
        case .cwDecoder: "headphones"
        case .cwPileup: "antenna.radiowaves.left.and.right.circle"
        case .cwHardware: "cable.connector.horizontal"
        case .contest: "flag.checkered"
        case .calendar: "calendar"
        case .awards: "medal"
        case .clubs: "person.3.sequence.fill"
        case .qslHub: "arrow.left.arrow.right.circle"
        case .qslLabels: "printer.fill"
        case .logSources: "arrow.triangle.2.circlepath"
        case .cloudCompanion: "icloud"
        }
    }

    var legacySection: Int {
        switch self {
        case .quickLog: 0
        case .dxCluster: 1
        case .logSources: 2
        case .radioBridge: 3
        case .contest: 4
        case .qslHub: 5
        case .awards: 6
        case .portable: 7
        case .cloudCompanion: 8
        case .calendar: 9
        case .clubLogSpots: 10
        case .sixMeter: 11
        case .globeGrids: 12
        case .bandmap: 13
        case .cwKeyer, .cwAcademy, .cwReference, .cwDecoder, .cwPileup: 14
        case .clubs: 15
        case .tci: 16
        case .on4kst: 17
        case .cwHardware: 18
        case .qslLabels: 19
        case .callRoster: 20
        case .dxNews: 21
        case .shackClock: 22
        case .digitalSuite: 23
        case .emulator: 24
        case .multiRigFT8: 25
        case .ft8: 26
        case .flrig: 27
        case .rotator: 28
        }
    }

    var cwSection: Int {
        switch self {
        case .cwAcademy: 1
        case .cwReference: 2
        case .cwDecoder: 3
        case .cwPileup: 4
        default: 0
        }
    }

    static func resolve(legacySection: Int, cwSection: Int = 0) -> Self {
        allCases.first { $0.legacySection == legacySection && (legacySection != 14 || $0.cwSection == cwSection) }
            ?? (legacySection == 14 ? .cwKeyer : .quickLog)
    }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let aliases: String = switch self {
        case .logSources: "Sync Center Synchronization Health"
        case .cloudCompanion: "Connect Connected Station Ecosystem"
        case .cwKeyer: "CW Keyer Memories Console"
        case .cwHardware: "WinKeyer USB Serial DTR RTS CAT"
        case .emulator: "Network Transceiver Emulator IC-705"
        case .qslLabels: "QSL Label Designer Print Studio"
        case .sixMeter: "6m Band 6m Magic Band Watch"
        case .clubs: "Clubs Club Memberships"
        case .multiRigFT8: "Multi-Rig Cluster SO2R SO3R"
        case .digitalSuite: "Digital Modes Suite"
        case .awards: "Awards Center"
        case .shackClock: "HamClock Mission Control"
        case .globeGrids: "3D Globe Grid Tracker GridTracker"
        default: ""
        }
        let text = "\(title) \(detail) \(group.title) \(aliases)"
        return terms.allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
}
