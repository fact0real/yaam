//
//  HelpView.swift
//  YAAM
//

import SwiftUI

private enum HelpTopic: String, CaseIterable, Identifiable {
    case start, stations, quickLog, dxCluster, radioBridge, contest, contestCalendar, dxpeditions, magicBand, syncCenter, qslHub, confirmations, qrzIncoming, logAssistant, awards, portable, connectivity, importReview, dataSafety, credentials, workflows, faq
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Getting Started"
        case .stations: return "Station Profiles"
        case .quickLog: return "Quick Log"
        case .dxCluster: return "DX Cluster"
        case .radioBridge: return "Radio & Digital Bridge"
        case .contest: return "Contest Workspace"
        case .contestCalendar: return "Contest Calendar"
        case .dxpeditions: return "DXpedition Watch"
        case .magicBand: return "6m & Propagation"
        case .syncCenter: return "Sync Center"
        case .qslHub: return "QSL Hub"
        case .confirmations: return "Confirmation Reconciliation"
        case .qrzIncoming: return "QRZ Incoming Requests"
        case .logAssistant: return "Log Assistant"
        case .awards: return "Award Engine"
        case .portable: return "Portable Activities"
        case .connectivity: return "Cloud & Mobile"
        case .importReview: return "Import Review"
        case .dataSafety: return "Backup & Restore"
        case .credentials: return "Credentials"
        case .workflows: return "Log Workflows"
        case .faq: return "FAQ"
        }
    }

    var icon: String {
        switch self {
        case .start: return "sparkles"
        case .stations: return "antenna.radiowaves.left.and.right"
        case .quickLog: return "plus.circle.fill"
        case .dxCluster: return "dot.radiowaves.left.and.right"
        case .radioBridge: return "wave.3.right.circle"
        case .contest: return "flag.checkered"
        case .contestCalendar: return "calendar.badge.clock"
        case .dxpeditions: return "binoculars.fill"
        case .magicBand: return "dot.radiowaves.left.and.right"
        case .syncCenter: return "arrow.triangle.2.circlepath"
        case .qslHub: return "arrow.left.arrow.right.circle"
        case .confirmations: return "checklist"
        case .qrzIncoming: return "tray.and.arrow.down.fill"
        case .logAssistant: return "bubble.left.and.text.bubble.right.fill"
        case .awards: return "medal"
        case .portable: return "figure.hiking"
        case .connectivity: return "network"
        case .importReview: return "doc.badge.magnifyingglass"
        case .dataSafety: return "externaldrive.fill.badge.checkmark"
        case .credentials: return "lock.shield.fill"
        case .workflows: return "arrow.triangle.2.circlepath"
        case .faq: return "questionmark.circle"
        }
    }
}

struct HelpView: View {
    @State private var selection: HelpTopic? = .start

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon)
                    .tag(topic)
                    .padding(.vertical, 3)
            }
            .navigationTitle("YAAM Help")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 245)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detail(for: selection ?? .start)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(28)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    @ViewBuilder
    private func detail(for topic: HelpTopic) -> some View {
        switch topic {
        case .start: gettingStarted
        case .stations: stationProfiles
        case .quickLog: quickLog
        case .dxCluster: dxCluster
        case .radioBridge: radioBridge
        case .contest: contest
        case .contestCalendar: contestCalendar
        case .dxpeditions: dxpeditions
        case .magicBand: magicBand
        case .syncCenter: syncCenter
        case .qslHub: qslHub
        case .confirmations: confirmations
        case .qrzIncoming: qrzIncoming
        case .logAssistant: logAssistant
        case .awards: awards
        case .portable: portable
        case .connectivity: connectivity
        case .importReview: importReview
        case .dataSafety: dataSafety
        case .credentials: credentials
        case .workflows: workflows
        case .faq: faq
        }
    }

    private var gettingStarted: some View {
        Group {
            helpHeader(
                title: "A Safer Master Log",
                subtitle: "YAAM keeps each station separate, reviews incoming contacts before merging, and creates restore points around important changes.",
                icon: "shield.lefthalf.filled",
                color: .blue
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Choose a station", detail: "Select the callsign profile in the Log Table toolbar."),
                HelpFlowStep(icon: "square.and.arrow.down", title: "Import or sync", detail: "Open ADIF or SmartSDR directly, or use a configured live source."),
                HelpFlowStep(icon: "doc.badge.magnifyingglass", title: "Review", detail: "Accept new QSOs and confirmation updates; inspect conflicts."),
                HelpFlowStep(icon: "externaldrive.fill.badge.checkmark", title: "Protected save", detail: "The Master Log is committed to SQLite with a restore point.")
            ])
            helpSection("First Setup") {
                HelpInstruction(number: 1, title: "Create or verify your station", text: "Open Settings > Stations. Enter the station callsign, Grid Locator, radio, antenna, and any service-specific identity.")
                HelpInstruction(number: 2, title: "Add online accounts", text: "Use the QRZ.com, LoTW, HAMQTH, and Email tabs, then press the password Save button once. Secret values are stored in macOS Keychain.")
                HelpInstruction(number: 3, title: "Bring in your log", text: "Choose File > Import Log File and select .adi, .adif, or SmartSDR.smartsdrlog. Review the categories and import only the records you intend to keep.")
                HelpInstruction(number: 4, title: "Check protection", text: "Open Settings > Data Safety to verify the database and view automatic restore points.")
                HelpInstruction(number: 5, title: "Open Operator Desk", text: "Use Quick Log during an operating session, DX Cluster for live spots, and Sync Center to monitor every configured log source.")
            }
            helpCallout(icon: "arrow.down.doc.fill", title: "Existing users", text: "On first launch, YAAM copies legacy MasterLogbook ADIF data into the protected database. The original ADIF file is retained as an additional fallback.", color: .green)
        }
    }

    private var stationProfiles: some View {
        Group {
            helpHeader(title: "Station Profiles", subtitle: "Keep home, portable, remote, club, or historical operations distinct without changing contacts by hand.", icon: "antenna.radiowaves.left.and.right", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "plus", title: "Add", detail: "Create a profile in Settings > Stations."),
                HelpFlowStep(icon: "mappin.and.ellipse", title: "Describe", detail: "Set callsign, Grid, QTH, zones, radio, and validity dates."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "Activate", detail: "Use Make Active or the station menu above the log table."),
                HelpFlowStep(icon: "tray.full.fill", title: "Work", detail: "YAAM loads only that profile's Master Log and service key.")
            ])
            helpSection("What Belongs to a Profile") {
                HelpDefinition(icon: "person.text.rectangle", title: "Identity", text: "Profile name, callsign, QTH, country, DXCC, CQ zone, and ITU zone.")
                HelpDefinition(icon: "location.fill", title: "Operating location", text: "Grid Locator, latitude, longitude, and optional start/end dates for historical or portable operation.")
                HelpDefinition(icon: "radio.fill", title: "Station equipment", text: "Radio model, power, antenna description, and antenna height used by DX Advisor and QSL output.")
                HelpDefinition(icon: "key.horizontal.fill", title: "Service identity", text: "LoTW station location, eQSL QTH nickname, and a station-specific QRZ Logbook API key.")
            }
            helpCallout(icon: "exclamationmark.triangle.fill", title: "Deleting a profile", text: "An active profile or a profile that still owns QSOs cannot be deleted. Activate another profile and preserve its contacts first.", color: .orange)
        }
    }

    private var quickLog: some View {
        Group {
            helpHeader(
                title: "Quick Log",
                subtitle: "Log a contact in seconds while YAAM checks callbooks, worked history, and likely duplicates before the QSO reaches the active station's Master Log.",
                icon: "plus.circle.fill",
                color: .blue
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "character.cursor.ibeam", title: "Enter callsign", detail: "YAAM normalizes the call and searches QRZ, HAMQTH, and local history."),
                HelpFlowStep(icon: "waveform.path", title: "Set operation", detail: "Enter frequency; band and common digital submode are inferred."),
                HelpFlowStep(icon: "clock.badge.exclamationmark", title: "Review", detail: "Check worked status and any recent same-band duplicate warning."),
                HelpFlowStep(icon: "checkmark.circle.fill", title: "Log", detail: "Press Command-Return to save to the active station in UTC.")
            ])
            helpSection("Operating Details") {
                HelpDefinition(icon: "globe", title: "UTC throughout", text: "Date and time are recorded in UTC. The current time is suggested when a fresh draft is opened.")
                HelpDefinition(icon: "dial.high", title: "Flexible frequency input", text: "Enter MHz, kHz, or Hz, for example 14.074, 14074, or 14074000. YAAM stores normalized MHz and derives the amateur band.")
                HelpDefinition(icon: "person.crop.circle.badge.checkmark", title: "Two callbooks plus local data", text: "When credentials are available, QRZ and HAMQTH are queried together. Missing details can be filled from earlier contacts in the local log.")
                HelpDefinition(icon: "clock.arrow.2.circlepath", title: "Worked history", text: "The side panel shows total and confirmed QSOs, same-band/mode count, last contact, and whether the callsign or band is new.")
                HelpDefinition(icon: "exclamationmark.triangle.fill", title: "Duplicate guard", text: "An exact duplicate is blocked. A contact with the same callsign, band, and mode in the last 30 minutes asks for explicit confirmation.", color: .orange)
            }
            helpCallout(icon: "scope", title: "From a DX spot", text: "Double-click a spot or use its target button to transfer callsign, frequency, mode, and comment into Quick Log without retyping.", color: .blue)
        }
    }

    private var dxCluster: some View {
        Group {
            helpHeader(
                title: "DX Cluster",
                subtitle: "Follow live Telnet spots with worked and confirmation intelligence from the active station's Master Log.",
                icon: "dot.radiowaves.left.and.right",
                color: .orange
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "network", title: "Connect", detail: "Set a cluster host and port; YAAM sends the active station callsign when prompted."),
                HelpFlowStep(icon: "line.3.horizontal.decrease.circle", title: "Focus", detail: "Filter by need, band, callsign, comment, or watchlist."),
                HelpFlowStep(icon: "scope", title: "Prepare", detail: "Double-click a spot to move it into Quick Log."),
                HelpFlowStep(icon: "checkmark.circle.fill", title: "Complete", detail: "Review RST and details, then save the QSO.")
            ])
            helpSection("Spot Status") {
                HelpDefinition(icon: "sparkles", title: "New callsign", text: "The active station has never worked this callsign.", color: .orange)
                HelpDefinition(icon: "rectangle.split.3x1", title: "New band", text: "The callsign is in the log, but not on the spotted band.", color: .blue)
                HelpDefinition(icon: "clock.arrow.2.circlepath", title: "Worked", text: "The callsign and band have already been worked, but no confirmation is present.", color: .secondary)
                HelpDefinition(icon: "checkmark.seal.fill", title: "Confirmed", text: "A matching callsign and band are confirmed in the Master Log.", color: .green)
            }
            helpSection("Connection & Alerts") {
                HelpDefinition(icon: "arrow.clockwise", title: "Automatic recovery", text: "After an unexpected disconnect, YAAM reconnects with a bounded delay and sends a keep-alive while connected.")
                HelpDefinition(icon: "star.fill", title: "Watchlist", text: "Star a callsign or edit the comma-separated watchlist in connection settings. The Watchlist filter shows only those operators.", color: .yellow)
                HelpDefinition(icon: "speaker.wave.2.fill", title: "Selective sound", text: "Optional sound is limited to watched, new-callsign, and new-band spots to avoid constant noise.")
                HelpDefinition(icon: "rectangle.stack.badge.minus", title: "Efficient stream", text: "Repeated spots are coalesced, updates are applied in batches, and the visible feed is capped to keep long sessions responsive.")
            }
            helpCallout(icon: "person.badge.key.fill", title: "Cluster access", text: "Some cluster nodes require registration, a password, or a different port. Enter the node details supplied by that cluster operator.", color: .orange)
        }
    }

    private var radioBridge: some View {
        Group {
            helpHeader(
                title: "Radio & Digital Bridge",
                subtitle: "Keep rig frequency, digital-mode activity, and Quick Log aligned while retaining explicit control over what reaches the Master Log.",
                icon: "wave.3.right.circle.fill",
                color: .blue
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "radio", title: "Start rigctld", detail: "Run Hamlib rigctld for your radio on the local Mac or trusted LAN."),
                HelpFlowStep(icon: "link", title: "Connect radio", detail: "Use 127.0.0.1 and TCP 4532 unless your rigctld setup differs."),
                HelpFlowStep(icon: "ear", title: "Listen for digital", detail: "Match YAAM's UDP port with WSJT-X or JTDX Reporting settings."),
                HelpFlowStep(icon: "tray.full", title: "Review logged QSOs", detail: "Inspect, import, or dismiss each Logged ADIF message.")
            ])
            helpSection("Hamlib Rig Control") {
                HelpInstruction(number: 1, title: "Configure the radio backend", text: "Start rigctld with the model and serial/network parameters required by your transceiver. YAAM speaks the standard rigctld TCP protocol rather than opening the radio device itself.")
                HelpInstruction(number: 2, title: "Open Operator Desk > Radio Bridge", text: "Enter the rigctld host and port, then press Connect. Frequency, band, mode, and passband update about once per second.")
                HelpInstruction(number: 3, title: "Choose the fill behavior", text: "Use Use in Quick Log for a one-time copy, or enable Fill Quick Log to keep frequency and mode synchronized automatically.")
            }
            helpSection("WSJT-X / JTDX UDP") {
                HelpDefinition(icon: "network", title: "Matching port", text: "The default is UDP 2237. Configure WSJT-X/JTDX to send status and logged ADIF messages to this Mac on the same port.")
                HelpDefinition(icon: "waveform", title: "Live context", text: "YAAM shows dial frequency, mode, selected DX callsign/Grid, and whether the decoder is monitoring, decoding, or transmitting.")
                HelpDefinition(icon: "doc.badge.magnifyingglass", title: "Review-first queue", text: "Logged ADIF packets do not silently enter the Master Log. Exact duplicates are marked and blocked; new entries can be reviewed or imported.", color: .green)
                HelpDefinition(icon: "rectangle.stack.badge.minus", title: "Bounded memory", text: "The listener retains at most 50 pending QSOs and coalesces identical packets so a long digital session stays responsive.")
            }
            helpCallout(icon: "lock.shield", title: "Local-network safety", text: "rigctld has no built-in encryption or authentication. Keep it on localhost or a trusted private network and do not expose its port to the public Internet.", color: .orange)
        }
    }

    private var contest: some View {
        Group {
            helpHeader(
                title: "Contest Workspace",
                subtitle: "Run a UTC contest session, capture exchanges and serials in ADIF, detect same-band/mode dupes, and export Cabrillo 3.0.",
                icon: "flag.checkered",
                color: .orange
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "slider.horizontal.3", title: "Define", detail: "Enter the official contest ID, sent exchange, operator, and category."),
                HelpFlowStep(icon: "play.fill", title: "Start", detail: "YAAM freezes the UTC start and prepares serial 1."),
                HelpFlowStep(icon: "plus.circle.fill", title: "Log", detail: "Quick Log adds CONTEST_ID, STX/STX_STRING, and received exchange."),
                HelpFlowStep(icon: "square.and.arrow.up", title: "Export", detail: "End or pause the session and create a Cabrillo 3.0 .log file.")
            ])
            helpSection("Session Setup") {
                HelpDefinition(icon: "textformat.abc", title: "Contest ID", text: "Use the sponsor's Cabrillo contest identifier, such as CQ-WW-SSB. This value is written to both ADIF and the Cabrillo CONTEST header.")
                HelpDefinition(icon: "number", title: "Exchange and serial", text: "YAAM keeps a persistent next serial and writes the fixed sent exchange separately. Enter the received exchange in Quick Log for every QSO.")
                HelpDefinition(icon: "person.text.rectangle", title: "Categories", text: "Operator, assistance, band, mode, and power become Cabrillo category headers. Select values that match the contest rules and your actual operation.")
                HelpDefinition(icon: "clock", title: "Persistent UTC session", text: "The active session survives an app restart. Ending it records the UTC boundary; Resume continues with the next unused serial.")
            }
            helpSection("During the Contest") {
                HelpInstruction(number: 1, title: "Keep the session active", text: "The orange Contest Exchange block appears in Quick Log and shows the next serial and sent exchange.")
                HelpInstruction(number: 2, title: "Watch the Dupe warning", text: "A callsign already worked on the same band and normalized contest mode is flagged before save. You can still explicitly log it when the contest rules require it.")
                HelpInstruction(number: 3, title: "Review live totals", text: "Contest Workspace reports QSOs, unique callsigns, DXCC entities, bands, duplicates, and the next serial without rescanning outside the current session.")
            }
            helpCallout(icon: "doc.text.magnifyingglass", title: "Verify before submission", text: "Cabrillo layouts and scoring rules vary by sponsor. YAAM emits a standards-based Cabrillo 3.0 log with CLAIMED-SCORE set to zero; calculate the official score and validate categories and exchange columns with the contest sponsor's checker.", color: .blue)
        }
    }

    private var contestCalendar: some View {
        Group {
            helpHeader(title: "Contest Calendar", subtitle: "Use the Operator Desk calendar to pick upcoming operating windows and move quickly into a contest session.", icon: "calendar.badge.clock", color: .blue)
            HelpFlow(steps: [
                HelpFlowStep(icon: "calendar", title: "Review", detail: "Open Operator Desk > Calendar/6m. YAAM loads the current WA7BNM 8-day calendar and keeps the last successful copy available offline."),
                HelpFlowStep(icon: "arrow.up.right.square", title: "Verify", detail: "Open the WA7BNM 5-week calendar for the official schedule and rule links."),
                HelpFlowStep(icon: "flag.checkered", title: "Prepare", detail: "Create or resume a Contest Workspace session with the official contest ID."),
                HelpFlowStep(icon: "square.and.arrow.up", title: "Submit", detail: "Export Cabrillo after the session and validate with the sponsor's checker.")
            ])
            helpSection("Practical Use") {
                HelpDefinition(icon: "location.north.line", title: "Regional focus", text: "YAAM marks worldwide, Asia, Europe, Middle East, and Turkiye events as relevant from Iran. The linked WA7BNM calendar remains authoritative for late changes and full rules.")
                HelpDefinition(icon: "arrow.clockwise", title: "Refresh and cache", text: "Use Refresh to request the latest contest list. A network failure never removes the last successfully loaded calendar.")
                HelpDefinition(icon: "timer", title: "UTC windows", text: "Times are shown in UTC so they match ADIF, Cabrillo, LoTW, and most contest announcements.")
                HelpDefinition(icon: "chart.line.uptrend.xyaxis", title: "Rank growth", text: "Use contests to increase QSO volume, find new DXCC entities, and fill missing bands for QRZ Rank movement.")
            }
        }
    }

    private var magicBand: some View {
        Group {
            helpHeader(title: "6m & Propagation", subtitle: "Combine PSK Reporter evidence, solar context, and regional locator matching to sense whether the Magic Band is worth immediate attention.", icon: "dot.radiowaves.left.and.right", color: .orange)
            HelpFlow(steps: [
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Set station", detail: "Choose the active station callsign before querying PSK Reporter."),
                HelpFlowStep(icon: "arrow.clockwise", title: "Refresh", detail: "Refresh no more than every few minutes; PSK Reporter asks developers to avoid repeated frequent queries."),
                HelpFlowStep(icon: "bolt.circle.fill", title: "React", detail: "When YAAM reports a likely 6m opening, check 50.313 FT8, beacons, and DX Cluster immediately."),
                HelpFlowStep(icon: "checkmark.seal", title: "Confirm", detail: "After QSOs are uploaded and confirmed, LoTW progress updates the local VUCC-style grid count.")
            ])
            helpSection("Evidence Model") {
                HelpDefinition(icon: "6.circle.fill", title: "6m reports", text: "Reports between 50 and 54 MHz are counted separately from HF reception reports.", color: .orange)
                HelpDefinition(icon: "location.north.circle", title: "Near Middle East", text: "YAAM treats LL, LM, LK, KL, and KM grid prefixes as regional evidence around Iran and neighboring paths.", color: .blue)
                HelpDefinition(icon: "sparkles", title: "E-skip context", text: "HamQSL VHF propagation values are used as supporting context, not as a replacement for live reception reports.")
            }
            helpCallout(icon: "exclamationmark.triangle.fill", title: "Opening alerts are advisory", text: "6m can open and close quickly. Treat YAAM's alert as a strong prompt to listen and transmit, not as a guarantee of propagation.", color: .orange)
        }
    }

    private var dxpeditions: some View {
        Group {
            helpHeader(title: "DXpedition Watch", subtitle: "Keep announced operations visible, then distinguish a planned operation from a live spot before changing the radio.", icon: "binoculars.fill", color: .purple)
            HelpFlow(steps: [
                HelpFlowStep(icon: "calendar", title: "Load", detail: "Open Operator Desk > Calendar / 6m. YAAM caches the announced DXpedition list so the most recent successful list remains available offline."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "Verify live activity", detail: "A green on-air indicator appears only when the same callsign is currently present in the DX Cluster feed."),
                HelpFlowStep(icon: "scope", title: "Check need", detail: "YAAM compares the spot with the active station's worked history and labels it as already worked or a good chance to work."),
                HelpFlowStep(icon: "bell.badge", title: "Notify", detail: "Enable DXpedition spot notifications in Contest Interests to receive a one-time alert when a listed callsign is spotted.")
            ])
            helpSection("How to Read the Watch") {
                HelpDefinition(icon: "clock", title: "Planned or active window", text: "Dates describe the announcement window. They do not prove that an operator is transmitting now.")
                HelpDefinition(icon: "dot.radiowaves.left.and.right", title: "On air", text: "This requires current DX Cluster evidence for the exact listed callsign, including band and frequency.", color: .green)
                HelpDefinition(icon: "checkmark.circle", title: "Worked status", text: "A worked marker comes from the active local log. It is not a confirmation or an award credit.")
            }
            helpCallout(icon: "antenna.radiowaves.left.and.right", title: "A timely nudge, not a promise", text: "Cluster spots can be old, mistaken, or unavailable. Tune and verify the callsign before logging a QSO.", color: .orange)
        }
    }

    private var confirmations: some View {
        Group {
            helpHeader(title: "Confirmation Reconciliation", subtitle: "Compare service totals with the local Master Log without hiding records that could not be matched safely.", icon: "checklist", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Sync", detail: "Use Sync QSLs for incremental updates, or Tools > Confirmation Reconciliation > Full History for a complete rebuild."),
                HelpFlowStep(icon: "arrow.left.arrow.right", title: "Match", detail: "YAAM matches callsign, date, band, mode when available, and provider-specific time rules."),
                HelpFlowStep(icon: "checkmark.seal", title: "Import safely", detail: "A confirmed remote record absent from the local log can be imported only when its identity is unambiguous."),
                HelpFlowStep(icon: "exclamationmark.triangle", title: "Investigate", detail: "Ambiguous records stay in the unmatched count instead of being attached to a possibly wrong QSO.")
            ])
            helpSection("Why Counts Can Differ") {
                HelpDefinition(icon: "person.crop.circle.badge.exclamationmark", title: "Station identity", text: "A provider may include a different callsign, portable suffix, or station location than the active YAAM profile.")
                HelpDefinition(icon: "clock.badge.exclamationmark", title: "QSO timing", text: "A clock or UTC-date discrepancy can prevent a safe match even when the callsign is correct.")
                HelpDefinition(icon: "doc.on.doc", title: "Local duplicates and gaps", text: "Provider totals count their confirmations. YAAM's total counts confirmed local QSOs, so duplicates, missing imports, and unmatched contacts remain visible separately.")
            }
            helpCallout(icon: "checkmark.shield", title: "No silent guessing", text: "The reconciliation report shows downloaded, matched, and unmatched items per provider. Use Full History after changing credentials or station identity.", color: .green)
        }
    }

    private var qrzIncoming: some View {
        Group {
            helpHeader(title: "QRZ Incoming Requests", subtitle: "Review confirmation requests from QRZ Logbook and politely collect missing details before creating any local contact.", icon: "tray.and.arrow.down.fill", color: .blue)
            HelpFlow(steps: [
                HelpFlowStep(icon: "key.fill", title: "Sign in", detail: "Use QRZ Login once to create the protected browser session used by QRZ Logbook."),
                HelpFlowStep(icon: "tray.and.arrow.down", title: "Load requests", detail: "Open Log Table > Tools > QRZ Incoming Requests. YAAM loads QRZ's Confirmation Requests page."),
                HelpFlowStep(icon: "magnifyingglass", title: "Check the local log", detail: "Each request is marked when a matching local QSO already exists."),
                HelpFlowStep(icon: "envelope", title: "Request details", detail: "For an unmatched request, select Request Details to prepare a respectful email using the QSL template.")
            ])
            helpSection("Safe Completion") {
                HelpDefinition(icon: "doc.text", title: "Review before creating", text: "The email asks the operator for the QSO date, UTC time, band, mode, reports, and confirmation method. Add a local QSO only after the details are credible.")
                HelpDefinition(icon: "person.badge.key", title: "QRZ session", text: "Incoming requests are read through the user-approved QRZ browser session. If QRZ requires MFA or a browser check, complete it in QRZ Login and refresh.")
                HelpDefinition(icon: "paperplane", title: "Your mail account", text: "YAAM drafts the email with your configured QSL signature and a short yaam.app reference; it does not send mail silently.")
            }
        }
    }

    private var logAssistant: some View {
        Group {
            helpHeader(title: "Log Assistant", subtitle: "Ask practical questions about the active log while keeping external accounts optional and every write operation explicit.", icon: "bubble.left.and.text.bubble.right.fill", color: .indigo)
            HelpFlow(steps: [
                HelpFlowStep(icon: "bubble.left", title: "Ask", detail: "Open Log Table > Tools > Log Assistant and enter a direct question or choose a suggested prompt."),
                HelpFlowStep(icon: "sparkles", title: "Understand", detail: "Without an account, YAAM handles supported local requests. With an OpenAI-compatible account, it also produces a concise explanation from aggregate log context."),
                HelpFlowStep(icon: "hand.raised", title: "Review", detail: "The assistant presents a proposed action such as opening reconciliation or applying an unconfirmed filter."),
                HelpFlowStep(icon: "checkmark.circle", title: "Confirm", detail: "Nothing changes until you press the shown action button.")
            ])
            helpSection("Privacy & Scope") {
                HelpDefinition(icon: "chart.bar", title: "Aggregate context", text: "Remote assistant requests contain station name and totals, not the QSO table, contact emails, or credentials.")
                HelpDefinition(icon: "key.horizontal", title: "Optional account", text: "Configure a compatible HTTPS endpoint, model, and key in Settings > Log Assistant. The key stays in macOS Keychain.")
                HelpDefinition(icon: "lock.shield", title: "Controlled actions", text: "Filtering, synchronizing, and opening views remain YAAM actions with visible confirmation. The assistant cannot independently edit or send your log.")
            }
        }
    }

    private var syncCenter: some View {
        Group {
            helpHeader(
                title: "Sync Center",
                subtitle: "See configuration, health, results, and recent history for every source that can change the active station's Master Log.",
                icon: "arrow.triangle.2.circlepath",
                color: .green
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "gearshape", title: "Configure", detail: "Choose live ADIF or SDR files and add LoTW or QRZ credentials."),
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Sync All", detail: "YAAM processes local sources first, then online confirmations."),
                HelpFlowStep(icon: "checkmark.shield", title: "Verify", detail: "Each source reports success, changes, duration, or a specific failure."),
                HelpFlowStep(icon: "clock.arrow.circlepath", title: "Schedule", detail: "Enable a single automatic interval for configured sources.")
            ])
            helpSection("Source Cards") {
                HelpDefinition(icon: "doc.text.fill", title: "External ADIF", text: "Watches the configured logger file and merges only meaningful additions or updates.")
                HelpDefinition(icon: "radio.fill", title: "SDR-Control", text: "Reads SmartSDR.smartsdrlog directly, ignores entries marked Deleted, normalizes date/time fields, and preserves the SDR Control record ID.")
                HelpDefinition(icon: "checkmark.seal.fill", title: "LoTW", text: "The first successful run builds a complete confirmation baseline for the active callsign. Matching follows call, date, band, and LoTW's 30-minute time window; later runs use the last-QSL cursor.")
                HelpDefinition(icon: "q.square.fill", title: "QRZ Logbook", text: "YAAM pages through every confirmed QRZ entry using APP_QRZLOG_LOGID and rejects an incomplete response instead of saving a partial baseline. Later runs request only records modified since the previous success.")
            }
            helpSection("Status & Performance") {
                HelpDefinition(icon: "circle.dotted", title: "Not configured", text: "The source is skipped until its file or credentials are supplied in Settings.", color: .secondary)
                HelpDefinition(icon: "checkmark.circle.fill", title: "Success", text: "The card records the last successful run, number of fetched items, changed QSOs, and elapsed time.", color: .green)
                HelpDefinition(icon: "exclamationmark.triangle.fill", title: "Needs attention", text: "The source keeps its failure message and time in history so a partial Sync All run is never mistaken for full success.", color: .orange)
                HelpDefinition(icon: "bolt.fill", title: "Indexed matching", text: "Confirmation candidates are indexed by callsign, date, and band before matching, keeping large logs responsive.", color: .yellow)
            }
            helpCallout(icon: "clock.badge.checkmark", title: "Automatic sync", text: "Choose an interval of at least five minutes. YAAM avoids overlapping runs and keeps the latest 100 source results locally.", color: .green)
        }
    }

    private var qslHub: some View {
        Group {
            helpHeader(title: "Two-way QSL Hub", subtitle: "Send QSOs through official service paths, retain every pending job, and bring confirmations back without overwriting the log.", icon: "arrow.left.arrow.right.circle.fill", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "scope", title: "Choose scope", detail: "Use selected rows, 24 hours, unsent records, or the full station log."),
                HelpFlowStep(icon: "checkmark.circle", title: "Choose services", detail: "Enable LoTW, QRZ, eQSL, or Club Log for this batch."),
                HelpFlowStep(icon: "tray.full", title: "Queue", detail: "YAAM saves one durable delivery job per QSO and service."),
                HelpFlowStep(icon: "paperplane.fill", title: "Deliver", detail: "Process controlled batches and inspect success, retry, or blocked status.")
            ])
            helpSection("Service Paths") {
                HelpDefinition(icon: "checkmark.seal", title: "LoTW through TQSL", text: "YAAM creates ADIF and invokes your installed TrustedQSL command-line tool. Set the station location in the active Station Profile.")
                HelpDefinition(icon: "globe.americas", title: "QRZ Logbook", text: "The official INSERT API accepts one QSO per request, so YAAM keeps the queue durable and sends records individually.")
                HelpDefinition(icon: "envelope.badge", title: "eQSL", text: "Uploads can be batched. Download Inbox matches confirmation ADIF to local QSOs and adds EQSL_QSL_RCVD without replacing existing fields.")
                HelpDefinition(icon: "person.3", title: "Club Log", text: "Batch upload uses an application password and API key. Download LoTW State imports Club Log's sent, confirmed, and verified LoTW flags. Club Log matches themselves are not counted as independent DXCC confirmation.")
            }
            helpSection("Recovery Rules") {
                HelpDefinition(icon: "clock.arrow.circlepath", title: "Transient failure", text: "A bounded exponential delay is recorded in SQLite; the job can be resumed after restart.")
                HelpDefinition(icon: "hand.raised.fill", title: "Authentication failure", text: "YAAM stops retrying that job to avoid account lockouts or repeated rejected uploads.", color: .orange)
                HelpDefinition(icon: "checkmark.shield", title: "Sent markers", text: "Only a successful service response updates that service's ADIF sent field and date.", color: .green)
            }
            helpCallout(icon: "arrow.down.circle", title: "Confirmation downloads", text: "The QSL Hub can pull LoTW and QRZ confirmations, eQSL Inbox ADIF, and Club Log's LoTW synchronization state. Each source is matched to the active station log and merged field by field.", color: .blue)
            helpCallout(icon: "exclamationmark.triangle.fill", title: "Large log safety", text: "A scope above 500 QSOs requires confirmation. Previously sent records and completed jobs are skipped, but verify the chosen station and credentials before continuing.", color: .orange)
        }
    }

    private var awards: some View {
        Group {
            helpHeader(title: "Independent Award Engine", subtitle: "Use the Master Log for planning while preserving the difference between contact evidence and an officially issued award.", icon: "medal.fill", color: .orange)
            HelpFlow(steps: [
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Worked", detail: "A unique entity, state, grid, park, island, or summit appears in the log."),
                HelpFlowStep(icon: "checkmark.circle", title: "Confirmed", detail: "At least one accepted confirmation method exists in the QSO."),
                HelpFlowStep(icon: "checkmark.seal", title: "Credited", detail: "An imported ADIF credit field identifies issuer credit where available."),
                HelpFlowStep(icon: "medal", title: "Submitted / Granted", detail: "You record administrative stages after applying to the issuer.")
            ])
            helpSection("Built-in Trackers") {
                HelpDefinition(icon: "globe.americas.fill", title: "DXCC, WAC, and WAS", text: "Tracks unique DXCC entities, populated continents, and US state codes with separate worked and confirmed counts.")
                HelpDefinition(icon: "square.grid.3x3.fill", title: "VUCC", text: "Uses unique four-character Maidenhead grids by band. Targets are 100 for 6 m and 2 m, and 50 for 70 cm.")
                HelpDefinition(icon: "water.waves", title: "IOTA", text: "Provides a 100-group local milestone from standard IOTA references.")
                HelpDefinition(icon: "tree.fill", title: "POTA", text: "Tracks unique hunted parks and qualifying activator park-days with at least 10 QSOs on the same UTC date.")
                HelpDefinition(icon: "mountain.2.fill", title: "SOTA", text: "Tracks unique references and activity. Official summit points are not guessed without the issuer's current summit database.")
            }
            helpCallout(icon: "building.columns", title: "Local estimate, official decision", text: "YAAM helps answer what remains. ARRL, POTA, SOTA, RSGB and other issuing organizations decide accepted credits and award grants.", color: .blue)
        }
    }

    private var portable: some View {
        Group {
            helpHeader(title: "Portable Activities", subtitle: "Capture activator and hunter references during the QSO, then review and export each UTC activity without proprietary fields.", icon: "figure.hiking", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "plus.circle", title: "Open Quick Log", detail: "Expand Portable Activity and choose Standard, Hunter, or Activator."),
                HelpFlowStep(icon: "tag", title: "Add references", detail: "Enter your reference and the contacted station's reference independently."),
                HelpFlowStep(icon: "arrow.forward", title: "Keep context", detail: "Your activator reference remains for the next QSO; contacted references clear."),
                HelpFlowStep(icon: "square.and.arrow.up", title: "Export", detail: "Create one standard ADIF file for the selected reference and UTC date.")
            ])
            helpSection("Standard ADIF Mapping") {
                HelpDefinition(icon: "tree.fill", title: "POTA", text: "Writes MY_POTA_REF/POTA_REF and compatible MY_SIG/SIG information.")
                HelpDefinition(icon: "mountain.2.fill", title: "SOTA", text: "Writes MY_SOTA_REF/SOTA_REF and compatible signal-program fields.")
                HelpDefinition(icon: "water.waves", title: "IOTA", text: "Writes MY_IOTA and IOTA for your and the contacted station's island references.")
                HelpDefinition(icon: "square.grid.3x3", title: "VUCC", text: "Writes MY_VUCC_GRIDS and VUCC_GRIDS. Award analysis reduces contacted locators to the leftmost valid four characters.")
            }
            helpCallout(icon: "calendar.badge.clock", title: "POTA readiness", text: "The Portable view marks a park-day ready at 10 logged QSOs on the same UTC date. POTA performs final validation after upload.", color: .green)
        }
    }

    private var connectivity: some View {
        Group {
            helpHeader(title: "Cloud & Mobile", subtitle: "Move a mergeable station package between Macs and use a private phone dashboard on the local network.", icon: "network", color: .blue)
            HelpFlow(steps: [
                HelpFlowStep(icon: "folder", title: "Choose cloud folder", detail: "Select a folder inside iCloud Drive or another synchronized location."),
                HelpFlowStep(icon: "arrow.down.circle", title: "Pull safely", detail: "YAAM reads the station package and creates a restore point before changes."),
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Merge", detail: "Stable UUIDs and QSO keys add missing records and preserve confirmations."),
                HelpFlowStep(icon: "arrow.up.circle", title: "Push", detail: "The merged, versioned package is written atomically for the next device.")
            ])
            helpSection("Why a Package, Not the Database") {
                HelpDefinition(icon: "externaldrive.badge.xmark", title: "No live SQLite sharing", text: "Cloud services can duplicate or partially synchronize SQLite, WAL, and SHM files. YAAM keeps the active database local.")
                HelpDefinition(icon: "doc.zipper", title: "Versioned package", text: "Each named station profile gets a JSON-based .yaamsync package with format version, device identity, headers, stable QSO IDs, and ADIF fields. YAAM refuses an ambiguous same-callsign merge.")
                HelpDefinition(icon: "externaldrive.fill.badge.checkmark", title: "Restore before merge", text: "A database restore point is created before any incoming package adds or updates QSOs.", color: .green)
            }
            helpSection("Mobile Companion") {
                HelpInstruction(number: 1, title: "Start explicitly", text: "Open Operator Desk > Connect, choose a high local port, and press Start. The server is off at every fresh launch.")
                HelpInstruction(number: 2, title: "Scan or open", text: "Use the QR code or private URL from a phone on the same Wi-Fi or trusted LAN.")
                HelpInstruction(number: 3, title: "Control write access", text: "Disable Allow Quick Log for a read-only dashboard. Rotate the Keychain token whenever a link may have been exposed.")
                HelpDefinition(icon: "list.number", title: "Paginated local API", text: "GET /api/v1/qsos accepts offset and limit. A page is capped at 500 QSOs so a large log cannot stall the phone or desktop app.")
            }
            helpCallout(icon: "lock.shield", title: "Local network only", text: "Do not port-forward the mobile companion to the Internet. The bearer token protects requests, but the local HTTP transport is designed for a trusted private network.", color: .orange)
        }
    }

    private var importReview: some View {
        Group {
            helpHeader(title: "Import Review", subtitle: "See exactly what an ADIF or SmartSDR file will change before it reaches the Master Log.", icon: "doc.badge.magnifyingglass", color: .orange)
            helpSection("Record Categories") {
                HelpDefinition(icon: "plus.circle.fill", title: "New", text: "No matching QSO exists. These records are selected by default.", color: .blue)
                HelpDefinition(icon: "arrow.triangle.2.circlepath.circle.fill", title: "Confirmation update", text: "The contact exists, but the incoming record adds a confirmation or fills a missing field.", color: .green)
                HelpDefinition(icon: "doc.on.doc", title: "Duplicate", text: "The same callsign, date, time, band, and mode already exist with no useful update. It is excluded.", color: .secondary)
                HelpDefinition(icon: "exclamationmark.triangle.fill", title: "Needs review", text: "A similar contact exists within five minutes. It is not selected until you decide both QSOs are valid.", color: .orange)
                HelpDefinition(icon: "xmark.octagon.fill", title: "Invalid", text: "CALL or the eight-digit QSO_DATE is missing. Correct the source record before importing it.", color: .red)
            }
            HelpFlow(steps: [
                HelpFlowStep(icon: "folder", title: "Open log", detail: "Choose an ADIF or SmartSDR file, then Merge into Master Log."),
                HelpFlowStep(icon: "line.3.horizontal.decrease.circle", title: "Filter", detail: "Select a summary category to inspect it."),
                HelpFlowStep(icon: "checkmark.circle", title: "Choose", detail: "Include only intentional new records and conflicts."),
                HelpFlowStep(icon: "square.and.arrow.down", title: "Import", detail: "YAAM backs up, merges, audits, and saves.")
            ])
        }
    }

    private var dataSafety: some View {
        Group {
            helpHeader(title: "Backup & Restore", subtitle: "The Master Log uses a local SQLite database with stable QSO identities, integrity checks, an audit trail, and versioned restore points.", icon: "externaldrive.fill.badge.checkmark", color: .blue)
            helpSection("Automatic Restore Points") {
                HelpDefinition(icon: "calendar.badge.clock", title: "Daily", text: "Created when the log has data and the latest restore point is at least 24 hours old.")
                HelpDefinition(icon: "square.and.arrow.down", title: "Before import", text: "Created before selected ADIF or SmartSDR changes are applied.")
                HelpDefinition(icon: "arrow.triangle.2.circlepath", title: "Around migration", text: "Created before and after legacy ADIF data moves into SQLite.")
                HelpDefinition(icon: "arrow.counterclockwise", title: "Before restore", text: "A rollback point is created immediately before an older version replaces the current database.")
            }
            HelpFlow(steps: [
                HelpFlowStep(icon: "gearshape", title: "Open Data Safety", detail: "Go to Settings > Data Safety."),
                HelpFlowStep(icon: "checkmark.shield", title: "Verify", detail: "Run a SQLite integrity check at any time."),
                HelpFlowStep(icon: "clock.arrow.circlepath", title: "Choose version", detail: "Review date, reason, and file size."),
                HelpFlowStep(icon: "arrow.counterclockwise", title: "Restore", detail: "Profiles and QSOs reload together after validation.")
            ])
            helpCallout(icon: "internaldrive.fill", title: "Stored locally", text: "Restore points remain in YAAM's Application Support folder and are never uploaded by the backup feature.", color: .blue)
        }
    }

    private var credentials: some View {
        Group {
            helpHeader(title: "Credentials & Keychain", subtitle: "Passwords, API keys, and QRZ browser session cookies are protected by the macOS credential store instead of preferences files.", icon: "lock.shield.fill", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "rectangle.and.pencil.and.ellipsis", title: "Enter", detail: "Add the secret in the relevant Settings tab."),
                HelpFlowStep(icon: "key.fill", title: "Protect", detail: "Press Save once to write it to this Mac's Keychain."),
                HelpFlowStep(icon: "network", title: "Use", detail: "The value is read only when contacting that service."),
                HelpFlowStep(icon: "trash.slash", title: "Keep private", detail: "It is not written to preferences or exported with ADIF.")
            ])
            helpSection("Credential Scope") {
                HelpDefinition(icon: "person.crop.circle", title: "Account-wide", text: "QRZ login password, LoTW password, HAMQTH password, and SMTP app password.")
                HelpDefinition(icon: "chart.line.uptrend.xyaxis", title: "QRZ Rank Service", text: "Leaderboard and log enrichment use a separate qrz-rank.asis.sh account after the three-query guest allowance. Configure it in Settings > Rank Service; it is not your QRZ.com account.")
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "Per station", text: "The QRZ Logbook API key follows the active station profile.")
                HelpDefinition(icon: "safari.fill", title: "QRZ session", text: "Saved QRZ cookies support Awards and authenticated lookups, and can be refreshed with QRZ Login.")
            }
            helpCallout(icon: "bolt.slash.fill", title: "No startup interruption", text: "The Master Log loads before online credentials. Keychain values are requested only when their Settings tab or related service is used.", color: .blue)
            helpCallout(icon: "arrow.triangle.2.circlepath", title: "Automatic migration", text: "Existing secrets from older YAAM versions are moved into Keychain after the log is available and removed from ordinary preferences only after a successful transfer.", color: .green)
        }
    }

    private var workflows: some View {
        Group {
            helpHeader(title: "Log Workflows", subtitle: "Import, live sync, confirmations, enrichment, and conversion remain available around the protected Master Log.", icon: "arrow.triangle.2.circlepath", color: .indigo)
            helpSection("Common Tasks") {
                HelpInstruction(number: 1, title: "Log while operating", text: "Open Operator Desk > Quick Log or press Command-L. Command-Return saves a validated QSO.")
                HelpInstruction(number: 2, title: "Work a DX spot", text: "Open Operator Desk > DX Cluster, connect to your node, and double-click a relevant spot to prepare it in Quick Log.")
                HelpInstruction(number: 3, title: "Sync every source", text: "Open Operator Desk > Sync Center and use Sync All, or run only the source you need.")
                HelpInstruction(number: 4, title: "Convert or filter", text: "Open Convert, choose an ADIF or SmartSDR input and an output file, then select an optional UTC range, band, mode, or any combination before processing.")
                HelpInstruction(number: 5, title: "Enrich contacts", text: "Select rows in Log Table or use Enrich Data to add authenticated QRZ Rank values plus available QRZ/HAMQTH identity data.")
                HelpInstruction(number: 6, title: "Backfill rankings", text: "Use Daily Rank in the Log Table toolbar to fill missing rankings for unique callsigns. Progress and the requests remaining today stay visible while it runs.")
                HelpInstruction(number: 7, title: "Review duplicates", text: "Open Database > Review Duplicate QSOs. YAAM groups exact station, callsign, UTC, band, and mode matches, keeps the richest record, merges confirmations, and creates a recovery checkpoint before removal.")
            }
            helpCallout(icon: "gauge.with.dots.needle.67percent", title: "Daily Rank safety", text: "All leaderboard and enrichment lookups share a durable ceiling of 1,440 attempts per local day. The count survives relaunches and resets at local midnight; stopping a backfill keeps every completed result.", color: .green)
            helpCallout(icon: "info.circle.fill", title: "Guest logs", text: "Opening ADIF or SmartSDR as a Guest keeps it outside the active station database. A SmartSDR source is read-only; Save exports a separate ADIF and never overwrites the binary source.", color: .blue)
        }
    }

    private var faq: some View {
        Group {
            helpHeader(title: "Frequently Asked Questions", subtitle: "Short answers for the workflows operators use most often.", icon: "questionmark.circle.fill", color: .blue)
            FAQItem(question: "Where is the WSJT-X ADIF log on macOS?", answer: "In WSJT-X choose File > Open log directory and select wsjtx_log.adi. A common location is ~/.local/share/WSJT-X/wsjtx_log.adi.")
            FAQItem(question: "Can I open a log without merging it?", answer: "Yes. Choose Open as Guest Log in the import prompt. Guest edits are saved or exported separately and do not change the active station Master Log.")
            FAQItem(question: "How does the UTC contest filter handle time and midnight?", answer: "Both pickers and the displayed range are true UTC values rounded to the minute. The start is included and the end is excluded, so 19:00 to 21:00 includes contacts from 19:00:00 through 20:59:59 and can safely cross UTC midnight.")
            FAQItem(question: "Can Convert filter FT8 records stored as MFSK?", answer: "Yes. Mode filtering checks both ADIF MODE and SUBMODE, so selecting FT8 matches records stored as MODE=MFSK and SUBMODE=FT8. Band filtering can also infer a missing BAND from FREQ.")
            FAQItem(question: "Can I import SmartSDR.smartsdrlog without exporting ADIF first?", answer: "Yes. Choose File > Import Log File or select it in Convert. YAAM reads SDR Control's binary property list directly, skips Deleted entries, normalizes QSO date/time, and sends Master Log imports through the same duplicate review used for ADIF.")
            FAQItem(question: "Does DX Advisor use the active station?", answer: "Yes. Grid Locator, radio, power, antenna, and height come from the active station profile.")
            FAQItem(question: "What frequency formats does Quick Log accept?", answer: "MHz, kHz, and Hz are accepted. For 20-meter FT8, 14.074, 14074, and 14074000 resolve to the same frequency and band.")
            FAQItem(question: "Why is a DX spot marked as new?", answer: "Status is calculated from the active station's Master Log. New Callsign means no prior QSO; New Band means the callsign exists but not on that band.")
            FAQItem(question: "Why did Sync All skip a source?", answer: "Only configured sources run. Open the source card or its Settings section and supply the required file, password, or station API key.")
            FAQItem(question: "How do QRZ and LoTW confirmation downloads stay complete?", answer: "Sync QSLs downloads incremental changes. Use the visible Full QSL History button to retrieve both providers from the beginning. YAAM reports downloaded, locally matched, unmatched, and updated counts separately, and never marks an incomplete QRZ page sequence as a successful baseline.")
            FAQItem(question: "What happens when duplicate QSOs are removed?", answer: "YAAM keeps the record with the strongest confirmation evidence and most complete data, fills its missing fields from the duplicates, and removes only the selected extras. A database checkpoint is created first so the operation remains recoverable.")
            FAQItem(question: "Why are tracked rankings unavailable?", answer: "YAAM restores the tracked callsign list and last valid snapshots locally. Live refresh needs a QRZ Rank Service account after its guest allowance expires; configure that separate account in Settings > Rank Service. A service failure never deletes saved rivals.")
            FAQItem(question: "How does Daily Rank choose callsigns?", answer: "It processes each unique callsign with missing QSO, Band, or DXCC rank once per day, newest QSOs first. Existing rank values are copied to duplicate contacts locally before any online request, so they do not consume the daily allowance.")
            FAQItem(question: "What counts toward the 1,440 daily rank limit?", answer: "Every attempted QRZ Rank lookup from Leaderboard, Enrich Data, or Daily Rank uses one slot. The counter is stored locally, survives app restarts, and resets at local midnight. Failed attempts count because they still reached the lookup workflow.")
            FAQItem(question: "Why can I not delete a station?", answer: "The active station cannot be deleted, and a profile that owns QSOs is protected. Activate another profile and preserve or relocate its contacts first.")
            FAQItem(question: "What happens if a restore fails?", answer: "YAAM validates the selected SQLite file and creates a rollback version before replacement. If reopening fails, it attempts to restore the database that was active immediately before the operation.")
            FAQItem(question: "How do I refresh QRZ Awards access?", answer: "Use QRZ Login in the Log Table toolbar, complete any QRZ browser challenge, then return to QRZ Awards and press Refresh.")
            FAQItem(question: "What password should Gmail SMTP use?", answer: "Use a Google App Password, not the normal Google account password. YAAM stores it in macOS Keychain.")
        }
    }

    private func helpHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 54, height: 54)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.largeTitle.weight(.semibold))
                Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func helpSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func helpCallout(icon: String, title: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 17, weight: .semibold)).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct HelpFlowStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

private struct HelpFlow: View {
    let steps: [HelpFlowStep]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                VStack(spacing: 9) {
                    Image(systemName: step.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 40, height: 40)
                        .background(.blue.opacity(0.11), in: Circle())
                    Text(step.title).font(.callout.weight(.semibold)).multilineTextAlignment(.center)
                    Text(step.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                if index < steps.count - 1 {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).padding(.top, 13)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct HelpInstruction: View {
    let number: Int
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted())
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HelpDefinition: View {
    let icon: String
    let title: String
    let text: String
    var color: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 15, weight: .semibold)).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(question).font(.callout.weight(.semibold))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.vertical, 8)
        Divider()
    }
}
