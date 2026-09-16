//
//  HelpView.swift
//  YAAM
//

import SwiftUI

private enum HelpTopic: String, CaseIterable, Identifiable {
    case start, stations, logTable, quickLog, callIntelligence, roverMode, convertExport, globeGrids, greylineOverlay, bandmap, pileupSniper, cwWinKeyer, cwAcademy, competitors, tciSdr, dxCluster, clubLogSpots, on4kst, radioBridge, nteEmulator, multiRigFT8, contest, digitalContest, digitalRoster, contestCalendar, dxpeditions, magicBand, tacticalPilot, hamClockShack, weatherRadar, satellites, clubMembership, syncCenter, lotwTqsl, qslHub, qslLabels, todayQSL, confirmations, statistics, qrzIncoming, logAssistant, awards, portable, connectivity, importReview, dataSafety, credentials, workflows, faq
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Getting Started"
        case .stations: return "Station Profiles"
        case .logTable: return "Log Table & Filters"
        case .quickLog: return "Quick Log"
        case .callIntelligence: return "Call Intelligence Panel (CIP)"
        case .roverMode: return "Tactical Rover Mode"
        case .convertExport: return "Convert & Export"
        case .globeGrids: return "3D Globe & GridTracker"
        case .greylineOverlay: return "Live Greyline & Solar Ducting"
        case .bandmap: return "Spectrum Bandmap & Waterfall"
        case .pileupSniper: return "Pileup Sniper & Split QSX"
        case .cwWinKeyer: return "CW Keyer & WinKeyer"
        case .cwAcademy: return "CW Academy & Audio Decoder"
        case .competitors: return "Competitor Tracking"
        case .tciSdr: return "TCI & SDR Integration"
        case .dxCluster: return "DX Cluster"
        case .clubLogSpots: return "Club Log Live Spots"
        case .on4kst: return "ON4KST Chat & Microwave"
        case .radioBridge: return "Radio, Icom & FT8"
        case .nteEmulator: return "Network Transceiver Emulator (NTE)"
        case .multiRigFT8: return "Multi-Rig FT8 Cluster (SO2R/SO3R)"
        case .contest: return "Contest Workspace"
        case .digitalContest: return "Digital Contest Suite (FT8/FT4)"
        case .digitalRoster: return "Digital Call Roster & Voice Alerts"
        case .contestCalendar: return "Contest Calendar"
        case .dxpeditions: return "DXpedition Watch"
        case .magicBand: return "6m & Propagation"
        case .tacticalPilot: return "Tactical Pilot & HF Propagation"
        case .hamClockShack: return "HamClock & Remote Server"
        case .weatherRadar: return "Station Weather & Lightning Safety"
        case .satellites: return "Satellite & APRS Tracking"
        case .clubMembership: return "International Club Memberships"
        case .syncCenter: return "Sync Center"
        case .lotwTqsl: return "LoTW & TQSL Digital Signing"
        case .qslHub: return "QSL Hub"
        case .qslLabels: return "QSL Card Label Studio"
        case .todayQSL: return "Today's QSL Email Dispatcher"
        case .confirmations: return "Confirmation Reconciliation"
        case .statistics: return "Statistics & Action Center"
        case .qrzIncoming: return "QRZ Incoming Requests"
        case .logAssistant: return "Log Assistant"
        case .awards: return "Awards & Achievements"
        case .portable: return "Portable Activities"
        case .connectivity: return "Cloud & Mobile"
        case .importReview: return "Import Review"
        case .dataSafety: return "Backup & Restore"
        case .credentials: return "Credentials"
        case .workflows: return "Log Workflows"
        case .faq: return "FAQ & Knowledge Base"
        }
    }

    var icon: String {
        switch self {
        case .start: return "sparkles"
        case .stations: return "antenna.radiowaves.left.and.right"
        case .logTable: return "tablecells"
        case .quickLog: return "plus.circle.fill"
        case .callIntelligence: return "brain.head.profile"
        case .roverMode: return "shoeprints.fill"
        case .convertExport: return "square.and.arrow.up.circle.fill"
        case .globeGrids: return "globe.americas.fill"
        case .greylineOverlay: return "sun.horizon.fill"
        case .bandmap: return "waveform.path.ecg.rectangle"
        case .pileupSniper: return "scope"
        case .cwWinKeyer: return "cable.connector.horizontal"
        case .cwAcademy: return "headphones.circle.fill"
        case .competitors: return "chart.line.uptrend.xyaxis"
        case .tciSdr: return "waveform.path.ecg.rectangle"
        case .dxCluster: return "dot.radiowaves.left.and.right"
        case .clubLogSpots: return "person.3.fill"
        case .on4kst: return "bubble.left.and.bubble.right.fill"
        case .radioBridge: return "wave.3.right.circle"
        case .nteEmulator: return "server.rack"
        case .multiRigFT8: return "square.split.3x1.fill"
        case .contest: return "flag.checkered"
        case .digitalContest: return "trophy.fill"
        case .digitalRoster: return "waveform.and.person.filled"
        case .contestCalendar: return "calendar.badge.clock"
        case .dxpeditions: return "binoculars.fill"
        case .magicBand: return "bolt.badge.clock.fill"
        case .tacticalPilot: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .hamClockShack: return "deskclock.fill"
        case .weatherRadar: return "cloud.bolt.rain.fill"
        case .satellites: return "antenna.radiowaves.left.and.right.circle.fill"
        case .clubMembership: return "person.3.sequence.fill"
        case .syncCenter: return "arrow.triangle.2.circlepath"
        case .lotwTqsl: return "signature"
        case .qslHub: return "arrow.left.arrow.right.circle"
        case .qslLabels: return "printer.fill"
        case .todayQSL: return "envelope.badge.shield.half.filled"
        case .confirmations: return "checklist"
        case .statistics: return "chart.bar.doc.horizontal.fill"
        case .qrzIncoming: return "tray.and.arrow.down.fill"
        case .logAssistant: return "bubble.left.and.text.bubble.right.fill"
        case .awards: return "medal"
        case .portable: return "figure.hiking"
        case .connectivity: return "network"
        case .importReview: return "doc.text.magnifyingglass"
        case .dataSafety: return "externaldrive.fill.badge.checkmark"
        case .credentials: return "lock.shield.fill"
        case .workflows: return "arrow.triangle.2.circlepath"
        case .faq: return "questionmark.circle.fill"
        }
    }

    var searchTerms: String {
        switch self {
        case .callIntelligence:
            return "\(title) call intelligence panel cip scp super check partial lotw qrz club memberships cwops skcc licw fists sunrise sunset great circle beam heading propagation muf pileup sniper dxcc entity zone af as eu na sa oc"
        case .pileupSniper:
            return "\(title) pileup sniper split qsx frequency hunter vfo-b arming dx comment parser stepping up stepping down sweet spot cluster wide spread simplex bandmap quicklog reticle cat"
        case .greylineOverlay:
            return "\(title) live greyline grayline solar terminator civil twilight nautical twilight low-band ducting 160m 80m 40m 30m countdown sunrise sunset azimuthal flat map vector shading station solar status"
        case .roverMode:
            return "\(title) rover tactical grid square scout pota sota stepped compass north south east west duration timer auto restore home qth session telemetry qso stamping"
        case .bandmap:
            return "\(title) bandmap spectrum waterfall sdr 3-pane ruler vfo split qsy cat flrig tci hamlib spot hunter panadapter heatmap iaru privileges sniper reticle arming"
        case .clubLogSpots:
            return "\(title) club log live spots cluster activity stream band opportunity recommendation score needed dxcc entities dominant mode oqrs"
        case .clubMembership:
            return "\(title) club membership skcc cwops fists licw 30mdg epc a1 club roster member number auto detect exchange lookup search"
        case .nteEmulator:
            return "\(title) nte network transceiver emulator icom ic-705 ic-7300 ic-7610 ic-9700 hamlib rigctld ci-v udp 50001 50002 50003 tcp 4532 awgn fading rayleigh rician doppler synthetic rf ft8 ft4 cw beacon pileup dsp benchmark test loopback front panel vfo oled spectrum waterfall"
        case .multiRigFT8:
            return "\(title) multi-rig ft8 cluster so2r so3r multi-transceiver icom lan tx-500 x6100 rigctld interlock concurrent strict lockout alternating slots opportunity radar cross-band waterfall dispatch qso radio slot audio routing cmd option 8"
        case .qslLabels:
            return "\(title) qsl labels label studio printing avery 5160 5162 5163 a4 l7160 skip matrix peel off printer alignment calibration pdf export"
        case .lotwTqsl:
            return "\(title) lotw tqsl arrl digital signature default station location ep2aes .p12 certificate private key sign .tq8 sandbox ~/.tqsl synchronize security keychain zero-click upload daemon auto background confirmation reconciliation"
        case .cwAcademy:
            return "\(title) cw academy morse koch method training effective speed farnsworth echo tutor adaptive accuracy audio decoder goertzel fft dsp wpm q-codes abbreviations winkeyer k1el paddle"
        case .hamClockShack:
            return "\(title) hamclock shack clock remote web server local ip tablet ipad sdo solar observatory drap d-region ionosphere absorption sfi ssn kp a-index grayline solar terminator"
        case .tacticalPilot:
            return "\(title) tactical pilot hf propagation voacap snr muf path reliability great circle azimuth beam heading tactical band advisor sdo sunspot 11-band 160m 6m timeline sparkline"
        case .weatherRadar:
            return "\(title) station weather radar nexrad lightning storm detection wind gust antenna safety safety engine alert warning safe zone"
        case .satellites:
            return "\(title) satellite tracking pass aos los doppler shift ao-91 iss amateur radio aprs high altitude balloon telemetry tracking"
        case .todayQSL:
            return "\(title) today qsl email dispatcher 2-page pdf card artwork confirmation certificate batch smtp send anti-dupe duplicate delivery prevention flag"
        case .digitalRoster:
            return "\(title) digital call roster ft8 ft4 js8 wsjt-x jtdx udp voice alerts speech triage new dxcc atno new band new grid reply calling me snr beam heading hands-free"
        case .digitalContest:
            return "\(title) digital contest ft8 ft4 wsjt-x jtdx cabrillo 3.0 multiplier matrix rate meter cq ww digi arrl exchange dupe qso sdr-control waterfall swr alc power master.scp super check partial"
        case .convertExport:
            return "\(title) excel csv cabrillo adif json html text export format contest slice utc band mode"
        case .globeGrids:
            return "\(title) 3d globe gridtracker maidenhead grid square solar terminator grayline propagation day night map azimuthal flat map"
        case .cwWinKeyer:
            return "\(title) cw keyer winkeyer k1el paddle speed wpm macro f1 f12 sidetone serial dtr rts"
        case .competitors:
            return "\(title) competitor rival confirmed qso progress progression curve velocity monthly forecast overtake"
        case .tciSdr:
            return "\(title) tci sdr expertsdr sunsdr cat waterfall vfo transceiver"
        case .on4kst:
            return "\(title) on4kst chat microwave vhf uhf 50mhz 144mhz 432mhz 1296mhz"
        case .logTable:
            return "\(title) chronological UTC row number numbering advanced filters columns hidden database ID band credit grid credit done new have leaderboard ranks center-aligned"
        case .awards:
            return "\(title) QRZ LoTW local progress achievement granted DXCC WAS VUCC WAC WPX 6m grids"
        default:
            return title
        }
    }
}

struct HelpView: View {
    @State private var selection: HelpTopic? = .start
    @State private var searchText = ""
    @State private var showFeedbackSheet = false

    private var visibleTopics: [HelpTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return HelpTopic.allCases }
        return HelpTopic.allCases.filter {
            $0.searchTerms.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search help", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)

                List(visibleTopics, selection: $selection) { topic in
                    Label(topic.title, systemImage: topic.icon)
                        .tag(topic)
                        .padding(.vertical, 3)
                }
            }
            .navigationTitle("YAAM Help")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 245)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    feedbackBanner
                    detail(for: selection ?? .start)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(28)
            }
            .navigationTitle(selection?.title ?? "YAAM Help")
            .sheet(isPresented: $showFeedbackSheet) {
                FeedbackView()
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    private var feedbackBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Have a suggestion, bug report, or feature request?")
                    .font(.subheadline.bold())
                Text("Help shape YAAM! Submit ideas, report shortcomings, or request DX tools directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showFeedbackSheet = true
            } label: {
                Label("Submit Feedback", systemImage: "paperplane.fill")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detail(for topic: HelpTopic) -> some View {
        switch topic {
        case .start: gettingStarted
        case .stations: stationProfiles
        case .logTable: logTable
        case .quickLog: quickLog
        case .callIntelligence: callIntelligenceView
        case .roverMode: roverModeView
        case .convertExport: convertExportView
        case .globeGrids: globeGridsView
        case .greylineOverlay: greylineOverlayView
        case .bandmap: bandmapView
        case .pileupSniper: pileupSniperView
        case .cwWinKeyer: cwWinKeyerView
        case .cwAcademy: cwAcademyView
        case .competitors: competitorsView
        case .tciSdr: tciSdrView
        case .dxCluster: dxCluster
        case .clubLogSpots: clubLogSpotsView
        case .on4kst: on4kstView
        case .radioBridge: radioBridge
        case .nteEmulator: nteEmulatorView
        case .multiRigFT8: multiRigFT8View
        case .contest: contest
        case .digitalContest: digitalContestView
        case .digitalRoster: digitalRosterView
        case .contestCalendar: contestCalendar
        case .dxpeditions: dxpeditions
        case .magicBand: magicBand
        case .tacticalPilot: tacticalPilotView
        case .hamClockShack: hamClockShackView
        case .weatherRadar: weatherRadarView
        case .satellites: satellitesView
        case .clubMembership: clubMembershipView
        case .syncCenter: syncCenter
        case .lotwTqsl: lotwTqslView
        case .qslHub: qslHub
        case .qslLabels: qslLabelsView
        case .todayQSL: todayQSLView
        case .confirmations: confirmations
        case .statistics: statistics
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
            HelpScreenshotCard(
                imageName: "help_log_table",
                title: "Master Log Grid & Workspace",
                caption: "Decluttered sub-toolbar, live DXCC counters, and centered QRZ leaderboard ranks."
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Choose a station", detail: "Select the callsign profile in the Log Table toolbar."),
                HelpFlowStep(icon: "square.and.arrow.down", title: "Import or sync", detail: "Open ADIF or SmartSDR directly, or use a configured live source."),
                HelpFlowStep(icon: "doc.text.magnifyingglass", title: "Review", detail: "Accept new QSOs and confirmation updates; inspect conflicts."),
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

    private var logTable: some View {
        Group {
            helpHeader(
                title: "Log Table & Filters",
                subtitle: "Browse large station logs smoothly, keep only useful columns on screen, and apply repeatable UTC-based filters without changing stored QSO data.",
                icon: "tablecells",
                color: .blue
            )
            HelpScreenshotCard(
                imageName: "help_log_table",
                title: "High-Performance Grid & Sub-Toolbar",
                caption: "Reorganized actions, instant search, custom column sets, and centered Leaderboard ranks."
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "magnifyingglass", title: "Find", detail: "Use the toolbar search to match a callsign, country, grid, email, or any visible ADIF value."),
                HelpFlowStep(icon: "line.3.horizontal.decrease.circle", title: "Filter", detail: "Open Filters to narrow the log by UTC date, band, mode, callsign, country, confirmation state, and more."),
                HelpFlowStep(icon: "arrow.up.arrow.down", title: "Order", detail: "Applying Filters numbers matching QSOs by QSO date and UTC time, newest first, even if you later sort a visible column."),
                HelpFlowStep(icon: "rectangle.3.group", title: "Focus", detail: "Use Columns to reveal an extra field temporarily or hide it again without removing any information from the Master Log.")
            ])
            helpSection("Columns and Stored Data") {
                HelpDefinition(icon: "eye.slash", title: "Hidden is not deleted", text: "Operational and service fields can be hidden by default to keep the table readable. They remain in the protected database and are available from Columns whenever needed.")
                HelpDefinition(icon: "text.aligncenter", title: "Center-Aligned Leaderboard Ranks", text: "Band Rank, DXCC Rank, and QSO Rank columns are center-aligned in both headers and table cells for clean and balanced presentation.", color: .orange)
                HelpDefinition(icon: "menubar.rectangle", title: "Streamlined Sub-Toolbar", text: "Redundant buttons have been eliminated, QSL sync options are unified into Log Actions, and live QSO/DXCC totals reside comfortably in the footer status bar.", color: .blue)
                HelpDefinition(icon: "envelope", title: "Contact and QRZ data", text: "EMAIL, QRZ_URL, and rank columns remain visible by default. Other service bookkeeping fields stay available without crowding daily operation.", color: .blue)
                HelpDefinition(icon: "slider.horizontal.3", title: "Your layout persists", text: "Column visibility is saved for the active station profile and is restored when changing tabs or reopening YAAM.")
                HelpDefinition(icon: "number.square", title: "Filtered UTC sequence", text: "A temporary number appears beside each row only while Advanced Filters are active. Number 1 is the newest visible QSO by UTC date and time; Reset Filters removes these view-only numbers.", color: .blue)
                HelpDefinition(icon: "lock.shield", title: "Internal ID stays hidden", text: "The filtered number is not the database row or record identifier. YAAM keeps its stable internal identity protected so sorting, filtering, importing, and deleting another QSO cannot make the visible number misleading.", color: .secondary)
                HelpDefinition(icon: "flag.2.crossed", title: "Country names stay consistent", text: "YAAM recognizes formal names, capitalization differences, abbreviations, and common legacy spellings as the same country. Federal Republic of Germany becomes Germany, Mt Athos becomes Mount Athos, Rodrigez Is. becomes Rodrigues Island, and Balearic Is. becomes Balearic Islands. Distinct DXCC entities such as Crete, European Russia, and Asiatic Russia remain separate; the ambiguous label Russia is preserved until a callsign or DXCC identifier can resolve it safely.", color: .green)
            }
            helpSection("Confirmation Credit Intelligence") {
                HelpDefinition(icon: "rectangle.stack.badge.plus", title: "BAND CREDIT", text: "For an unconfirmed QSO, NEW means that confirming it would create the first confirmed contact on that band for the contact's country. HAVE means that country-band combination is already confirmed.", color: .blue)
                HelpDefinition(icon: "square.grid.3x3.fill", title: "GRID CREDIT", text: "NEW means confirmation would add a new confirmed four-character Maidenhead grid. YAAM uses the leftmost four grid characters and can derive the grid from latitude and longitude when needed.", color: .mint)
                HelpDefinition(icon: "checkmark.seal.fill", title: "Badge meanings", text: "DONE marks an already confirmed QSO. NEW identifies a useful confirmation opportunity, HAVE means the credit already exists, and N/A means the QSO does not contain enough country, band, grid, or coordinate data.", color: .green)
                HelpDefinition(icon: "flag.checkered", title: "Country band plan", text: "Open Statistics > Country Bands to see every confirmed country as a band matrix. Green is confirmed, orange is worked but unconfirmed, and gray is still needed. Select a confirmed or pending tile to filter the Log Table to those QSOs.", color: .orange)
                HelpDefinition(icon: "bolt.horizontal.circle", title: "Designed for large logs", text: "The credit index is rebuilt only when the Master Log changes. Visible rows use cached lookups, so the two intelligence columns do not repeatedly scan the entire log while you scroll.", color: .secondary)
            }
            helpSection("Filtering Safely") {
                HelpDefinition(icon: "clock", title: "UTC date range", text: "Date filters compare QSO_DATE in UTC. After Apply Filters, matching results are sorted by QSO_DATE and TIME_ON, newest first.", color: .green)
                HelpDefinition(icon: "checkmark.seal", title: "Confirmation filter", text: "Confirmed means a local QSO has a recognized LoTW, QRZ, eQSL, or QSL confirmation. Sync QSLs or Full QSL History refreshes these fields from configured services.")
                HelpDefinition(icon: "xmark.circle", title: "Reset without risk", text: "Reset Filters clears only the temporary filter rules. It never removes QSOs, confirmations, or enrichment fields from the Master Log.", color: .orange)
            }
            helpCallout(icon: "cursorarrow.rays", title: "Fast large-log browsing", text: "Rows are rendered lazily and the table header stays visible while scrolling. Use search or filters before opening a wide set of auxiliary ADIF columns for the quickest review of a large log.", color: .blue)
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
            HelpScreenshotCard(
                imageName: "help_operator_desk",
                title: "Operator Desk & Studio Hub",
                caption: "Two-way confirmation status matrix, live dropzone, and multi-service synchronization."
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

    private var roverModeView: some View {
        Group {
            helpHeader(
                title: "Tactical Rover Mode",
                subtitle: "Temporarily project your station to alternate Maidenhead grids for POTA, SOTA, VHF/UHF rovering, and propagation exploration with automatic timer restore, compass grid stepping, and live telemetry.",
                icon: "shoeprints.fill",
                color: .orange
            )

            HelpScreenshotCard(
                imageName: "help_rover_mode",
                title: "Tactical Rover Cockpit & Geodesic Telemetry",
                caption: "Temporary grid override, compass grid stepper, and geodesic distance & bearing telemetry."
            )

            HelpRoverModeMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "figure.walk", title: "1. Open Rover Sheet", detail: "Click the Rover pill in the top navigation bar or choose Tools > Rover Mode (or press Option-Command-R)."),
                HelpFlowStep(icon: "mappin.and.ellipse", title: "2. Set Target Grid", detail: "Enter any 4- or 6-character Maidenhead locator (e.g. LL46) or select from built-in and custom presets."),
                HelpFlowStep(icon: "clock.badge.checkmark", title: "3. Choose Duration", detail: "Select 1 Hour (Quick Scout), 4 Hours (Half-Day), 8 Hours, Until End of UTC Day, or Manual Indefinite."),
                HelpFlowStep(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "4. Compass Stepping", detail: "As your vehicle travels, tap North, South, East, or West to advance squares in real time."),
                HelpFlowStep(icon: "arrow.uturn.backward.circle.fill", title: "5. Automatic Safe Return", detail: "When time expires or on manual deactivation, YAAM cleanly reverts to your home QTH with voice confirmation.")
            ])

            helpSection("Non-Destructive Station Projection") {
                HelpDefinition(
                    icon: "shield.lefthalf.filled",
                    title: "Master Profile Isolation",
                    text: "Rover Mode intercepts effective grid and geographic coordinates in memory for all real-time tools (Tactical Pilot, DX Cluster, 3D Globe, Bandmap, HamClock) without modifying your permanent SQLite database station profile.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "tag.fill",
                    title: "Outbound QSO Stamping",
                    text: "When 'Stamp MY_GRIDSQUARE in outgoing QSOs' is enabled, QSOs logged via Quick Log, WSJT-X, or FT8 record your current rover grid and QTH, ensuring accurate logs for POTA activators and VHF rover contests.",
                    color: .green
                )
            }

            helpSection("4-Way Compass Grid Stepper") {
                HelpDefinition(
                    icon: "compass.drawing",
                    title: "Mathematical Maidenhead Indexing",
                    text: "The stepper increments and decrements field and square indices along longitude and latitude. Longitude wraps around the globe (0 to 179 squares) while latitude clamps safely to polar limits.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "character.textbox",
                    title: "Subsquare Preservation",
                    text: "If you enter a 6-character locator (e.g. LL46ab), stepping to neighboring squares preserves your precision subsquares (e.g. LL47ab) automatically.",
                    color: .secondary
                )
            }

            helpSection("Geodesic Telemetry & Audio Feedback") {
                HelpDefinition(
                    icon: "ruler.fill",
                    title: "Live Distance & Bearing",
                    text: "Continuously computes geodesic distance in kilometers and miles, initial great-circle bearing, and 16-point compass heading relative to your permanent home QTH.",
                    color: .purple
                )
                HelpDefinition(
                    icon: "sun.horizon.fill",
                    title: "Astronomical Solar Window",
                    text: "Calculates exact UTC sunrise and sunset times for the rover grid, helping you anticipate low-band grayline openings on location.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "speaker.wave.3.fill",
                    title: "Voice Announcements & Audio Chimes",
                    text: "Distinct macOS chimes sound on activation, extension (+1 Hour), and deactivation. If Voice Alerts are enabled, the speech synthesizer announces status changes hands-free.",
                    color: .teal
                )
            }

            helpCallout(
                icon: "sparkles",
                title: "Top Navigation Status Pill",
                text: "While Rover Mode is active, an amber glowing pill in the window title bar displays your active grid and remaining countdown time. Click it at any time to adjust duration or return home with one click.",
                color: .orange
            )
        }
    }

    private var callIntelligenceView: some View {
        Group {
            helpHeader(
                title: "Call Intelligence Panel (CIP)",
                subtitle: "Deep multi-database tactical HUD integrating DXCC prefix resolution, Super Check Partial (SCP), LoTW & QRZ activity, international club memberships, solar ephemeris, and live point-to-point HF propagation.",
                icon: "brain.head.profile",
                color: .yellow
            )

            HelpScreenshotCard(
                imageName: "help_call_intelligence",
                title: "Call Intelligence Panel (CIP) HUD",
                caption: "Multi-layered operator intelligence displaying DXCC entity, SCP matching, LoTW verification, and live HF propagation."
            )

            HelpCallIntelligenceMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "character.cursor.ibeam", title: "1. Type or Spot Callsign", detail: "As soon as you enter 2+ characters in QuickLog or click a spot in Bandmap or DX Cluster, CIP immediately activates."),
                HelpFlowStep(icon: "flag.fill", title: "2. Resolve Entity & Geodesics", detail: "Instantly extracts country flag, DXCC entity, CQ/ITU zones, continent, beam heading, and distance in km/miles."),
                HelpFlowStep(icon: "signature", title: "3. Verify LoTW & Clubs", detail: "Cross-checks against the embedded 50,000+ LoTW activity database and international club rosters (CWops, SKCC, FISTS, LICW, 30MDG, EPC, A1)."),
                HelpFlowStep(icon: "magnifyingglass", title: "4. SCP Autocomplete", detail: "Super Check Partial highlights valid contest callsigns matching your keystrokes to prevent busted calls."),
                HelpFlowStep(icon: "waveform.path.ecg", title: "5. Propagation & Split Target", detail: "Computes path MUF/LUF, recommended band, and displays the Pileup Sniper radar if the DX is operating split.")
            ])

            helpSection("Multi-Database Operator Intelligence") {
                HelpDefinition(
                    icon: "globe.americas.fill",
                    title: "Prefix & Geodesic Calculation",
                    text: "Uses high-precision CTY database matching with prefix overrides. Continuously computes true great-circle short-path (SP) and long-path (LP) headings from your active station (or Rover grid).",
                    color: .cyan
                )
                HelpDefinition(
                    icon: "sun.max.fill",
                    title: "Solar Ephemeris at DX",
                    text: "Calculates the exact local solar time and current solar elevation angle at the target station, highlighting whether they are in daylight, night, or golden twilight hours.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "person.3.sequence.fill",
                    title: "International Club Rosters",
                    text: "Identifies memberships across 7 major telegraphy and digital clubs with official membership numbers, aiding contest exchanges and ragchew QSOs.",
                    color: .purple
                )
            }

            helpSection("Super Check Partial (SCP) Engine") {
                HelpDefinition(
                    icon: "bolt.shield.fill",
                    title: "Contest Call Verification",
                    text: "Scans the MASTER.SCP active contester database using Levenshtein distance algorithms. Click any suggested callsign to replace or autofill QuickLog instantaneously.",
                    color: .yellow
                )
            }

            helpSection("Point-to-Point Propagation & Split Hunting") {
                HelpDefinition(
                    icon: "chart.xyaxis.line",
                    title: "Integrated MUF & Band Radar",
                    text: "Directly embeds point-to-point propagation predictions, displaying current circuit reliability, expected SNR in dB, and a 24-hour UTC forecast sparkline.",
                    color: .teal
                )
                HelpDefinition(
                    icon: "scope",
                    title: "Pileup Sniper Radar Card",
                    text: "When cluster comments indicate split operation (e.g. 'UP 5', 'QSX 14025'), CIP renders the tactical Sniper card with VFO-B recommendation and 1-click arming.",
                    color: .green
                )
            }
        }
    }

    private var pileupSniperView: some View {
        Group {
            helpHeader(
                title: "Pileup Sniper & Split QSX Frequency Hunter",
                subtitle: "Tactical DX split analysis assistant that parses cluster comment shorthand, models DX operator listening trajectories, predicts optimal transmit frequencies, and arms VFO-B with a single click.",
                icon: "scope",
                color: .orange
            )

            HelpScreenshotCard(
                imageName: "help_pileup_sniper",
                title: "Pileup Sniper Tactical HUD & Split Radar",
                caption: "Live split spectrum tracking, DX operator trajectory forecasting (Stepping UP), and 1-click VFO-B arming."
            )

            HelpPileupSniperMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "text.magnifyingglass", title: "1. Cluster Spot Parsing", detail: "Engine reads verbal DX shorthand comments such as 'UP 5-10', 'WKD +3.5', 'QSX 14.025', 'DN 2', or 'SIMPLEX'."),
                HelpFlowStep(icon: "chart.line.uptrend.xyaxis", title: "2. Trajectory Modeling", detail: "Analyzes recent hit points with 20-minute exponential time-decay to detect whether the DX is stepping UP, stepping DOWN, or clustering."),
                HelpFlowStep(icon: "target", title: "3. Reticle Positioning", detail: "Calculates the optimal transmit frequency (including a +150 Hz offset in clusters to punch through zero-beat QRM)."),
                HelpFlowStep(icon: "bolt.horizontal.fill", title: "4. One-Click Arming", detail: "Click [ARM VFO-B] to instantly tune VFO-B and activate Split Transceive without altering VFO-A.")
            ])

            helpSection("Trajectory Recognition & Patterns") {
                HelpDefinition(
                    icon: "arrow.up.right.circle.fill",
                    title: "Stepping UP Trajectory",
                    text: "Detects when the DX operator systematically moves higher after each contact. The engine predicts the next step above the last worked frequency, wrapping around to the split floor if an explicit ceiling was reached.",
                    color: .green
                )
                HelpDefinition(
                    icon: "arrow.down.right.circle.fill",
                    title: "Stepping DOWN Trajectory",
                    text: "Tracks downward tuning cycles, recommending frequencies just below the last QSO to stay ahead of the pack.",
                    color: .cyan
                )
                HelpDefinition(
                    icon: "scope",
                    title: "Sweet Spot Clustering (+150 Hz Offset)",
                    text: "When calls are concentrated around a specific frequency, the engine calculates the weighted mean and applies a +150 Hz pitch offset to help your signal punch through heavy zero-beat QRM.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "waveform.path",
                    title: "Wide Spread Hunting",
                    text: "In broad splits (e.g. UP 5-10), the engine aims in the upper third of the window where caller density is lower and signal copy is cleaner.",
                    color: .purple
                )
            }

            helpSection("Zero-Duplication Transceiver Integration") {
                HelpDefinition(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "VFO-A RX Preservation",
                    text: "Arming split updates only VFO-B (TX) in BandmapEngine and sends CAT commands to your radio, keeping your VFO-A receiver strictly locked on the DX station.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "ruler.fill",
                    title: "Bandmap Ruler Reticle",
                    text: "A glowing yellow reticle marker appears on the vertical Bandmap frequency ruler at the predicted transmit frequency. Clicking it selects the solution immediately.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "bolt.badge.clock.fill",
                    title: "QuickLog Transceiver Desk Badge",
                    text: "A compact [🎯 SPLIT +X.X kHz] badge lights up in the QuickLog transceiver header, allowing split arming directly from the log entry desk.",
                    color: .orange
                )
            }
        }
    }

    private var greylineOverlayView: some View {
        Group {
            helpHeader(
                title: "Live Greyline Propagation Overlay & Solar Ducting",
                subtitle: "Vector-grade astronomical solar terminator and civil/nautical twilight contours with live station solar status, next event countdown, and great-circle low-band ducting path detection.",
                icon: "sun.horizon.fill",
                color: .orange
            )

            HelpScreenshotCard(
                imageName: "help_greyline_overlay",
                title: "Vector Greyline & Solar Ephemeris HUD",
                caption: "Continuous vector twilight contours, triple-stroke glowing terminator ribbon, and live station ducting telemetry."
            )

            HelpGreylineOverlayMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "sun.max.fill", title: "1. Solar Ephemeris", detail: "Solves spherical solar altitude equations in real time to locate the exact subsolar point and declination."),
                HelpFlowStep(icon: "pencil.and.outline", title: "2. Vector Contours", detail: "Generates continuous vector ribbons for the optical terminator (0°), civil twilight (-6°), and nautical twilight (-12°)."),
                HelpFlowStep(icon: "eye.fill", title: "3. Shaded Polar Mesh", detail: "Renders seamless day, twilight, and night shading on both 3D Globe, Azimuthal Equidistant, and Flat maps."),
                HelpFlowStep(icon: "bolt.fill", title: "4. Ducting Telemetry", detail: "Calculates low-band ionospheric ducting efficiency and highlights Great Circle paths coinciding with the twilight band.")
            ])

            helpSection("Astronomical & Ionospheric Physics") {
                HelpDefinition(
                    icon: "sun.horizon.fill",
                    title: "Low-Band Ionospheric Ducting",
                    text: "During twilight, solar ultraviolet radiation stops ionizing the lower ionosphere, causing the signal-absorbing D-layer to rapidly collapse while the reflective F2-layer remains charged. This creates a low-loss waveguide for 160m, 80m, 40m, and 30m signals.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "waveform.path.ecg",
                    title: "Great Circle Path Coincidence (+35 dB Bonus)",
                    text: "When a great circle path between your station and a spotted DX station traverses the twilight corridor, YAAM renders the beam with a golden halo and applies up to +35 dB ducting bonus in propagation scoring.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "deskclock.fill",
                    title: "Station Solar HUD & Countdown",
                    text: "A floating glassmorphism widget in the map canvas displays real-time solar elevation, low-band ducting percentage, and an exact countdown to the next solar event (e.g. 'Sunset in 5h 20m').",
                    color: .blue
                )
            }

            helpSection("Full Rover Mode Synchronization") {
                HelpDefinition(
                    icon: "shoeprints.fill",
                    title: "Mobile Twilight Adaptation",
                    text: "When Tactical Rover Mode is active, all solar calculations, twilight horizon angles, and ducting timers instantly adapt to the rover's Maidenhead grid coordinates.",
                    color: .purple
                )
            }
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

            HelpScreenshotCard(
                imageName: "help_dx_cluster",
                title: "Live DX Cluster",
                caption: "Real-time spot monitoring, band filters, needed entity alerts, and 1-click Quick Log fill."
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

    private var clubLogSpotsView: some View {
        Group {
            helpHeader(
                title: "Club Log Live Spots & Band Intelligence",
                subtitle: "Real-time activity stream from Club Log cluster servers, automatic DXCC band-need cross referencing, and the Band Opportunity Recommendation Engine.",
                icon: "person.3.fill",
                color: .blue
            )

            HelpClubLogSpotsMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "network", title: "1. Open Club Log Desk", detail: "Select the 'Club Log' tab (Tag 10) in Operator Desk to establish a persistent live stream."),
                HelpFlowStep(icon: "flame.fill", title: "2. Inspect Band Opportunity", detail: "Review the top banner recommendation scoring all amateur bands by active spot density and needed DXCC entities."),
                HelpFlowStep(icon: "line.3.horizontal.decrease.circle", title: "3. Filter Mode & Band", detail: "Filter by Digital (FT8/FT4), CW, or Phone/Voice, or type to search specific prefixes or DXpedition callsigns."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "4. One-Click QSY & Log", detail: "Click 'Tune Rig' on any spot to send CAT commands to your transceiver and immediately stage the contact.")
            ])

            helpSection("Band Opportunity & Recommendation Engine") {
                HelpDefinition(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Smart Scoring Algorithm",
                    text: "YAAM evaluates every live spot against your active station's confirmed DXCC matrix: Score = Total Spots + (Needed DXCC * 3.5). This prioritizes bands with high DX value rather than just high raw traffic.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Dominant Mode Detection",
                    text: "Identifies whether the activity on a recommended band is predominantly FT8, CW, or SSB, so you can configure your transceiver filters before tuning.",
                    color: .blue
                )
            }

            helpSection("Entity Intelligence & Status Tags") {
                HelpDefinition(icon: "sparkles", title: "ATNO (All-Time New One)", text: "Highlighted in purple when the spotted entity has never been worked on any band in your Master Log.", color: .purple)
                HelpDefinition(icon: "rectangle.split.3x1", title: "Needed Band", text: "Highlighted in green when the DXCC entity is confirmed on other bands, but still needed on the spotted band.", color: .green)
                HelpDefinition(icon: "checkmark.seal.fill", title: "Confirmed Entity", text: "Marked in secondary styling when your station already holds an accepted confirmation for this band.", color: .secondary)
            }

            helpCallout(
                icon: "globe",
                title: "Complementary to DX Cluster",
                text: "Unlike raw Telnet clusters, Club Log spots are cross-referenced with Club Log's global database of active stations and propagation models, filtering out invalid callsigns and bad spots.",
                color: .blue
            )
        }
    }

    private var radioBridge: some View {
        Group {
            helpHeader(
                title: "Radio, Icom & FT8",
                subtitle: "Control a rig, monitor WSJT-X/JTDX, or operate YAAM's native FT8 station with explicit receive, sequencing, and transmit safety controls.",
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
                HelpDefinition(icon: "doc.text.magnifyingglass", title: "Review-first queue", text: "Logged ADIF packets do not silently enter the Master Log. Exact duplicates are marked and blocked; new entries can be reviewed or imported.", color: .green)
                HelpDefinition(icon: "rectangle.stack.badge.minus", title: "Bounded memory", text: "The listener retains at most 50 pending QSOs and coalesces identical packets so a long digital session stays responsive.")
            }
            helpSection("Native FT8 with IC-7300MKII or IC-705") {
                HelpFlow(steps: [
                    HelpFlowStep(icon: "network", title: "Enable Icom LAN", detail: "Enable Network Control, CI-V Transceive, and DATA MOD = WLAN, then create the Icom network user."),
                    HelpFlowStep(icon: "link", title: "Connect", detail: "Choose the radio, enter its LAN address and control port, then connect from FT8 Station."),
                    HelpFlowStep(icon: "waveform.path.ecg", title: "Monitor", detail: "Choose an FT8 dial frequency, set USB-D, and allow one complete 15-second UTC slot."),
                    HelpFlowStep(icon: "paperplane.fill", title: "Reply safely", detail: "Select a decode, review the generated message, arm TX, and send in the opposite sequence.")
                ])
                HelpInstruction(number: 1, title: "Open Operator Desk > Radio Bridge > FT8 Station", text: "Direct Icom LAN carries login, CI-V control, and 48 kHz LPCM16 receive/transmit audio over separate UDP streams. Set DATA MOD to WLAN so keyed FT8 audio reaches the transmitter. Connect keeps the password only for the current session; press the key button only when you explicitly want to save it in macOS Keychain. It is never written into preferences or the log database.")
                HelpInstruction(number: 2, title: "Verify the receive path", text: "Press Start Monitoring and watch the waterfall. Decode results appear after a full UTC slot. Use the audio passband from 200 to 3000 Hz and keep macOS time synchronization enabled.")
                HelpInstruction(number: 3, title: "Prepare a standard exchange", text: "Prepare CQ or choose a decoded CQ/message addressed to your callsign. YAAM selects the opposite odd/even sequence and advances Grid, report, R-report, RR73, and 73 messages.")
                HelpInstruction(number: 4, title: "Arm only when ready", text: "Check the callsign, Grid, dial frequency, audio offset, antenna path, and RF power before enabling Arm TX. Send at Next Slot schedules against the UTC slot boundary.")
                HelpInstruction(number: 5, title: "Diagnose without a crash", text: "Cancel stops an in-progress handshake. If the host, port, login, or radio network service rejects the connection, YAAM keeps the station offline and shows the exact failure beneath the connection controls so you can correct it and retry.")
            }
            helpSection("Audio, Timing & Safety") {
                HelpDefinition(icon: "cable.connector.horizontal", title: "Two audio paths", text: "Direct Icom LAN is available for IC-7300MKII and IC-705. The rigctld + Audio path works with a selected Core Audio input/output and uses Hamlib only for frequency, mode, and PTT.", color: .blue)
                HelpDefinition(icon: "clock.badge.checkmark", title: "UTC synchronization", text: "FT8 uses exact 15-second periods. A Mac clock error can prevent decoding or make transmissions overlap; leave automatic date and time enabled.", color: .orange)
                HelpDefinition(icon: "checkmark.shield", title: "Offline self-test", text: "Run Offline Self-Test before RF operation. It verifies CI-V frequency encoding, protected local UDP transport, 79 FT8 tones, 12 kHz waveform generation, loopback decode, and odd/even UTC slot timing. It does not contact or key the radio.", color: .green)
                HelpDefinition(icon: "stop.circle.fill", title: "Hard PTT Release & Dynamic Watchdog", text: "TX requires an explicit arm switch, and an exact protocol watchdog (15.0s for FT8, 7.5s for FT4) automatically releases transmitter PTT after cancellation, network failure, or a stalled slot.", color: .red)
                HelpDefinition(icon: "gauge.with.needle", title: "Live Radio Meters & SDR Waterfall", text: "Direct Icom CI-V polling reads forward RF Power (0-100W), SWR with smart safety thresholds (emerald/amber/red), and ALC level. The SDR-Control 240-row waterfall keeps 30s of continuous history.", color: .orange)
            }
            helpCallout(icon: "antenna.radiowaves.left.and.right", title: "First transmission", text: "Begin with a dummy load or minimum RF power. Keep ALC inactive, verify the selected audio device and frequency, and remain able to stop the radio locally before enabling automatic sequencing.", color: .orange)
            helpCallout(icon: "lock.shield", title: "Local-network safety", text: "Keep rigctld and direct Icom LAN on localhost or a trusted private network. Do not expose either control port to the public Internet; use a trusted VPN when remote access is required.", color: .orange)
        }
    }

    private var nteEmulatorView: some View {
        Group {
            helpHeader(
                title: "Network Transceiver Emulator (NTE)",
                subtitle: "Full hardware-grade emulation of modern network transceivers (Icom IC-705, IC-7300/MK2, IC-7610, IC-9700) with CI-V over IP, 48 kHz LPCM16 streaming audio, built-in Hamlib rigctld, and a synthetic RF physics engine.",
                icon: "server.rack",
                color: .blue
            )

            HelpNTEMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "power.circle.fill", title: "1. Power ON Transceiver", detail: "Open Network Transceiver Emulator (Tools > Transceiver Emulator, Option-Command-E, or Operator Desk Tab 24) and click Power Transceiver ON."),
                HelpFlowStep(icon: "network", title: "2. Bind Control & rigctld Ports", detail: "NTE binds UDP 50001 (Control), UDP 50002 (CI-V), UDP 50003 (Audio), and TCP 4532 (Hamlib rigctld) for immediate client connectivity."),
                HelpFlowStep(icon: "waveform.path", title: "3. Configure Channel Physics", detail: "Select channel fading (Clean, Mild QSB, Deep Rayleigh, Auroral), set calibrated AWGN SNR (-30 dB to +30 dB), or inject Doppler drift."),
                HelpFlowStep(icon: "waveform.badge.plus", title: "4. Inject Synthetic Signals", detail: "Activate FT8/FT4 signal synthesis, 5-station pileups, CW beacons, or inject custom callsigns aligned with UTC 15-second time slots."),
                HelpFlowStep(icon: "link.circle.fill", title: "5. Connect YAAM or WSJT-X", detail: "Click 'Connect YAAM LAN' to test YAAM's internal receiver in loopback, or point WSJT-X / JTDX to localhost:4532 via Hamlib rigctld.")
            ])

            helpSection("Network & Protocol Architecture") {
                HelpDefinition(
                    icon: "server.rack",
                    title: "Icom LAN Three-Socket UDP Stack",
                    text: "Implements authentic Icom network protocols: UDP 50001 handles broadcast discovery and handshake tokens; UDP 50002 processes 0x01C0 framing for CI-V frequency, mode, and S-meter registers; UDP 50003 streams uncompressed 48 kHz LPCM16 audio frames at strict 10ms intervals.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "cable.connector.horizontal",
                    title: "Built-In Hamlib rigctld Server (TCP 4532)",
                    text: "A native non-blocking TCP socket server supporting standard Hamlib commands ('f', 'F', 'm', 'M', 't', 'T', 'l', '\\dump_state'). Third-party apps like WSJT-X, JTDX, and N1MM connect with zero configuration and no external virtual serial cables.",
                    color: .purple
                )
                HelpDefinition(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Local Network Auto-Discovery",
                    text: "Responds to UDP broadcast discovery probes, allowing external companion software like wfview or SDR-Control on your LAN to discover the emulator automatically as if it were a physical radio.",
                    color: .cyan
                )
            }

            helpSection("Synthetic RF & Channel Physics Engine") {
                HelpDefinition(
                    icon: "waveform.path.ecg",
                    title: "Calibrated AWGN & Box-Muller Noise",
                    text: "Generates true additive white Gaussian noise precisely calibrated in a 2.5 kHz bandwidth across a -30 dB to +30 dB SNR range, allowing rigorous receiver sensitivity evaluations.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "wind",
                    title: "Ionospheric Multipath Fading",
                    text: "Models real-world HF ionospheric propagation including Mild QSB (0.2 Hz Doppler spread), Deep Rayleigh flutter (1.5 Hz spread), and high-latitude Auroral flutter (4.0 Hz spread) through complex Gaussian filtering.",
                    color: .teal
                )
                HelpDefinition(
                    icon: "arrow.left.arrow.right",
                    title: "Doppler Shift & Frequency Drift",
                    text: "Simulates satellite passes and ionospheric layer dynamics with continuous phase accumulation supporting static offsets up to ±500 Hz and linear frequency drift up to ±100 Hz/minute.",
                    color: .indigo
                )
                HelpDefinition(
                    icon: "bolt.fill",
                    title: "Atmospheric QRN & Network Impairments",
                    text: "Injects Poisson-distributed impulsive static bursts, along with configurable UDP packet drop (0-25%) and jitter buffer delay (0-100 ms) to stress-test client resilience.",
                    color: .yellow
                )
            }

            helpSection("Signal Studio & DSP Benchmarking") {
                HelpDefinition(
                    icon: "waveform",
                    title: "FT8 / FT4 Continuous-Phase Modulation",
                    text: "Synthesizes real 79-tone FT8 and 4-GFSK FT4 transmissions using FT8Codec, perfectly synchronized to UTC 15-second and 7.5-second time boundaries.",
                    color: .green
                )
                HelpDefinition(
                    icon: "person.3.sequence.fill",
                    title: "5-Station Multi-Caller Pileup",
                    text: "Generates simultaneous calling stations on distinct audio frequencies (e.g. 1200 Hz, 1450 Hz, 1850 Hz) with independent SNR levels to test receiver selectivity and decoder multi-pass performance.",
                    color: .pink
                )
                HelpDefinition(
                    icon: "chart.bar.doc.horizontal.fill",
                    title: "Automated SNR Sensitivity Sweeps",
                    text: "Runs stepped sensitivity sweeps from +6 dB down to -24 dB in 3 dB increments, evaluating decode success rates and producing structured markdown and JSON benchmark reports.",
                    color: .purple
                )
            }

            helpSection("Hardware OLED Panel & Ergonomics") {
                HelpDefinition(
                    icon: "display",
                    title: "Front Panel OLED with Glowing VFO",
                    text: "Features high-contrast digital frequency readout, band and mode badges, dynamic analog S-meter and SWR gauges, frequency stepping buttons, and latching PTT.",
                    color: .mint
                )
                HelpDefinition(
                    icon: "link",
                    title: "1-Click 'Connect YAAM LAN' Loopback",
                    text: "Clicking 'Connect YAAM LAN' automatically configures and connects YAAM's internal Icom LAN client to the local emulator, providing an instant end-to-end radio and digital modem testbed.",
                    color: .blue
                )
            }

            helpCallout(
                icon: "keyboard",
                title: "Quick Access & Detached Window Mode",
                text: "Launch the emulator at any time using Option-Command-E, select it in Operator Desk (Tab 24), or click the detach button to pop the emulator into its own independent floating macOS window scene.",
                color: .blue
            )
        }
    }

    private var multiRigFT8View: some View {
        Group {
            helpHeader(
                title: "Multi-Rig FT8 Cluster (SO2R / SO3R)",
                subtitle: "Operate up to 4 independent transceivers concurrently on separate amateur bands with dedicated DSP decoders, isolated CoreAudio routing, cross-rig TX interlock protection, and unified SQLite log deduplication.",
                icon: "square.split.3x1.fill",
                color: .indigo
            )

            HelpMultiRigMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "plus.square.dashed", title: "1. Configure Transceiver Slots", detail: "Assign radios (Icom LAN UDP, Lab599 TX-500, Xiegu X6100, Hamlib rigctld, or NTE Emulator) and dial frequencies (e.g. 20m, 40m, 10m)."),
                HelpFlowStep(icon: "speaker.wave.2.fill", title: "2. Isolate Audio Hardware", detail: "Bind distinct CoreAudio input/output channels per slot (e.g. USB Audio CODEC, network LPCM, virtual cable) to guarantee zero audio bleed."),
                HelpFlowStep(icon: "lock.shield.fill", title: "3. Choose TX Interlock Policy", detail: "Select Strict Lockout (mutex), Alternating Slots (even/odd 15s SO2R), or Concurrent TX to prevent front-end desensitization and RF burnout."),
                HelpFlowStep(icon: "waveform.path.ecg", title: "4. Start All Decoders", detail: "Click 'Start All' to initiate simultaneous background DSP decoding and live 3 kHz waterfall spectrums across all slots."),
                HelpFlowStep(icon: "bolt.horizontal.circle.fill", title: "5. Cross-Band DX Dispatch", detail: "Inspect the Cross-Band Opportunity Radar for unworked DXCCs or grids and click 'Answer on Rig X' to tune, arm, and reply instantly.")
            ])

            helpSection("Architecture & Signal Processing Isolation") {
                HelpDefinition(
                    icon: "cpu",
                    title: "Autonomous DSP Engines (FT8EngineService)",
                    text: "Each slot executes an independent DSP decoder on dedicated Grand Central Dispatch queues. A heavy pileup or decode cycle on 20m will never cause dropped samples or timing lag on 40m or 10m.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "cable.connector.horizontal",
                    title: "Strict Audio Device Binding (Zero Bleed)",
                    text: "Every engine binds directly to a unique CoreAudio hardware UID. Transmit audio synthesized for Slot 1 never leaks into the receive stream of Slot 2 or Slot 3.",
                    color: .purple
                )
                HelpDefinition(
                    icon: "radio",
                    title: "Universal CAT Driver Support",
                    text: "Mix and match transceivers seamlessly: Icom direct LAN UDP (IC-705, IC-7300MK2, IC-7610), USB-C serial (Lab599 TX-500, Xiegu X6100, Icom USB), Hamlib rigctld (TCP 4532), and YAAM's internal NTE Emulator.",
                    color: .teal
                )
            }

            helpSection("Cross-Rig TX Interlock Coordinator") {
                HelpDefinition(
                    icon: "lock.shield.fill",
                    title: "Strict Lockout (Mutual Exclusion)",
                    text: "A hardware-level mutex guarantees that only one transceiver may key PTT at any instant. If Rig 1 is transmitting, Rig 2 is held in standby until Rig 1 releases PTT.",
                    color: .red
                )
                HelpDefinition(
                    icon: "clock.arrow.2.circlepath",
                    title: "Alternating Slots (SO2R Gold Standard)",
                    text: "Synchronized with the UTC 15-second FT8 epoch: Rig 1 transmits on even slots (:00, :30) while Rig 2 listens; Rig 2 transmits on odd slots (:15, :45) while Rig 1 listens. Slot 3 acts as a continuous listener or runner.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Concurrent TX Mode",
                    text: "Permits simultaneous transmission across all armed radios. Recommended only for multi-operator stations with physically isolated antenna towers and high-rejection bandpass filters (BPFs).",
                    color: .green
                )
                HelpDefinition(
                    icon: "exclamationmark.octagon.fill",
                    title: "Emergency Master Disarm (Disarm All TX)",
                    text: "Instantly releases PTT and disarms transmit state across all transceivers simultaneously with one click.",
                    color: .red
                )
            }

            helpSection("Ergonomic Console Layouts & Waterfalls") {
                HelpDefinition(
                    icon: "rectangle.split.3x1",
                    title: "3-Column Parallel",
                    text: "Displays 3 transceivers side-by-side with full-height waterfalls, live S-meters, power/SWR telemetry, and decode lists. Optimized for 16:9 and ultrawide displays.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "rectangle.split.1x2",
                    title: "Hero + 2 Sub-Rigs",
                    text: "High-resolution main band waterfall on top; two secondary bands side-by-side below for fast secondary-station tracking.",
                    color: .indigo
                )
                HelpDefinition(
                    icon: "rectangle.split.2x1",
                    title: "Dual Split & Quad Matrix",
                    text: "Provides 50/50 dual-rig layout for classic SO2R, or a 2x2 grid for monitoring 4 bands simultaneously.",
                    color: .cyan
                )
            }

            helpSection("Cross-Band DX Opportunity Radar & Unified Logging") {
                HelpDefinition(
                    icon: "radar",
                    title: "Real-Time Opportunity Aggregator",
                    text: "Collects incoming CQ frames from all slots in real time, cross-referencing your central logbook to identify and badge NEW DXCC, NEW BAND, and NEW GRID entities.",
                    color: .pink
                )
                HelpDefinition(
                    icon: "arrowshape.turn.up.right.fill",
                    title: "1-Click Cross-Band Dispatch",
                    text: "Click 'Answer on Rig X' to tune the corresponding radio to the target audio frequency, generate the response macro, and queue transmission for the next UTC slot.",
                    color: .green
                )
                HelpDefinition(
                    icon: "doc.text.fill",
                    title: "Unified SQLite Logbook with RADIO Tags",
                    text: "Every completed QSO is automatically committed to YAAM's central database with ADIF tags for RADIO (e.g. 'Rig 1 (20m FT8)') and exact frequency. Worked status immediately propagates across all active slots.",
                    color: .mint
                )
            }

            helpCallout(
                icon: "macwindow.on.rectangle",
                title: "Multi-Monitor Floating Window (Cmd + Option + 8)",
                text: "Press Command-Option-8 or select Window > Multi-Rig FT8 Cluster (SO3R)... to launch the cluster console in an independent floating window scene, keeping your primary monitor open for logbook analysis, maps, and awards.",
                color: .indigo
            )
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

            HelpScreenshotCard(
                imageName: "help_contest",
                title: "Contest Operations & Scoring Engine",
                caption: "CQ WW, WPX, ARRL DX presets, Cabrillo 3.0 robot headers, and live serial numbering."
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
            helpCallout(icon: "trophy.fill", title: "FT8 / FT4 Digital Contests", text: "Looking for real-time multiplier matrices, rate meters, WSJT-X 2-way live stream, and instant Cabrillo 3.0 export? Check out the dedicated Digital Contest Suite topic.", color: .yellow)
            helpCallout(icon: "doc.text.magnifyingglass", title: "Verify before submission", text: "Cabrillo layouts and scoring rules vary by sponsor. YAAM emits a standards-based Cabrillo 3.0 log with CLAIMED-SCORE set to zero; calculate the official score and validate categories and exchange columns with the contest sponsor's checker.", color: .blue)
        }
    }

    private var digitalContestView: some View {
        Group {
            helpHeader(
                title: "Digital Contest Suite (FT8 & FT4)",
                subtitle: "The gold-standard macOS digital contest environment: real-time multiplier engine, rate meters, WSJT-X 2-way live stream, high-density band matrix, and official Cabrillo 3.0 export.",
                icon: "trophy.fill",
                color: .yellow
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "flag.checkered", title: "Setup", detail: "Configure CQ WW Digi or ARRL Digi rules with your station call and Maidenhead grid."),
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Stream", detail: "Connect WSJT-X / JTDX 2-way UDP stream or run YAAM's native FT8/FT4 engine."),
                HelpFlowStep(icon: "tray.full.fill", title: "Auto-Runner", detail: "Smart multi-caller queue captures pile-ups and engages callers with zero idle cycles."),
                HelpFlowStep(icon: "bolt.fill", title: "Spot & Hunt", detail: "Live amber highlights spotlight new grid fields & DXCC mults in every decode slot."),
                HelpFlowStep(icon: "tablecells.badge.sparkles", title: "Matrix & Rate", detail: "Track QSOs, dupes, points, rate/hr, and projected score in the band matrix."),
                HelpFlowStep(icon: "square.and.arrow.up.fill", title: "Cabrillo 3.0", detail: "Pre-flight validation ensures robot acceptance before 1-click export.")
            ])

            // Visual Showcase 1: Live Decode Highlights
            helpSection("Live Decode Highlights & Spot Hunting") {
                Text("Every decode in both the WSJT-X 2-way stream and YAAM native FT8 station is analyzed in real-time against your contest log:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    // Multiplier Decode Mockup
                    HStack(spacing: 8) {
                        Text("14:20:00")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("-06dB")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("1240Hz")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                        Text("FT8")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 3).background(Color.secondary.opacity(0.12)).cornerRadius(3)
                        Text("🇩🇪 Germany")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("DL1ABC")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange)
                        Text("JO31")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).background(Color.orange.opacity(0.15)).foregroundStyle(.orange).cornerRadius(3)
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.system(size: 7))
                            Text("MULT: JO").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        }
                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange).foregroundStyle(Color.black).cornerRadius(3)
                        Text("CQ DL1ABC JO31")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Reply")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.green).foregroundStyle(.white).cornerRadius(4)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.5), lineWidth: 1))

                    // Normal QSO Decode Mockup
                    HStack(spacing: 8) {
                        Text("14:20:00")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("-11dB")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                        Text("1680Hz")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                        Text("FT8")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 3).background(Color.secondary.opacity(0.12)).cornerRadius(3)
                        Text("🇫🇷 France")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("F6XYZ")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text("JN18")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).background(Color.orange.opacity(0.15)).foregroundStyle(.orange).cornerRadius(3)
                        Text("+2 PTS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.green.opacity(0.15)).foregroundStyle(.green).cornerRadius(3)
                        Text("CQ F6XYZ JN18")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Reply")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor).foregroundStyle(.white).cornerRadius(4)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

                    // Dupe Decode Mockup
                    HStack(spacing: 8) {
                        Text("14:20:00")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("-04dB")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("0850Hz")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                        Text("FT8")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 3).background(Color.secondary.opacity(0.12)).cornerRadius(3)
                        Text("🇩🇪 Germany")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("DL1ABC")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("JO31")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).background(Color.secondary.opacity(0.1)).foregroundStyle(.secondary).cornerRadius(3)
                        Text("DUPE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.secondary.opacity(0.2)).foregroundStyle(.secondary).cornerRadius(3)
                        Text("DL1ABC EP2LMA R-08")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Worked")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.02)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }

                HelpDefinition(icon: "bolt.fill", title: "New Multiplier (⚡️ MULT)", text: "Golden amber badge and highlighted callsign indicate that answering this station will award a new Maidenhead grid field (CQ WW Digi) or DXCC entity/State on the current band.", color: .orange)
                HelpDefinition(icon: "plus.circle.fill", title: "New Valid QSO (+Pts)", text: "Emerald green badge indicates a fresh valid contact that adds distance or contest points without being a duplicate.", color: .green)
                HelpDefinition(icon: "slash.circle", title: "Duplicate Call (DUPE)", text: "Dimmed slate badge warns you if this station was already worked on the current band in this contest, preventing lost cycle time.", color: .secondary)
            }

            // Visual Showcase 1.5: Smart Auto-Runner & Multi-Caller Pile-up Queue
            helpSection("Smart Auto-Runner & Multi-Caller Queue (Zero-Idle)") {
                Text("When running a frequency during high-density pile-ups, competing callers are intelligently prioritized and queued for instant continuous execution:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    // Queue Header Bar Mockup
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full.fill")
                                .foregroundStyle(Color.yellow)
                                .font(.system(size: 11))
                            Text("Auto-Runner Queue")
                                .font(.system(size: 11, weight: .bold))
                            Text("(3)")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                        }

                        Divider()
                            .frame(height: 14)

                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.green)
                            Text("Zero-Idle Auto-Engage: ON")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.cyan)
                            Text("Auto-Queue: ON")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.cyan)
                        }

                        Spacer()

                        Text("Engage #1 (JA1ABC)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.black)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(6)

                    // Queued Cards Mockup
                    HStack(spacing: 8) {
                        // Card 1
                        HStack(spacing: 6) {
                            Text("#1")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text("JA1ABC").font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("MULT: PM")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 2))
                                }
                                Text("🇯🇵 PM95 · -08 dB · 1800 Hz").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        }
                        .padding(6)
                        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                        // Card 2
                        HStack(spacing: 6) {
                            Text("#2")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text("DL1ABC").font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("MULT: JO")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 2))
                                }
                                Text("🇩🇪 JO31 · -10 dB · 1450 Hz").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                        // Card 3
                        HStack(spacing: 6) {
                            Text("#3")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text("EP2XYZ").font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("+1 PTS")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(Color.green, in: RoundedRectangle(cornerRadius: 2))
                                }
                                Text("🇮🇷 KM32 · -05 dB · 1200 Hz").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                HelpDefinition(icon: "bolt.horizontal.circle.fill", title: "Zero-Idle QSO Auto-Engagement", text: "When your active QSO completes (RR73 sent or received), the engine immediately pops the #1 ranked station and transmits their exchange on the very next slot without returning to CQ, saving 15s/7.5s every contact.", color: .green)
                HelpDefinition(icon: "chart.line.uptrend.xyaxis.circle.fill", title: "Intelligent Multi-Factor Priority Scoring", text: "Stations are dynamically ranked: New Multiplier (+1000 pts) > Contact Points (x50) > Great Circle Distance > SNR. Dupes are automatically rejected or placed at the bottom.", color: .yellow)
                HelpDefinition(icon: "tray.and.arrow.down.fill", title: "Live Pile-up Auto-Queueing", text: "When multiple stations answer your CQ at once or call while you work another DX, they are automatically captured into the queue in both the Native FT8 Engine and the WSJT-X / JTDX stream.", color: .cyan)
                HelpDefinition(icon: "arrow.up.circle.fill", title: "Manual Override & VIP Promotion", text: "Click the up-chevron (▲) on any card to promote an important DX station straight to #1, or click the bolt icon to engage immediately.", color: .orange)
            }

            // Visual Showcase 2: Rate Meters HUD
            helpSection("Real-Time Rate Meters & Velocity HUD") {
                Text("Monitor your operating velocity and forecast final score with sub-second recalculation:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("10-MIN RATE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("64").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.green)
                            Text("/hr").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.green.opacity(0.08)).cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("60-MIN RATE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("52").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.cyan)
                            Text("/hr").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.cyan.opacity(0.08)).cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PEAK RATE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("84").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.purple)
                            Text("/hr").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.purple.opacity(0.08)).cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AVG PTS/QSO").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        Text("2.35").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.primary)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08)).cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PROJECTED FINAL").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        Text("48,200").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.yellow)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.12)).cornerRadius(6)
                }

                HelpDefinition(icon: "speedometer", title: "10-Minute Rolling Rate", text: "Instantaneous QSOs/hour velocity computed from recent contacts to evaluate run frequency viability.", color: .green)
                HelpDefinition(icon: "sparkles", title: "Projected Final Score", text: "Mathematically combines rolling 60-minute rate, average points per contact, and accumulated multipliers to forecast final contest output.", color: .yellow)
            }

            // Section: Band Matrix & Multiplier Explorer
            helpSection("Band-by-Band Matrix & Multiplier Explorer") {
                HelpInstruction(number: 1, title: "Band Matrix Table", text: "Access via the 'Contest Matrix' button in FT8 Station or WSJT-X console. Shows 160m to 6m breakdowns with valid QSOs, dupes, points, grid mults, DXCC mults, and band score.")
                HelpInstruction(number: 2, title: "Activity Share Progress", text: "Visual progress capsule highlights which band has the highest contact yield and where band changes are needed.")
                HelpInstruction(number: 3, title: "Multiplier Explorer", text: "Browse worked 2-letter Maidenhead fields (JO, JN, LL, FN...) and DXCC countries with flags per band or across all bands.")
                HelpInstruction(number: 4, title: "Live Contest QSOs", text: "Review raw contest log entries with sent/received exchanges, exact UTC timestamp, and multiplier flags.")
            }

            // Section: WSJT-X / JTDX Two-Way Integration
            helpSection("Two-Way WSJT-X & JTDX Integration") {
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "1-Click Reply (Type 4 Packet)", text: "Clicking Reply or double-clicking any decode row in YAAM instantly directs WSJT-X to set DX Call, Grid, and key the transmitter.", color: .green)
                HelpDefinition(icon: "stop.circle.fill", title: "1-Click Halt TX (Type 7 Packet)", text: "Instantly aborts transmission in WSJT-X directly from YAAM's toolbar for emergency safety or QRM avoidance.", color: .red)
                HelpDefinition(icon: "mappin.and.ellipse", title: "Sync Grid (Type 9 Packet)", text: "Pushes your station Maidenhead grid to WSJT-X with one click to ensure consistent exchange logging.", color: .blue)
                HelpDefinition(icon: "line.3.horizontal.decrease.circle", title: "⚡️ Mults Filter Chip", text: "Toggle the '⚡️ Mults' filter chip to show only high-value multipliers in the live stream for rapid rate boosting.", color: .orange)
            }

            // Section: Native FT8 Engine & Hardware Telemetry
            helpSection("Native FT8 Engine & Hardware Telemetry") {
                HelpDefinition(icon: "clock.badge.checkmark", title: "Exact UTC Slot Clock", text: "Built-in DigitalSlotClock strictly enforces 15.0s (FT8) and 7.5s (FT4) boundaries with odd/even parity management.", color: .blue)
                HelpDefinition(icon: "gauge.with.needle", title: "Live Radio SWR, Power & ALC", text: "Direct CI-V polling reads forward RF Power (0-100W), antenna SWR (emerald <= 1.5, amber <= 2.0, red > 2.0), ALC level, and S-meter in real time.", color: .orange)
                HelpDefinition(icon: "waveform", title: "High-Contrast SDR-Control Waterfall", text: "240-row depth (30 seconds history) with exponential moving average noise-floor tracking to clearly resolve individual FT8 tone packets.", color: .purple)
                HelpDefinition(icon: "shield.lefthalf.filled", title: "Dynamic Watchdog", text: "Rigorous 15.0s (FT8) and 7.5s (FT4) hardware watchdog automatically releases transmitter PTT if any audio or socket stall occurs.", color: .red)
            }

            // Section: Official Cabrillo 3.0 Export
            helpSection("Official Cabrillo 3.0 Export & Pre-Flight Validation") {
                HelpInstruction(number: 1, title: "Automated Pre-Flight Robot Validation", text: "Before generating files, YAAM verifies mandatory fields (Callsign, Grid Locator, Categories) to prevent contest robot rejection emails.")
                HelpInstruction(number: 2, title: "CQ WW Digi & ARRL Digi Format", text: "Generates strict column-aligned Cabrillo 3.0 headers and QSO lines with CRLF line terminators and CLAIMED-SCORE computation.")
                HelpInstruction(number: 3, title: "1-Click Export & Share", text: "Save the verified .log file to disk or copy directly to the contest web upload portal.")
            }

            helpCallout(
                icon: "trophy.fill",
                title: "Maximum Competitive Efficiency",
                text: "Combine the WSJT-X 2-way stream with the '⚡️ Mults' filter to quickly capture rare grid fields on open bands, then switch to Contest Matrix to monitor your 60-minute rate and points per contact.",
                color: .yellow
            )
        }
    }

    private var digitalRosterView: some View {
        Group {
            helpHeader(
                title: "Digital Call Roster & Voice Alerts",
                subtitle: "Real-time decode triage against your Master Log, instant 1-click calling via UDP, geodesic beam headings, and hands-free Apple speech alerts.",
                icon: "waveform.and.person.filled",
                color: .purple
            )

            HelpScreenshotCard(
                imageName: "help_call_roster",
                title: "Live Digital Call Roster & Real-Time Triage",
                caption: "Instant classification against Master Log, 1-click calling, geodesic bearing & distance, and hands-free AVSpeechSynthesizer voice alerts."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "network", title: "UDP Ingestion", detail: "Listens on UDP 2237 for live WSJT-X and JTDX decodes every 15-second FT8/FT4 cycle."),
                HelpFlowStep(icon: "bolt.badge.clock.fill", title: "Master Log Triage", detail: "Indexes your SQLite log in memory to determine in O(1) time if a caller is an All-Time New One or New Band."),
                HelpFlowStep(icon: "location.north.circle.fill", title: "Geodesic Heading", detail: "Computes exact great-circle short-path beam heading degrees and distance in km from your Maidenhead grid."),
                HelpFlowStep(icon: "bolt.fill", title: "1-Click Calling", detail: "Click 'Call ⚡️' or double-click any row to instruct WSJT-X to transmit immediately without leaving YAAM."),
                HelpFlowStep(icon: "speaker.wave.3.fill", title: "Voice Alerts", detail: "Apple AVSpeechSynthesizer announces rare DXCCs and direct callers hands-free with cycle debouncing.")
            ])

            helpSection("Real-Time Priority Triage Hierarchy") {
                Text("Each decode is matched against your master logbook and tagged with high-visibility badges:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HelpDefinition(
                    icon: "star.fill",
                    title: "⭐️ NEW DXCC (All-Time New One)",
                    text: "Indicates a country entity that you have NEVER worked on any band or mode. Highest operational priority for your DXCC score.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "target",
                    title: "🎯 NEW BAND (Band DXCC)",
                    text: "Indicates a country you have worked on other bands, but is unworked on the current operating band. Essential for DXCC Challenge and multi-band awards.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "square.grid.3x3.fill",
                    title: "💠 NEW GRID (VUCC Gridsquare)",
                    text: "Indicates a Maidenhead locator (e.g. LL29, JO31) that you have not yet logged, critical for VHF/UHF and HF VUCC awards.",
                    color: .cyan
                )
                HelpDefinition(
                    icon: "bell.badge.fill",
                    title: "🔔 CALLING ME (Direct Contact)",
                    text: "Highlights any incoming message directed specifically to your station callsign (e.g., answering your CQ or replying to your report).",
                    color: .green
                )
                HelpDefinition(
                    icon: "checkmark.seal.fill",
                    title: "✓ WORKED / CONFIRMED",
                    text: "Station or country already in your log; confirmations verified via LoTW or QRZ are highlighted.",
                    color: .secondary
                )
            }

            helpSection("Zero-Window-Switching (1-Click & Double-Click Calling)") {
                HelpInstruction(
                    number: 1,
                    title: "1-Click Instant Reply",
                    text: "Click the 'Call ⚡️' button in any row to transmit a WSJT-X UDP Type 4 (Reply) message. WSJT-X immediately sets the DX call, frequency offset, and enables TX."
                )
                HelpInstruction(
                    number: 2,
                    title: "Double-Click Shortcut",
                    text: "Double-click anywhere on a call roster row to initiate transmission on that station with zero mouse precision required."
                )
                HelpInstruction(
                    number: 3,
                    title: "Antenna Rotator Direction",
                    text: "Read the computed short-path beam heading (e.g. 048° NE) and distance to align your directional beam before transmitting."
                )
            }

            helpSection("Smart Audio Speech Alerts (Apple AVSpeechSynthesizer)") {
                HelpInstruction(
                    number: 1,
                    title: "Hands-Free Operation",
                    text: "Click 'Voice Alerts 🔈' in the Call Roster toolbar to customize voice callouts. YAAM speaks incoming events like 'New DXCC! Japan on 14 megahertz, signal minus 8'."
                )
                HelpInstruction(
                    number: 2,
                    title: "Cycle Debouncing",
                    text: "Repeat CQs from the same station within 60 seconds are automatically debounced to prevent voice fatigue during busy FT8 cycles."
                )
                HelpInstruction(
                    number: 3,
                    title: "Audio Chimes & Speed",
                    text: "Enable subtle audio chimes (NSSound) before speech, adjust the speech rate slider, and choose any installed macOS voice (e.g. Samantha, Daniel, Siri)."
                )
            }

            helpCallout(
                icon: "keyboard",
                title: "Instant Global Access: ⌘⇧R",
                text: "Open the Digital Call Roster at any time from anywhere in YAAM by pressing Command + Shift + R or opening Operator Desk tab 20.",
                color: .purple
            )
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
            helpHeader(
                title: "6m Magic Band Watch & Propagation Suite",
                subtitle: "Real-time scientific VHF telemetry combining NOAA space weather, GIRO ionosondes, mid-point geometry, dynamic weighting, and automated opening alarms.",
                icon: "bolt.badge.clock.fill",
                color: .orange
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "antenna.radiowaves.left.and.right", title: "Station Location", detail: "YAAM automatically uses your active station grid/coordinates to calculate Great Circle beam headings and midpoint distances."),
                HelpFlowStep(icon: "arrow.triangle.swap", title: "Mid-Point Sounders", detail: "Ionospheric reflection occurs 500–1100 km away at the path midpoint, not overhead. YAAM tracks Nicosia, Athens, and Balkan sounders."),
                HelpFlowStep(icon: "chart.line.uptrend.xyaxis", title: "Rate of Change", detail: "Look for positive ΔFoEs/Δt rates (▲ Rapid Rise ≥1.5 MHz/h) indicating rapid formation of dense Sporadic-E clouds."),
                HelpFlowStep(icon: "bell.badge.fill", title: "Alarms & Webhooks", detail: "Receive audio chimes, spoken voice announcements, and Discord/Telegram push notifications when the 50 MHz threshold is breached.")
            ])

            helpSection("Propagation Physics & Corridors") {
                HelpDefinition(
                    icon: "cloud.bolt.rain.fill",
                    title: "Sporadic-E (Es) Mechanism",
                    text: "Dense clouds of metallic ions (Fe+, Mg+ from meteoric ablation) form in the E-region (90–120 km altitude). When the critical vertical frequency (FoEs) reaches 10–12 MHz, oblique reflection (MUF ≈ 5.0 × FoEs) opens 50 MHz.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "arrow.triangle.merge",
                    title: "Single-Hop (Es1) vs Double-Hop (Es2)",
                    text: "A single Sporadic-E hop spans up to 2,200 km with an ionospheric midpoint at 500–1,100 km. Paths beyond 2,200 km (e.g. Tehran to Western Europe at 2,600 km) require two consecutive hops (Es2) with an intermediate ground bounce.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "location.north.circle.fill",
                    title: "Optimal Beam Heading",
                    text: "YAAM computes the true Great Circle azimuth (0°–360°) and 16-point compass heading (e.g. 295° WNW) pointing directly toward the highest ionization hotspot.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "sun.max.fill",
                    title: "F2 Solar Max & Transequatorial (TEP)",
                    text: "During Solar Cycle peaks when SFI ≥ 160–200, the F2 layer supports worldwide propagation. In late afternoons/evenings, TEP enables 5,000–8,000 km north-south paths across the magnetic equator.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "sparkles",
                    title: "Auroral Scatter",
                    text: "When Planetary Kp ≥ 5 during geomagnetic storms, intense auroral backscatter enables high-latitude VHF communication with distinctive raspy audio.",
                    color: .purple
                )
            }

            helpSection("Scientific Weighted Composite Model") {
                HelpDefinition(
                    icon: "chart.bar.xaxis",
                    title: "Dynamic Weighting Formula",
                    text: "Composite Score = (Midpoint MUF × W1) + (2000km Telemetry × W2) + (Diurnal/Seasonal × 15%) + (Space Weather × 10%).",
                    color: .green
                )
                HelpDefinition(
                    icon: "scope",
                    title: "Sparse-Receiver Dynamic Compensation",
                    text: "In regions with lower active amateur beacon density (such as the Middle East/EP), when regional spots are <5, YAAM dynamically shifts 15% weight from Telemetry to Mid-Point MUF (boosting it to 65%) so valid ionospheric conditions are not penalized.",
                    color: .green
                )
            }

            helpCallout(
                icon: "bolt.fill",
                title: "Operating Strategy on 50 MHz",
                text: "Sporadic-E openings can develop within 10–15 minutes and fade just as quickly. When YAAM signals High Alert (Score ≥45%) or Band Open (Score ≥70%), rotate your antenna to the recommended beam heading and immediately monitor 50.313 MHz (FT8), 50.090–50.110 MHz (CW beacons), and the DX Cluster.",
                color: .orange
            )
        }
    }

    private var tacticalPilotView: some View {
        Group {
            helpHeader(
                title: "Tactical Pilot & HF Propagation",
                subtitle: "Point-to-point HF propagation prediction engine covering all 11 amateur bands (160m to 6m), SNR forecasting, MUF curves, 24-hour UTC forecast timeline, and dynamic peak hour advice.",
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                color: .teal
            )

            HelpScreenshotCard(
                imageName: "help_tactical_pilot",
                title: "11-Band HF Propagation Matrix & MUF Radar",
                caption: "Full amateur coverage (160m Topband to 6m Magic Band), 24h timeline forecast, and dynamic peak hour calculation."
            )

            HelpTacticalPilotMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "target", title: "1. Target Entity", detail: "Select a callsign, DXCC country, or Maidenhead grid locator."),
                HelpFlowStep(icon: "globe.americas.fill", title: "2. Path Geometry", detail: "Calculates great circle short-path and long-path azimuth, distance, and ionospheric bounce midpoints."),
                HelpFlowStep(icon: "chart.line.uptrend.xyaxis", title: "3. Solar Raytrace", detail: "Uses real-time SFI, SSN, and geomagnetic Kp to model D, E, F1, and F2 layer densities."),
                HelpFlowStep(icon: "checkmark.seal.fill", title: "4. 11-Band Spectrum Advisor", detail: "Scores all 11 amateur bands (160m to 6m) by SNR, circuit reliability percentage, and operating window."),
                HelpFlowStep(icon: "clock.arrow.circlepath", title: "5. 24H Forecast Timeline", detail: "Renders an interactive 24-hour UTC sparkline displaying exact diurnal opening onsets and dynamic peak hour.")
            ])

            helpSection("Propagation Telemetry & Calculations") {
                HelpDefinition(icon: "chart.xyaxis.line", title: "Maximum Usable Frequency (MUF)", text: "Determines the highest frequency refracted back to Earth along the path. Frequencies just below MUF (85–90% FOT) experience the lowest absorption and strongest signal levels.", color: .teal)
                HelpDefinition(icon: "waveform.badge.plus", title: "Signal-to-Noise Ratio (SNR)", text: "Estimates received signal strength in dB relative to ambient noise floor, accounting for transceiver transmitter power and antenna gains.", color: .green)
                HelpDefinition(icon: "clock.arrow.circlepath", title: "Dynamic Peak Hour (UTC)", text: "Analyzes all 24 hours of the diurnal cycle and extracts the statistically optimal hour for highest total circuit reliability.", color: .yellow)
            }

            helpSection("Full 11-Band Amateur Coverage") {
                HelpDefinition(
                    icon: "moon.stars.fill",
                    title: "160m Topband (1.8 MHz)",
                    text: "Physical modeling of severe D-layer solar absorption during daytime (signal extinction) transitioning to powerful nocturnal F2 skywave propagation at local midnight.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "sparkles",
                    title: "6m Magic Band (50.1 MHz)",
                    text: "Models summertime sporadic-E (Es) ionization clouds and high solar flux (SFI ≥ 160) F2 cycle peaks, letting VHF enthusiasts monitor transatlantic and transcontinental openings.",
                    color: .purple
                )
                HelpDefinition(
                    icon: "shoeprints.fill",
                    title: "Rover Mode Geodesic Synchronization",
                    text: "When Tactical Rover Mode is active, all great-circle distances, beam headings, hop geometries, and MUF evaluations dynamically recalculate from the rover's temporary Maidenhead grid.",
                    color: .cyan
                )
            }
        }
    }

    private var hamClockShackView: some View {
        Group {
            helpHeader(
                title: "HamClock & Remote Server",
                subtitle: "Live shack dashboard with dual UTC/Local dials, real-time solar indices, SDO imagery, DRAP ionospheric absorption, and local network web broadcasting to iPads and tablets.",
                icon: "deskclock.fill",
                color: .indigo
            )

            HelpHamClockMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "clock", title: "UTC Master Time", detail: "Precision clocks with UTC and local timezone dials synchronized to Apple network time."),
                HelpFlowStep(icon: "sun.max.fill", title: "Solar Indices", detail: "Direct NOAA/SWPC feeds for Solar Flux Index (SFI), Sunspot Number (SSN), A-Index, and Kp index."),
                HelpFlowStep(icon: "photo.fill", title: "SDO Imagery & DRAP", detail: "NASA Solar Dynamics Observatory extreme ultraviolet images (AIA 304Å) and D-Region absorption maps."),
                HelpFlowStep(icon: "ipad.and.iphone", title: "Remote Web Server", detail: "Built-in zero-config HTTP server broadcasts live metrics to iPads, phones, or secondary screens on your LAN.")
            ])

            helpSection("Remote Web Server Setup") {
                HelpInstruction(number: 1, title: "Enable Server", text: "In Tools > HamClock or Operator Desk, toggle 'Enable Remote Web Server'. YAAM starts a lightweight HTTP daemon on port 8080.")
                HelpInstruction(number: 2, title: "Connect Second Screen", text: "Open Safari or Chrome on your iPad, tablet, or wall-mounted Raspberry Pi screen, and navigate to the displayed local IP address (e.g., http://192.168.1.55:8080).")
                HelpInstruction(number: 3, title: "Real-Time Telemetry", text: "The remote dashboard updates automatically via SSE (Server-Sent Events) without page reloads, giving you a full shack console.")
            }
        }
    }

    private var weatherRadarView: some View {
        Group {
            helpHeader(
                title: "Station Weather & Lightning Safety",
                subtitle: "Real-time NEXRAD weather radar overlay, severe wind gust alerts, and thunderstorm cell tracking to protect towers, beams, and shack transceivers.",
                icon: "cloud.bolt.rain.fill",
                color: .blue
            )

            HelpWeatherRadarMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "location.fill", title: "Station Location", detail: "Automatically centers weather radar around your active station profile's coordinates."),
                HelpFlowStep(icon: "cloud.rain.fill", title: "Precipitation & Wind", detail: "Live doppler precipitation reflectivity and real-time wind gust monitoring."),
                HelpFlowStep(icon: "bolt.fill", title: "Lightning Proximity", detail: "Monitors atmospheric electrical discharges within a 100 km radius of your station antennas."),
                HelpFlowStep(icon: "exclamationmark.shield.fill", title: "Protection Alerts", detail: "Audible and visual alerts trigger when lightning is detected within 30 km or winds exceed 65 km/h.")
            ])

            helpSection("Equipment Safety Protocols") {
                HelpDefinition(icon: "shield.lefthalf.filled", title: "Safe Zone (> 30 km)", text: "Normal operation. Rotators and amplifiers safe to use.", color: .green)
                HelpDefinition(icon: "exclamationmark.triangle.fill", title: "Caution Zone (15–30 km)", text: "Thunderstorm cell approaching. Prepare to park rotators, lower crank-up towers, and power down linear amplifiers.", color: .orange)
                HelpDefinition(icon: "xmark.octagon.fill", title: "Danger Zone (< 15 km)", text: "IMMEDIATE ACTION: Disconnect coaxial feedlines, ground antenna switches, and disconnect station power to prevent lightning-induced EMP damage.", color: .red)
            }
        }
    }

    private var satellitesView: some View {
        Group {
            helpHeader(
                title: "Satellite & APRS Tracking",
                subtitle: "Real-time pass predictions for amateur radio satellites (AO-91, ISS, SO-50), Doppler frequency shift compensation, and high-altitude APRS balloon telemetry.",
                icon: "antenna.radiowaves.left.and.right.circle.fill",
                color: .cyan
            )

            HelpSatelliteMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Orbital Elements", detail: "Fetches and caches fresh Two-Line Element sets (TLEs) from Celestrak and AMSAT."),
                HelpFlowStep(icon: "clock.badge.checkmark", title: "Pass Countdown", detail: "Accurately predicts Acquisition of Signal (AOS), Loss of Signal (LOS), duration, and maximum elevation."),
                HelpFlowStep(icon: "waveform.path", title: "Doppler Correction", detail: "Calculates real-time uplink and downlink Doppler frequency shifts as the satellite approaches and recedes."),
                HelpFlowStep(icon: "balloon.fill", title: "APRS Balloons", detail: "Tracks high-altitude amateur radio weather balloons with altitude, ascent rate, and flight path telemetry.")
            ])

            helpSection("Operating LEO FM Satellites") {
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "Cross-Band Repeater", text: "Most amateur satellites use VHF Uplink (e.g. 145.980 MHz) and UHF Downlink (e.g. 435.180 MHz) with a sub-audible CTCSS tone (e.g. 67.0 Hz).", color: .blue)
                HelpDefinition(icon: "dial.high", title: "UHF Doppler Tuning", text: "Because Doppler shift is four times greater on 70cm than 2m, tune your UHF downlink in 5 kHz steps during the pass (+10 kHz at AOS, nominal at TCA, -10 kHz at LOS).", color: .orange)
            }
        }
    }

    private var clubMembershipView: some View {
        Group {
            helpHeader(
                title: "International Club Memberships",
                subtitle: "Automatically detect and cross-reference international CW and digital club member numbers (SKCC, CWops, FISTS, LICW, 30MDG, EPC) during QSO logging.",
                icon: "person.3.sequence.fill",
                color: .purple
            )

            HelpClubMembershipMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "1. Update Rosters", detail: "Click 'Update Rosters' to fetch the latest membership rosters from club repositories into local SQLite."),
                HelpFlowStep(icon: "character.cursor.ibeam", title: "2. Automatic Detection", detail: "As you enter a callsign in Quick Log, Contest, or Digital Roster, YAAM matches all active club memberships in milliseconds."),
                HelpFlowStep(icon: "tag.fill", title: "3. Review Member Badges", detail: "Discovered club numbers (e.g. CWops #1428, SKCC #9821S) appear alongside operator name and location."),
                HelpFlowStep(icon: "plus.circle.fill", title: "4. 1-Click Exchange Insert", detail: "Click 'Insert Exchange' or press Command-E to copy member numbers directly into the QSO exchange field.")
            ])

            helpSection("Supported International Societies") {
                HelpDefinition(icon: "tuningfork", title: "SKCC (Straight Key Century Club)", text: "Tracks mechanical keying members, endorsements (Centurion, Tribune, Senator), and exact member numbers.", color: .orange)
                HelpDefinition(icon: "headphones", title: "CWops", text: "Global high-speed CW fraternity members with official roster numbers for CWT weekly sprints.", color: .blue)
                HelpDefinition(icon: "cable.connector.horizontal", title: "FISTS CW Club", text: "International Morse Preservation Society member and century awards tracking.", color: .green)
                HelpDefinition(icon: "graduationcap.fill", title: "LICW (Long Island CW Club)", text: "Active training and operating community members worldwide.", color: .teal)
                HelpDefinition(icon: "wave.3.right", title: "30MDG & EPC Digital Groups", text: "30 Meter Digital Group and European Phase Shift Club (PSK/Digital) member registries.", color: .indigo)
            }

            helpSection("Offline Performance & Search Desk") {
                HelpDefinition(
                    icon: "internaldrive.fill",
                    title: "Zero-Latency Local SQLite Cache",
                    text: "Membership rosters (over 38,000 operators) are indexed locally in YAAM's application support directory. Lookups execute in under 2 milliseconds without internet dependency.",
                    color: .purple
                )
                HelpDefinition(
                    icon: "magnifyingglass",
                    title: "Dedicated Callsign Lookup",
                    text: "Use the Callsign Membership Lookup bar in Operator Desk > Clubs (Tag 15) to inspect any operator's complete club affiliations and membership history.",
                    color: .secondary
                )
            }

            helpCallout(
                icon: "medal.fill",
                title: "Club Award Milestones",
                text: "QSOs logged with club numbers automatically populate member tracking in the Awards Center, simplifying applications for SKCC and CWops milestone certificates.",
                color: .purple
            )
        }
    }

    private var dxpeditions: some View {
        Group {
            helpHeader(title: "DXpedition Watch & DX News Desk", subtitle: "Keep announced operations visible, review full weekly bulletins and articles, and distinguish a planned operation from a live spot before changing the radio.", icon: "binoculars.fill", color: .purple)
            HelpFlow(steps: [
                HelpFlowStep(icon: "calendar", title: "Load & Parse", detail: "Open Operator Desk > DX News (or Calendar / 6m). YAAM reads the newest DX-World and 425 DX News weekly bulletins alongside their current feeds/calendars and DXPing in parallel."),
                HelpFlowStep(icon: "tag.fill", title: "Extract Rich Attributes", detail: "Bands, modes (FT8, CW, SSB), QSL managers, IOTA island references, operators, and Maidenhead grids are automatically extracted."),
                HelpFlowStep(icon: "newspaper.fill", title: "News & Bulletins", detail: "Browse categorized DX articles from DX-World and 425 DX News, or inspect full weekly bulletin text archives with issue search and copy."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "Verify live activity", detail: "A green on-air indicator appears only when the same callsign is currently present in the DX Cluster feed."),
                HelpFlowStep(icon: "scope", title: "Check need", detail: "YAAM compares the spot with the active station's worked history and labels it as already worked or a good chance to work."),
                HelpFlowStep(icon: "bell.badge", title: "Notify", detail: "Enable DXpedition spot notifications in Contest Interests to receive a one-time alert when a listed callsign is spotted.")
            ])
            helpSection("Weekly Sources and Provenance") {
                HelpDefinition(icon: "newspaper.fill", title: "425 DX News", text: "YAAM reads the official operation calendar and bulletin archive together, fetches plain-text and PDF weekly issues, and extracts announced callsigns, destinations, operating windows, IOTA references, and QSL routes. The bulletin number and source links remain available for verification.", color: .orange)
                HelpDefinition(icon: "doc.text.image", title: "DX-World Weekly", text: "YAAM uses the official DX News feed to locate the newest weekly bulletin, downloads its linked issue, and extracts announced callsigns, entities, operating windows, modes, and bands. The issue number and original bulletin links remain available for verification.", color: .blue)
                HelpDefinition(icon: "network", title: "DXPing", text: "DXPing remains a complementary schedule source. Agreement between sources improves context, but YAAM preserves every source label instead of presenting a merged claim as certain.", color: .purple)
                HelpDefinition(icon: "externaldrive.badge.checkmark", title: "Saved fallback", text: "The last successful multi-source list, news articles, and bulletin texts are cached locally in UserDefaults. A temporary website failure does not erase the DXpeditions or news already available in YAAM.", color: .green)
                HelpDefinition(icon: "checkmark.shield", title: "Verify free-form notices", text: "Weekly magazines contain prose and schedules can change. YAAM normalizes clear callsigns and date windows, while the linked source remains authoritative for frequencies, modes, QSL routes, and late changes.", color: .green)
            }
            helpSection("Workspaces and Tools") {
                HelpDefinition(icon: "newspaper.fill", title: "DX News & Intelligence Desk", text: "Accessible from Operator Desk > DX News (Desk tab 21) or Tools > DX News & Intelligence (Cmd+Shift+N). Includes Quick Filters for Active Now, Upcoming, ATNO / Needed, FT8 / Digital, 6m Band, and IOTA Islands.")
                HelpDefinition(icon: "doc.plaintext", title: "Weekly Bulletins Reader", text: "Switch between issues of 425 DX News and DX-World Weekly, search full bulletin text, copy passages, or open original source URLs.")
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "One-Click Rig Tune", text: "When a DXpedition is spotted on the cluster, click 'Tune Rig' to instantly QSY your connected transceiver via CAT or TCI SDR.")
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

    private var statistics: some View {
        Group {
            helpHeader(
                title: "Statistics & Action Center",
                subtitle: "Keep the full confirmation picture in a separate, resizable workspace and turn useful gaps into concrete follow-up actions.",
                icon: "chart.bar.doc.horizontal.fill",
                color: .purple
            )

            HelpScreenshotCard(
                imageName: "help_statistics",
                title: "Log Statistics & Confirmation Breakdown",
                caption: "DXCC country matrix, 4-char grid square progress, and confirmation follow-up triage."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "macwindow", title: "Open", detail: "Choose Tools > Log Statistics or press Command-T. Statistics opens as an independent window, so it can stay beside the Log Table and be resized for the amount of detail you need."),
                HelpFlowStep(icon: "chart.bar.xaxis", title: "Analyze", detail: "Review confirmation rate, unique callsigns and modes, provider coverage, countries, bands, grids, and progress over time."),
                HelpFlowStep(icon: "scope", title: "Prioritize", detail: "The Action Center ranks unconfirmed QSOs that could add a new country-band or a new four-character grid."),
                HelpFlowStep(icon: "paperplane", title: "Act", detail: "Open the contact in the Log Table, find an address, compose a confirmation request, preview a QSL card, or open the operator's QRZ page without rebuilding the search manually.")
            ])
            helpSection("Reading the Summary") {
                HelpDefinition(icon: "percent", title: "Confirmation rate", text: "Confirmed local QSOs divided by all QSOs in the active station log. Any recognized LoTW, QRZ, eQSL, or paper/direct confirmation can satisfy a local QSO.", color: .green)
                HelpDefinition(icon: "person.2.fill", title: "Unique activity", text: "Unique callsigns and active modes describe the breadth of the current log rather than the number of rows.")
                HelpDefinition(icon: "checkmark.seal.fill", title: "Provider coverage", text: "LoTW, QRZ, eQSL, and paper/direct cards count local QSOs confirmed by that source. One QSO can be confirmed by several providers, so provider cards intentionally overlap and should not be added together.", color: .blue)
                HelpDefinition(icon: "square.grid.3x3.fill", title: "Four-character grids", text: "Grid statistics normalize longer Maidenhead locators to their first four characters. Confirmation credit still belongs to the underlying QSO.")
            }
            helpSection("Action Center") {
                HelpDefinition(icon: "flag.checkered", title: "New country-band", text: "The QSO is currently unconfirmed and its confirmation would add the first confirmed credit for that DXCC entity on that band.", color: .orange)
                HelpDefinition(icon: "square.grid.3x3", title: "New grid", text: "The QSO is currently unconfirmed and its four-character grid does not yet appear among confirmed grids.", color: .cyan)
                HelpDefinition(icon: "envelope", title: "Editable email", text: "Compose opens YAAM's normal mail editor. When no address is stored, Find Email checks the configured callsign sources first; YAAM never sends a message silently.")
                HelpDefinition(icon: "rectangle.portrait.and.arrow.right", title: "QSL workflow", text: "Preview QSL renders the same card and message flow used elsewhere in YAAM. Review the recipient, text, and attachment before sending.")
            }
            helpSection("Focused Analysis") {
                HelpDefinition(icon: "waveform.path", title: "Band breakdown", text: "Compare QSO volume, confirmations, unconfirmed contacts, DXCC reach, and confirmed DXCC by band.")
                HelpDefinition(icon: "globe", title: "Country and country-band views", text: "Inspect worked and confirmed countries, then drill into the bands still missing confirmation for a specific entity.")
                HelpDefinition(icon: "clock.badge.questionmark", title: "Unconfirmed DXCC", text: "Find entities with worked QSOs but no confirmation and send the resulting set back to the Log Table as a filter.")
                HelpDefinition(icon: "chart.xyaxis.line", title: "Progress", text: "Use the chronological view to distinguish growth in activity from growth in confirmations.")
            }
            helpCallout(icon: "rectangle.inset.filled.and.person.filled", title: "A companion window", text: "Keep Statistics open while working in the main window. Actions that filter or reveal a QSO activate the Log Table; the statistics window remains available for the next comparison.", color: .purple)
        }
    }

    private var qrzIncoming: some View {
        Group {
            helpHeader(title: "QRZ Incoming Requests", subtitle: "Review confirmation requests from QRZ Logbook and politely collect missing details before creating any local contact.", icon: "tray.and.arrow.down.fill", color: .blue)
            HelpFlow(steps: [
                HelpFlowStep(icon: "key.fill", title: "Sign in", detail: "Use QRZ Login once to create the protected browser session used by QRZ Logbook."),
                HelpFlowStep(icon: "tray.and.arrow.down", title: "Load requests", detail: "Open Log Table > Tools > QRZ Incoming Requests. YAAM opens QRZ's Confirmation Requests view and keeps the last successful result available between launches."),
                HelpFlowStep(icon: "magnifyingglass", title: "Check the local log", detail: "Each request is marked when a matching local QSO already exists."),
                HelpFlowStep(icon: "square.and.pencil", title: "Compose a request", detail: "For an unmatched request, select Compose Email. YAAM immediately opens an editable recovery draft while it looks for the operator's published QRZ or HAMQTH address.")
            ])
            helpSection("Safe Completion") {
                HelpDefinition(icon: "doc.text", title: "Review before creating", text: "The email asks the operator for the QSO date, UTC time, band, mode, reports, and confirmation method. Add a local QSO only after the details are credible.")
                HelpDefinition(icon: "person.badge.key", title: "QRZ session", text: "Incoming requests are read through the user-approved QRZ browser session. If QRZ requires MFA or a browser check, complete it in QRZ Login and refresh.")
                HelpDefinition(icon: "at", title: "Missing email address", text: "If neither QRZ nor HAMQTH publishes an address, the draft stays open. Enter a recipient manually or use the QRZ profile button to continue your review.", color: .orange)
                HelpDefinition(icon: "paperplane", title: "Your mail account", text: "YAAM prepares the message in the mail composer for your review; it never sends the request silently.")
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

            HelpScreenshotCard(
                imageName: "help_sync_center",
                title: "Synchronization Health & Multi-Source Sync",
                caption: "One-click 'Sync All' for ARRL LoTW, QRZ Logbook, SDR-Control, Wavelog, and automatic scheduling."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "gearshape", title: "Configure", detail: "Choose live ADIF or SDR files and add LoTW or QRZ credentials."),
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Sync All", detail: "YAAM processes local sources first, then online confirmations."),
                HelpFlowStep(icon: "checkmark.shield", title: "Verify", detail: "Each source reports success, changes, duration, or a specific failure."),
                HelpFlowStep(icon: "clock.arrow.circlepath", title: "Schedule", detail: "Enable a single automatic interval for configured sources.")
            ])
            helpSection("Downloading Confirmations from QRZ & LoTW") {
                HelpInstruction(number: 1, title: "Open Sync Center", text: "Click 'Operator Desk' in the main top tab bar, then select 'Sync Center' from the panel bar (or choose Tools > Sync Center / press ⌘⇧S).")
                HelpInstruction(number: 2, title: "One-Click 'Sync All'", text: "Press the prominent blue 'Sync All' button in the top right corner. YAAM immediately contacts ARRL LoTW and QRZ Logbook to download all new confirmations.")
                HelpInstruction(number: 3, title: "Individual Provider Sync", text: "To pull confirmations from only one source, locate the LoTW or QRZ Logbook card and click the circular refresh icon (🔄) on the bottom right of that card.")
                HelpInstruction(number: 4, title: "Hands-Free Auto Sync", text: "Toggle 'Automatic sync' at the bottom and set an interval (e.g., 30 minutes) so YAAM automatically fetches new confirmations in the background.")
            }
            helpSection("Source Cards") {
                HelpDefinition(icon: "doc.text.fill", title: "External ADIF", text: "Watches the configured logger file and merges only meaningful additions or updates.")
                HelpDefinition(icon: "radio.fill", title: "SDR-Control", text: "Reads SmartSDR.smartsdrlog directly, ignores entries marked Deleted, normalizes date/time fields, and preserves the SDR Control record ID. When SDR Control stores the same QSO once at a rounded minute/frequency and once with precise seconds/frequency, YAAM keeps the precise identity and merges the richer details and confirmations into it.")
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
            helpHeader(title: "Two-way QSL Hub & Dispatcher", subtitle: "Send QSOs through official service paths, dispatch personalized 2-page QSL cards via email, and bring confirmations back safely.", icon: "arrow.left.arrow.right.circle.fill", color: .green)
            HelpScreenshotCard(
                imageName: "help_qsl_dispatcher",
                title: "Today's Confirmed QSL Dispatcher",
                caption: "Automated batch delivery of personalized 2-page QSL PDFs, live card previews, and anti-duplicate safeguards."
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "checkmark.seal.fill", title: "Detect Confirmed", detail: "YAAM identifies newly confirmed QSOs from today automatically."),
                HelpFlowStep(icon: "paperplane.fill", title: "One-Click Dispatch", detail: "Click 'Send QSLs' in the toolbar to review all un-emailed contacts."),
                HelpFlowStep(icon: "doc.richtext", title: "Live Preview", detail: "Inspect high-resolution 2-page personalized QSL cards and email bodies."),
                HelpFlowStep(icon: "envelope.badge.shield.half.filled", title: "Safe Send", detail: "Delivers via SMTP with built-in duplicate send protection.")
            ])
            helpSection("Today's Confirmed QSL Dispatcher") {
                HelpDefinition(icon: "paperplane.circle.fill", title: "Batch PDF Generation & Email", text: "Generates high-resolution 2-page personalized QSL cards (artwork + confirmation certificate) and delivers them directly to contact emails with zero manual typing.", color: .green)
                HelpDefinition(icon: "shield.lefthalf.filled", title: "Duplicate Delivery Prevention", text: "Contacts already emailed are visually badged ('Already Sent') and unselected by default, preventing accidental repeat emails while keeping full audit history.", color: .blue)
                HelpDefinition(icon: "flag.fill", title: "Complete Country Flag Support", text: "Accurate flag emojis for all world DXCC entities, including Taiwan, European/Asiatic Russia, Kosovo, and remote island entities.", color: .orange)
                HelpDefinition(icon: "doc.on.doc", title: "PDF & Bureau Export", text: "Export all generated cards to a local folder or queue them for physical bureau printout.", color: .indigo)
            }
            helpSection("Service Paths") {
                HelpDefinition(icon: "checkmark.seal", title: "LoTW through TQSL", text: "YAAM compiles ADIF and invokes your installed TrustedQSL command-line tool. Set the station location in Settings > LoTW or Station Profiles. See the dedicated 'LoTW & TQSL Digital Signing' guide for complete configuration details.")
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

    private var lotwTqslView: some View {
        Group {
            helpHeader(
                title: "LoTW & TQSL Digital Signing",
                subtitle: "Comprehensive guide to cryptographic QSO signing with ARRL TrustedQSL (tqsl), Default Station Location configuration, .p12 certificates, sandbox synchronization, and Zero-Click automated cloud uploads.",
                icon: "signature",
                color: .green
            )

            HelpLoTWSigningMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "app.badge.checkmark", title: "1. Define in TQSL", detail: "Open TrustedQSL on your Mac, click 'Station Locations', and note your exact location name (e.g. EP2AES-Home)."),
                HelpFlowStep(icon: "gearshape.fill", title: "2. Set in YAAM", detail: "In Settings > LoTW, enter your username and the exact Default Station Location matching TQSL."),
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "3. Sync Storage", detail: "Click 'Sync TQSL Data (~/.tqsl)' so YAAM's App Sandbox has full access to TQSL station_data and keys."),
                HelpFlowStep(icon: "doc.badge.gearshape.fill", title: "4. Link Certificate", detail: "Choose your .p12 certificate file and save the certificate password in macOS Keychain."),
                HelpFlowStep(icon: "paperplane.fill", title: "5. Sign & Upload", detail: "Use QSL Hub or enable Zero-Click Cloud Upload for automatic background signing and direct ARRL delivery.")
            ])

            helpSection("Default Station Location: Crucial Technical Requirement") {
                HelpDefinition(
                    icon: "mappin.and.ellipse",
                    title: "What is a Station Location in TQSL?",
                    text: "In ARRL Logbook of the World, a digital callsign certificate proves who you are, but the Station Location defines WHERE you operated. Inside the TrustedQSL app, each Station Location couples your callsign with your DXCC entity (e.g. Iran), Maidenhead Grid Locator (e.g. LL25wr), CQ Zone (21), ITU Zone (40), and administrative province or county.",
                    color: .orange
                )

                HelpDefinition(
                    icon: "exclamationmark.triangle.fill",
                    title: "Strict Exact String Matching (-l parameter)",
                    text: "When YAAM signs an ADIF log, it executes: tqsl -d -u -x -q -l \"<StationLocation>\" <file>. TQSL looks up this exact string in its internal station_data database. If the string has any spelling difference, capitalization discrepancy (e.g. ep2aes-home vs EP2AES-Home), or trailing whitespace, TQSL will fail immediately with exit code 1: 'Station location not found'.",
                    color: .red
                )

                HelpDefinition(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    title: "Global Default vs Profile-Specific Locations",
                    text: "The 'Default Station Location' configured in Settings > LoTW acts as the global fallback. If you operate from multiple locations (e.g., Home, Portable, Island, Contest), specify the exact TQSL location name in Settings > Stations > Service Identity for each profile. YAAM automatically chooses the profile's dedicated location whenever it signs contacts.",
                    color: .blue
                )
            }

            helpSection("macOS App Sandbox Synchronization (~/.tqsl)") {
                HelpDefinition(
                    icon: "lock.shield",
                    title: "The Sandbox Isolation Boundary",
                    text: "Under Apple's App Sandbox security model, YAAM cannot freely browse arbitrary files in your real user home folder (~/.tqsl). Instead, macOS gives the app a private sandbox container at ~/Library/Containers/ASIS.YAAM/Data/.tqsl.",
                    color: .secondary
                )

                HelpDefinition(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automated Timestamp-Based Synchronization",
                    text: "YAAM includes an intelligent synchronization engine (TQSLService.synchronizeTQSLStorage). On launch and before every signing operation, it compares file modification dates between ~/.tqsl and the container, automatically copying new station_data, certificates, and configuration files.",
                    color: .green
                )

                HelpDefinition(
                    icon: "cursorarrow.click.2",
                    title: "Manual 'Sync TQSL Data' Button",
                    text: "If you create, rename, or modify a Station Location inside the TrustedQSL desktop application while YAAM is running, click the 'Sync TQSL Data (~/.tqsl)' button in Settings > LoTW to immediately refresh the sandbox cache.",
                    color: .blue
                )
            }

            helpSection("Security, Certificates & Keychain Storage") {
                HelpDefinition(
                    icon: "doc.badge.gearshape.fill",
                    title: "Security-Scoped .p12 Bookmarks",
                    text: "When you select your LoTW .p12 certificate container, YAAM generates an Apple Security-Scoped Bookmark. This allows persistent, permission-granted access to the certificate across Mac restarts without copying private keys into the logbook database.",
                    color: .indigo
                )

                HelpDefinition(
                    icon: "key.horizontal.fill",
                    title: "Hardware-Bound Password Vault",
                    text: "Your certificate passphrase and LoTW account password are encrypted using AES-256-GCM with a hardware key derived from your Mac's unique platform UUID (IOPlatformUUID). They are stored safely in macOS Keychain.",
                    color: .green
                )
            }

            helpSection("Zero-Click Cloud Upload & Two-Way Reconciliation") {
                HelpDefinition(
                    icon: "bolt.fill",
                    title: "Zero-Click Background Daemon",
                    text: "When Zero-Click LoTW upload is enabled, every QSO logged via Quick Log, native FT8 Station, or WSJT-X is automatically micro-batched, signed with TQSL in the background, and uploaded to ARRL servers without requiring any manual export or button clicks.",
                    color: .yellow
                )

                HelpDefinition(
                    icon: "checkmark.seal.fill",
                    title: "Confirmation Tracking (LOTW_QSL_SENT & RCVD)",
                    text: "When ARRL LoTW accepts the signed upload, YAAM updates the local QSO with LOTW_QSL_SENT = Y and the upload date. During Sync QSLs, downloaded confirmations are matched using callsign, band, mode, and LoTW's standard 30-minute UTC window, marking LOTW_QSL_RCVD = Y.",
                    color: .green
                )
            }

            helpCallout(
                icon: "exclamationmark.octagon.fill",
                title: "Troubleshooting 'Station location not found'",
                text: "If you encounter an error during LoTW upload: (1) Open TrustedQSL app on your Mac. (2) Click 'Station Locations' and read the exact name. (3) Open YAAM Settings > LoTW and verify that 'Default Station Location' is typed identically. (4) Click 'Sync TQSL Data (~/.tqsl)' and retry.",
                color: .orange
            )
        }
    }

    private var todayQSLView: some View {
        Group {
            helpHeader(
                title: "Today's QSL Email Dispatcher",
                subtitle: "Automated batch delivery of personalized 2-page high-resolution QSL PDF cards with confirmation certificate, email templates, and anti-duplicate safeguards.",
                icon: "envelope.badge.shield.half.filled",
                color: .green
            )

            HelpScreenshotCard(
                imageName: "help_qsl_dispatcher",
                title: "Today's Confirmed QSL Dispatcher",
                caption: "Personalized 2-page PDF cards, live preview, and anti-duplicate safeguards."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "checkmark.seal.fill", title: "1. Detect Confirmed", detail: "YAAM automatically scans your Master Log for newly confirmed contacts from today."),
                HelpFlowStep(icon: "envelope.badge", title: "2. Review Contacts", detail: "Operators already emailed are flagged 'Already Sent' and unselected by default to prevent spam."),
                HelpFlowStep(icon: "doc.richtext", title: "3. Live 2-Page Preview", detail: "Inspect high-resolution front card artwork and reverse-side official confirmation certificate."),
                HelpFlowStep(icon: "paperplane.fill", title: "4. Batch Dispatch", detail: "Sends via your configured SMTP mail account with full audit logging in activity_audit.log.")
            ])

            helpSection("Card Architecture & Features") {
                HelpDefinition(icon: "doc.fill", title: "2-Page Professional PDF", text: "Page 1 renders high-definition station artwork and operator photo; Page 2 renders the official QSO confirmation certificate with callsign, band, mode, RST, grid, and operator signature.", color: .blue)
                HelpDefinition(icon: "shield.lefthalf.filled", title: "Anti-Duplicate Delivery Guard", text: "Maintains a persistent record of emailed recipients. Any contact previously emailed is visually badged and locked unless explicitly overridden by the operator.", color: .green)
                HelpDefinition(icon: "flag.fill", title: "Accurate DXCC National Flags", text: "Automatically attaches Unicode national flag emojis for every world DXCC entity in email subjects and bodies.", color: .orange)
            }
        }
    }

    private var qslLabelsView: some View {
        Group {
            helpHeader(
                title: "QSL Card Label Studio",
                subtitle: "Design, preview, calibrate, and print professional peel-and-stick adhesive labels for postcard QSL cards via Bureau or Direct mail with interactive sheet skip matrix.",
                icon: "printer.fill",
                color: .orange
            )

            HelpQSLLabelStudioMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "doc.text", title: "1. Select Sheet Format", detail: "Choose standard Avery formats (5160 30-up, 5162 14-up, 5163 10-up) or European A4 (L7160 21-up, L7162 16-up)."),
                HelpFlowStep(icon: "books.vertical.fill", title: "2. Choose QSO Source", detail: "Filter by Recent QSOs, Unconfirmed / Need QSL contacts, or selected contest sessions."),
                HelpFlowStep(icon: "scissors", title: "3. Interactive Skip Matrix", detail: "Click on any label slots that were previously peeled off a partially used sheet to prevent wasted labels!"),
                HelpFlowStep(icon: "slider.horizontal.2.square", title: "4. Calibrate Margins", detail: "Fine-tune horizontal/vertical offsets (in millimeters) to ensure flawless alignment with your printer tray."),
                HelpFlowStep(icon: "printer.fill", title: "5. Print or Export PDF", detail: "Send directly to your macOS system printer or generate a high-resolution print-ready PDF.")
            ])

            helpSection("Interactive Sheet Skip Matrix") {
                HelpDefinition(
                    icon: "hand.tap.fill",
                    title: "Zero-Waste Label Reuse",
                    text: "Adhesive label sheets are expensive. YAAM displays an interactive grid of your sheet layout. Simply click any already-used slots: YAAM marks them 'SKIPPED' and begins printing on the first intact blank label.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "arrow.clockwise",
                    title: "Persistent Sheet Memory",
                    text: "The skip matrix remembers remaining blank positions across multiple print runs until you reset the sheet layout.",
                    color: .blue
                )
            }

            helpSection("Printer Calibration & Customization") {
                HelpDefinition(
                    icon: "ruler",
                    title: "Sub-Millimeter Alignment Offsets",
                    text: "Compensate for hardware paper tray shift with dedicated X and Y offset sliders (±5.0 mm in 0.1 mm increments).",
                    color: .green
                )
                HelpDefinition(
                    icon: "textformat",
                    title: "Rich Label Content & Routing Tags",
                    text: "Labels automatically render station callsign, 2-way QSO confirmation grid, RST, Band, Mode, Satellite name/propagation mode, and routing instructions ('PSE QSL VIA BUREAU' or 'TNX QSL').",
                    color: .secondary
                )
            }

            helpCallout(
                icon: "checkmark.seal.fill",
                title: "Print & Bureau Workflow",
                text: "After printing labels, you can immediately peel and stick them to standard postcard QSL cards for delivery through the national IARU QSL Bureau or direct airmail.",
                color: .orange
            )
        }
    }

    private var awards: some View {
        Group {
            helpHeader(title: "Awards: Online and Local Evidence", subtitle: "Review QRZ achievements, LoTW-confirmed progress, and YAAM's local planning estimates without confusing evidence with an issuer's final decision.", icon: "medal.fill", color: .orange)
            HelpScreenshotCard(
                imageName: "help_awards",
                title: "Awards & Achievement Dashboard",
                caption: "Comprehensive LoTW milestones (DXCC, WAS, VUCC) and authenticated QRZ achievements."
            )
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
            helpSection("What the Awards Page Combines") {
                HelpDefinition(icon: "trophy.fill", title: "QRZ achievements", text: "Issued QRZ awards and available progress are read from the authenticated QRZ Logbook Awards workflow. Achievement text and completion percentages stay provider-specific.", color: .orange)
                HelpDefinition(icon: "checkmark.seal.fill", title: "LoTW evidence", text: "LoTW cards show practical DXCC, WAS, and VUCC-style counts calculated only from LoTW-confirmed QSOs already reconciled with the active Master Log.", color: .green)
                HelpDefinition(icon: "chart.bar.doc.horizontal", title: "Local award planning", text: "YAAM can estimate what is worked or confirmed across the log. A local 100% result is a planning signal unless the issuing organization has also granted the award.", color: .blue)
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
            helpHeader(title: "Import Review", subtitle: "See exactly what an ADIF or SmartSDR file will change before it reaches the Master Log.", icon: "doc.text.magnifyingglass", color: .orange)
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
            helpSection("Activity Audit Trail") {
                HelpDefinition(icon: "doc.text.magnifyingglass", title: "Comprehensive Audit Log", text: "Every user and automated action is permanently recorded in activity_audit.log with ISO-8601 timestamps, operation types, targets, and result statuses.")
                HelpDefinition(icon: "arrow.triangle.2.circlepath.circle", title: "Smart Rotation (15 MB)", text: "To prevent disk bloating, the audit log automatically rotates when it reaches 15 MB, keeping up to 5 historical compressed archives.")
                HelpDefinition(icon: "magnifyingglass.circle.fill", title: "One-Click Finder Inspection", text: "Select 'Reveal Activity Audit Log in Finder...' from the Help or Tools menu to immediately locate and inspect your audit trail.")
            }
            helpCallout(icon: "internaldrive.fill", title: "Stored locally", text: "Restore points and activity audit logs remain strictly in YAAM's sandboxed Application Support folder and are never uploaded to any remote server.", color: .blue)
        }
    }

    private var credentials: some View {
        Group {
            helpHeader(title: "Credentials & Keychain", subtitle: "Passwords, API keys, and QRZ browser session cookies are protected by the macOS credential store and Hardware-Bound AES-256-GCM encryption.", icon: "lock.shield.fill", color: .green)
            HelpFlow(steps: [
                HelpFlowStep(icon: "rectangle.and.pencil.and.ellipsis", title: "Enter", detail: "Add the secret in the relevant Settings tab."),
                HelpFlowStep(icon: "key.fill", title: "Protect", detail: "Press Save once to write it to macOS Keychain and Secure Vault."),
                HelpFlowStep(icon: "network", title: "Use", detail: "The value is decrypted in memory only when contacting that service."),
                HelpFlowStep(icon: "trash.slash", title: "Keep private", detail: "It is never written to plain text preferences or exported with ADIF.")
            ])
            helpSection("Hardware-Bound AES-256-GCM Secure Vault") {
                HelpDefinition(icon: "cpu", title: "Bound to Mac Hardware", text: "Sensitive tokens and credentials are encrypted using AES-256-GCM with a key derived from your Mac's unique hardware platform UUID (IOPlatformUUID). Even if database or setting files are copied to another computer, they cannot be decrypted.")
                HelpDefinition(icon: "shield.lefthalf.filled", title: "Cryptographic Salt & POSIX Permissions", text: "Each installation generates a unique 256-bit cryptographic salt stored with POSIX 0o600 permissions (user-read/write only), safeguarding credentials against unauthorized access.")
                HelpDefinition(icon: "key.viewfinder", title: "Dual Keychain Fallback", text: "YAAM pairs macOS Keychain Services with the Hardware-Bound Vault for maximum reliability across sandboxed environments and headless operations.")
            }
            helpSection("Credential Scope") {
                HelpDefinition(icon: "person.crop.circle", title: "Account-wide", text: "QRZ login password, LoTW password, HAMQTH password, and SMTP app password.")
                HelpDefinition(icon: "chart.line.uptrend.xyaxis", title: "QRZ Rank Service", text: "Leaderboard and log enrichment use a personal API token from qrz-rank.asis.sh. Generate it in the QRZ Rank panel, then save it in Settings > Rank Service. The token is stored in Keychain and is separate from your QRZ.com credentials.")
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
                HelpInstruction(number: 8, title: "Inspect activity", text: "Open Tools > Activity Console to search, copy, or clear detailed import, sync, award, and service messages in a separate resizable window. Convert now shows only compact processing status.")
            }
            helpCallout(icon: "gauge.with.dots.needle.67percent", title: "Server-managed Rank allowance", text: "Leaderboard, enrichment, and Daily Rank share the allowance assigned to your token by qrz-rank.asis.sh. YAAM checks the server before a batch, shows the reported remaining count or unlimited status, and pauses safely when the service says the allowance is exhausted. Stopping a backfill keeps every completed result.", color: .green)
            helpCallout(icon: "info.circle.fill", title: "Guest logs", text: "Opening ADIF or SmartSDR as a Guest keeps it outside the active station database. A SmartSDR source is read-only; Save exports a separate ADIF and never overwrites the binary source.", color: .blue)
        }
    }

    private var convertExportView: some View {
        Group {
            helpHeader(
                title: "Convert & Export Formats",
                subtitle: "Export logs to Excel/CSV, Cabrillo 3.0 contest format, standard ADIF 3.1.4, JSON database array, interactive HTML report, or clean text summaries.",
                icon: "square.and.arrow.up.circle.fill",
                color: .blue
            )

            HelpScreenshotCard(
                imageName: "help_convert_export",
                title: "Log Conversion & Multi-Format Export",
                caption: "Export to Excel/CSV, Cabrillo 3.0 contest format, ADIF 3.1.4, and interactive HTML."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "tray.full.fill", title: "1. Select Source", detail: "Choose External File (.adi, .smartsdrlog) or active YAAM SQLite Database."),
                HelpFlowStep(icon: "slider.horizontal.3", title: "2. Set Filters", detail: "Optionally apply UTC Contest window, Band, or Mode filters."),
                HelpFlowStep(icon: "doc.text.badge.plus", title: "3. Choose Format", detail: "Select Excel/CSV, Cabrillo 3.0, ADIF, JSON, HTML, or Text."),
                HelpFlowStep(icon: "square.and.arrow.up", title: "4. Convert & Save", detail: "Output is written atomically and can be opened with one click.")
            ])

            helpSection("Supported Export Formats") {
                HelpDefinition(icon: "tablecells.badge.ellipsis", title: "Excel / CSV (.csv)", text: "Formatted spreadsheet with UTF-8 BOM encoding. Opens cleanly in Microsoft Excel, Apple Numbers, and Google Sheets without character corruption.")
                HelpDefinition(icon: "flag.checkered.circle.fill", title: "Cabrillo 3.0 (.cbr / .log)", text: "Official contest format compliant with CQ WW, ARRL, and IARU robots. Includes configurable Contest ID, Category, Power, Operator, and Claimed Score.")
                HelpDefinition(icon: "doc.text.fill", title: "ADIF 3.1.4 (.adi)", text: "Standard amateur radio interchange format recognized by LoTW, QRZ.com, eQSL, Club Log, and all logging software.")
                HelpDefinition(icon: "curlybraces", title: "JSON Database (.json)", text: "Structured JSON array of QSO objects suitable for web applications, scripting, and cloud backups.")
                HelpDefinition(icon: "safari.fill", title: "Interactive HTML Report (.html)", text: "Self-contained dark/light styled HTML table with station metadata, band statistics breakdown, and sortable QSO records viewable in any web browser.")
                HelpDefinition(icon: "doc.plaintext", title: "Text Summary & Matrix (.txt)", text: "Human-readable ASCII log summary report with band/mode statistics matrix and formatted QSO lines.")
            }

            helpCallout(icon: "timer", title: "UTC Contest Time Slicing", text: "When 'Enable UTC Time Filter' is active, start and end times operate in true UTC, allowing you to slice contest sessions across midnight seamlessly.", color: .orange)
        }
    }

    private var globeGridsView: some View {
        Group {
            helpHeader(
                title: "3D Globe & GridTracker",
                subtitle: "Visualize DX contacts, real-time cluster spots, Maidenhead grid squares, and the solar terminator in high-performance Metal 3D or 2D projections.",
                icon: "globe.americas.fill",
                color: .cyan
            )

            HelpScreenshotCard(
                imageName: "help_globe",
                title: "3D Globe & GridTracker Workspace",
                caption: "Maidenhead grid overlays, real-time grayline terminator, and great-circle QSO paths."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "globe.americas", title: "Projection", detail: "Switch between 3D Spherical Globe, 2D Equirectangular, or Mercator views."),
                HelpFlowStep(icon: "sun.max.fill", title: "Solar Terminator", detail: "Real-time grayline calculation showing day/night boundaries and solar subpoint."),
                HelpFlowStep(icon: "square.grid.3x3.fill", title: "Grid Overlays", detail: "View Maidenhead grid squares (4-char & 6-char) color-coded by worked/confirmed status."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "Live Spots", detail: "Cluster spots render as interactive glowing pins with bearing and distance.")
            ])

            helpSection("Key Capabilities") {
                HelpDefinition(icon: "sparkles", title: "High-Performance Rendering", text: "Hardware-accelerated via Apple Metal and SceneKit with zero CPU stutter and smooth 60 FPS rotation.")
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "GridTracker Integration", text: "Instantly identify worked, confirmed, and unworked Maidenhead grid squares for VUCC, 6m Magic Band, and Satellite awards.")
                HelpDefinition(icon: "moon.stars.fill", title: "Grayline Propagation", text: "Easily spot sunrise/sunset greyline openings on low bands (160m, 80m, 40m) where ionospheric D-layer absorption drops.")
            }
        }
    }

    private var bandmapView: some View {
        Group {
            helpHeader(
                title: "Spectrum Bandmap & Waterfall",
                subtitle: "Interactive 3-pane radio spectrum workspace featuring a vertical frequency ruler, live SDR waterfall, DX cluster spots, dual VFO split tracking, and 1-click transceiver QSY.",
                icon: "waveform.path.ecg.rectangle",
                color: .mint
            )

            HelpBandmapMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "square.split.3x1", title: "1. Choose View Mode", detail: "Switch between Studio (3-Pane), Ruler & Spots, SDR Waterfall, or 4-Band Multi-Band Panorama."),
                HelpFlowStep(icon: "link", title: "2. Connect Rig CAT", detail: "Connect via Hamlib rigctld, FLRig, or TCI SDR for zero-latency bidirectional frequency synchronization."),
                HelpFlowStep(icon: "waveform.path.ecg", title: "3. Monitor Activity", detail: "Observe RF density on the thermal heatmap ribbon and watch real-time waterfall signal traces."),
                HelpFlowStep(icon: "hand.tap.fill", title: "4. One-Click QSY & Log", detail: "Click any spot or frequency on the ruler to jump your VFO instantly; double-click to populate Quick Log.")
            ])

            helpSection("Layout Architecture & Panes") {
                HelpDefinition(
                    icon: "ruler.fill",
                    title: "Left Pane: Vertical Bandmap Ruler",
                    text: "Precision frequency scale with color-coded subbands for CW, Data/Digital, and Phone. Plotted cluster spots show callsign, mode, signal report, and age-based fade.",
                    color: .mint
                )
                HelpDefinition(
                    icon: "waveform.path.ecg",
                    title: "Center Pane: Live SDR Spectrum & Waterfall",
                    text: "Real-time spectrum analyzer with adjustable FFT zoom (0.5x to 4x), peak hold indicators, and smooth cascading multi-color waterfall gradient.",
                    color: .blue
                )
                HelpDefinition(
                    icon: "scope",
                    title: "Right Pane: DX Spot Hunter Table",
                    text: "Sortable spot feed with freshness tags (Fresh, Active, Aging), New DXCC / ATNO badges, SNR telemetry, and 1-click 'Tune Rig' actions.",
                    color: .orange
                )
            }

            helpSection("Advanced Transceiver & Operating Features") {
                HelpDefinition(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Dual VFO & Split Frequency Tracking",
                    text: "Visual markers for VFO A (green) and VFO B (orange) allow you to visualize DX split operations (e.g., listening up 5 kHz) directly on the spectrum ruler.",
                    color: .yellow
                )
                HelpDefinition(
                    icon: "scope",
                    title: "Pileup Sniper Target Reticle",
                    text: "When a DX spot contains split comments, a luminous yellow sniper reticle marks the optimal VFO-B transmit frequency directly on the vertical ruler. Clicking the reticle selects the solution and arms split.",
                    color: .orange
                )
                HelpDefinition(
                    icon: "flame.fill",
                    title: "Thermal Activity Heatmap Ribbon",
                    text: "Accumulates RF spot activity over rolling 15-minute windows, highlighting hot pile-up frequencies even before signals appear on your local antenna.",
                    color: .red
                )
                HelpDefinition(
                    icon: "square.grid.2x2",
                    title: "Multi-Band Panorama Mode",
                    text: "Monitors 40m, 20m, 15m, and 10m simultaneously in a 2x2 grid, giving contest operators an instant overview of HF band openings.",
                    color: .purple
                )
            }

            helpCallout(
                icon: "shield.lefthalf.filled",
                title: "License Class & IARU Privileges",
                text: "Select your license class (e.g. US Extra, General, Technician) and IARU Region (1, 2, or 3) to overlay permitted frequency segments directly on the bandmap ruler.",
                color: .mint
            )
        }
    }

    private var cwWinKeyerView: some View {
        Group {
            helpHeader(
                title: "CW Keyer & WinKeyer Integration",
                subtitle: "Precision Morse code transmission via software keyer or dedicated K1EL WinKeyer hardware USB interfaces.",
                icon: "cable.connector.horizontal",
                color: .yellow
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "cable.connector", title: "Connect Port", detail: "Select your serial port (USB-to-UART / WinKeyer) in Settings or Operator Desk."),
                HelpFlowStep(icon: "speedometer", title: "Speed Control", detail: "Adjust speed from 5 to 50 WPM with real-time speed pot sync."),
                HelpFlowStep(icon: "keyboard", title: "Macros F1–F12", detail: "One-click transmission of CQ, exchange, TU, serial numbers, and callsigns."),
                HelpFlowStep(icon: "tuningfork", title: "Paddle & Sidetone", detail: "Configure Iambic A/B, Ultimatic, paddle reverse, and internal sidetone frequency.")
            ])

            helpSection("WinKeyer Protocol Features") {
                HelpDefinition(icon: "waveform", title: "Hardware Timing", text: "WinKeyer generates pristine Morse code directly on the microcontroller, eliminating macOS USB latency jitter.")
                HelpDefinition(icon: "textformat.abc", title: "Prosigns & Cut Numbers", text: "Supports standard prosigns (AR, SK, KN, BT) and contest cut numbers (e.g. 5NN for 599).")
            }
        }
    }

    private var cwAcademyView: some View {
        Group {
            helpHeader(
                title: "CW Academy & Audio Decoder",
                subtitle: "Interactive Morse code training with the Koch method, Farnsworth timing, real-time Goertzel DSP audio decoder, and comprehensive CW operating reference desk.",
                icon: "headphones.circle.fill",
                color: .yellow
            )

            HelpCWAcademyMockup()

            HelpFlow(steps: [
                HelpFlowStep(icon: "graduationcap.fill", title: "Select Lesson", detail: "Advance letter-by-letter through the 40-character Koch method sequence."),
                HelpFlowStep(icon: "speedometer", title: "Farnsworth Timing", detail: "Train ears at 20 WPM character speed with extended spacing to avoid counting dots."),
                HelpFlowStep(icon: "waveform.badge.magnifyingglass", title: "Echo Trainer", detail: "Key the character back on paddles or keyboard with instant accuracy evaluation."),
                HelpFlowStep(icon: "waveform.path.ecg", title: "DSP Audio Decoder", detail: "Feed audio from your rig to decode live CW tones with Goertzel peak detection.")
            ])

            helpSection("The Koch Method & Farnsworth Spacing") {
                HelpDefinition(icon: "brain.head.profile", title: "Sound-Shape Recognition", text: "Instead of mentally converting dots and dashes, you learn characters directly as acoustic rhythms at full speed (20+ WPM).", color: .yellow)
                HelpDefinition(icon: "timer", title: "Farnsworth Spacing", text: "Maintains full-speed character sound-shapes while elongating intervals between characters, giving your brain time to register before the next symbol arrives.", color: .orange)
                HelpDefinition(icon: "repeat", title: "Adaptive Assistant", text: "YAAM monitors your response latency and error rates, automatically re-injecting troublesome characters until 90%+ mastery is achieved.", color: .green)
            }

            helpSection("Real-Time Goertzel DSP Audio Decoder") {
                HelpDefinition(icon: "waveform", title: "Goertzel Tone Filter (700 Hz)", text: "High-Q filter isolates CW carrier tones from band noise, providing clean Morse key-up and key-down transitions even in crowded pile-ups.", color: .blue)
                HelpDefinition(icon: "gauge.with.needle", title: "Automatic WPM Tracking", text: "Adapts to changing sender speeds between 10 and 45 WPM with adaptive thresholding.", color: .green)
            }

            helpSection("CW Operating Reference Desk") {
                HelpDefinition(icon: "questionmark.bubble.fill", title: "Standard Q-Codes", text: "Instant lookup for essential Q-codes: QTH (location), QSL (acknowledge), QSY (change frequency), QRM (man-made noise), QRN (atmospheric noise), QSB (fading).", color: .purple)
                HelpDefinition(icon: "textformat.abc", title: "Common Abbreviations & Prosigns", text: "Standard prosigns (AR, SK, KN, BT, AS) and contest abbreviations (5NN, AGN, TU, BK, 73, WX).", color: .secondary)
            }

            helpCallout(
                icon: "lightbulb.fill",
                title: "Training Tip",
                text: "Never practice Morse below 18 WPM. Counting dots (dits) and dashes (dahs) creates a mental wall at 10–12 WPM that is very hard to break. Train with Koch at 20 WPM effective 12 WPM for effortless high-speed copying.",
                color: .yellow
            )
        }
    }

    private var competitorsView: some View {
        Group {
            helpHeader(
                title: "Competitor & Rival Tracking",
                subtitle: "Track activity, growth rates, and confirmed QSO progression curves against regional and global rivals over time.",
                icon: "chart.line.uptrend.xyaxis",
                color: .purple
            )

            HelpScreenshotCard(
                imageName: "help_leaderboard",
                title: "Leaderboard & 360° Radar",
                caption: "Rival performance trajectories, rank percentiles, and band coverage."
            )

            HelpFlow(steps: [
                HelpFlowStep(icon: "person.crop.circle.badge.plus", title: "Add Rival", detail: "Enter competitor callsign, baseline confirmed QSOs, and monthly rate."),
                HelpFlowStep(icon: "chart.xyaxis.line", title: "Progression Curve", detail: "Compare your station's growth against all rivals over -12m to +12m timelines."),
                HelpFlowStep(icon: "speedometer", title: "Velocity Table", detail: "Head-to-head table showing monthly velocity (QSO/mo) and trend indicators."),
                HelpFlowStep(icon: "calendar.badge.clock", title: "Overtake Forecast", detail: "Mathematical forecast predicting exact dates when you will overtake a competitor.")
            ])

            helpSection("Trend Indicators") {
                HelpDefinition(icon: "arrow.up.right", title: "Surging (↑↑)", text: "Competitor is expanding activity at over 150 QSO/month.", color: .green)
                HelpDefinition(icon: "arrow.right", title: "Steady (→)", text: "Consistent operating pace between 30 and 80 QSO/month.", color: .blue)
                HelpDefinition(icon: "arrow.down.right", title: "Cooling (↘)", text: "Activity has slowed below 30 QSO/month.", color: .orange)
            }
        }
    }

    private var tciSdrView: some View {
        Group {
            helpHeader(
                title: "TCI & SDR Integration",
                subtitle: "Direct IP connection to ExpertSDR / SunSDR transceivers for zero-latency frequency sync, spot tuning, and dual VFO control.",
                icon: "waveform.path.ecg.rectangle",
                color: .mint
            )
            HelpFlow(steps: [
                HelpFlowStep(icon: "network", title: "Enable TCI", detail: "Start TCI server in ExpertSDR (default port 40001)."),
                HelpFlowStep(icon: "link", title: "Connect in YAAM", detail: "Enter host and port in Operator Desk > TCI SDR panel."),
                HelpFlowStep(icon: "arrow.triangle.2.circlepath", title: "Bidirectional Sync", detail: "VFO frequency, mode, and modulation sync automatically in real time."),
                HelpFlowStep(icon: "dot.radiowaves.left.and.right", title: "Click-to-Tune", detail: "Clicking any cluster spot instantly QSYs your SDR to the exact frequency.")
            ])
        }
    }

    private var on4kstView: some View {
        Group {
            helpHeader(
                title: "ON4KST Chat & Microwave",
                subtitle: "Real-time communication and spot coordination with VHF, UHF, and Microwave operators across 50 MHz, 144 MHz, 432 MHz, and 1.2+ GHz.",
                icon: "bubble.left.and.bubble.right.fill",
                color: .indigo
            )
            helpSection("Chat Rooms") {
                HelpDefinition(icon: "antenna.radiowaves.left.and.right", title: "50/70 MHz (6m & 4m)", text: "Real-time Sporadic-E, TEP, and F2 opening alerts.")
                HelpDefinition(icon: "wave.3.forward", title: "144/432 MHz (2m & 70cm)", text: "Tropo ducting, meteor scatter (MSK144), and aurora skeds.")
                HelpDefinition(icon: "sparkle", title: "Microwave (1.2 GHz+)", text: "Rain scatter, EME (Earth-Moon-Earth), and line-of-sight tests.")
            }
        }
    }

    private var faq: some View {
        Group {
            helpHeader(
                title: "FAQ & Knowledge Base",
                subtitle: "Answers to common operating questions, data format tips, synchronization details, and troubleshooting.",
                icon: "questionmark.circle.fill",
                color: .blue
            )
            FAQItem(question: "How do I export my logbook to Microsoft Excel without character issues?", answer: "Open Convert & Export, select 'Excel / CSV (.csv)', and click Convert. YAAM automatically embeds a UTF-8 BOM (Byte Order Mark), so Persian, Arabic, accented characters, and Cyrillic names open with 100% precision in Excel, Apple Numbers, and Google Sheets.")
            FAQItem(question: "How do I export a contest log in Cabrillo format for CQ WW / ARRL?", answer: "In Convert & Export, select 'Cabrillo 3.0 (.cbr / .log)'. Enter your Contest ID (e.g. CQ-WW-SSB), category (SINGLE-OP), power (HIGH/LOW/QRP), and Claimed Score. YAAM generates official Cabrillo 3.0 output ready for robot email submission.")
            FAQItem(question: "Why does the Awards page show instant progress now?", answer: "YAAM calculates real-time DXCC 100, WAC, WAS, VUCC Grids, WPX, and 6m Magic Band progress directly from your local master log in milliseconds, and caches QRZ award summaries so you never have to wait or repeatedly press refresh.")
            FAQItem(question: "How does the UTC contest filter handle time and midnight?", answer: "Both pickers and the displayed range are true UTC values rounded to the minute. The start is included and the end is excluded, so 19:00 to 21:00 includes contacts from 19:00:00 through 20:59:59 and can safely cross UTC midnight.")
            FAQItem(question: "Can Convert filter FT8 records stored as MFSK?", answer: "Yes. Mode filtering checks both ADIF MODE and SUBMODE, so selecting FT8 matches records stored as MODE=MFSK and SUBMODE=FT8. Band filtering can also infer a missing BAND from FREQ.")
            FAQItem(question: "Can I import SmartSDR.smartsdrlog without exporting ADIF first?", answer: "Yes. Choose File > Import Log File or select it in Convert. YAAM reads SDR Control's binary property list directly, skips Deleted entries, and normalizes QSO date/time.")
            FAQItem(question: "Does DX Advisor use the active station?", answer: "Yes. Grid Locator, radio, power, antenna, and height come from the active station profile.")
            FAQItem(question: "What frequency formats does Quick Log accept?", answer: "MHz, kHz, and Hz are accepted. For 20-meter FT8, 14.074, 14074, and 14074000 resolve to the same frequency and band.")
            FAQItem(question: "Why is a DX spot marked as new?", answer: "Status is calculated from the active station's Master Log. New Callsign means no prior QSO; New Band means the callsign exists but not on that band.")
            FAQItem(question: "Why did Sync All skip a source?", answer: "Only configured sources run. Open the source card or its Settings section and supply the required file, password, or station API key.")
            FAQItem(question: "How do QRZ and LoTW confirmation downloads stay complete?", answer: "Sync QSLs downloads incremental changes. Use the visible Full QSL History button to retrieve both providers from the beginning. YAAM reports downloaded, locally matched, unmatched, and updated counts separately.")
            FAQItem(question: "What happens when duplicate QSOs are removed?", answer: "YAAM keeps the record with the strongest confirmation evidence and most complete data, fills its missing fields from the duplicates, and removes only the selected extras. A database checkpoint is created first so the operation remains recoverable.")
            FAQItem(question: "Why are Russia, European Russia, and Asiatic Russia separate?", answer: "European Russia and Asiatic Russia are separate DXCC entities, while a plain Russia value is ambiguous source data. YAAM therefore keeps all three labels distinct instead of assigning credit to the wrong entity.")
            FAQItem(question: "What password should Gmail SMTP use?", answer: "Use a Google App Password, not the normal Google account password. YAAM stores it safely in macOS Keychain.")
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

struct HelpScreenshotCard: View {
    let imageName: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("— \(caption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.8)
        )
        .padding(.vertical, 6)
    }
}

// MARK: - Native Visual UI Mockup Components

struct HelpLoTWSigningMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("ARRL TrustedQSL (tqsl) Engine — Cryptographic ADIF Signer")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("CLI Ready")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Default Station Location:")
                        .font(.caption.weight(.medium))
                        .frame(width: 165, alignment: .leading)
                    Text("EP2AES-Home")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                        Text("MATCHES TQSL NAME").font(.system(size: 9, weight: .heavy))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Must exactly match the Station Location name defined in TrustedQSL (case-sensitive). If TQSL has 'EP2AES-Home', entering 'Home' or 'ep2aes-home' causes TQSL exit code 1: 'Station location not found'.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(spacing: 6) {
                HStack {
                    Label("Storage Sync:", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .frame(width: 165, alignment: .leading)
                    Text("~/.tqsl Synced with Sandbox Container (24 items)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sync TQSL Data (~/.tqsl)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }

                HStack {
                    Label("Certificate (.p12):", systemImage: "doc.badge.gearshape.fill")
                        .font(.caption.weight(.medium))
                        .frame(width: 165, alignment: .leading)
                    Text("EP2AES_Cert.p12 (Security Bookmark Active)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Keychain Secured")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("AUTOMATED EXECUTION PIPELINE:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("tqsl -d -u -x -q -l \"EP2AES-Home\" -p •••••••• ~/Library/Containers/.../upload.adi")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.yellow)
                Text("Zero-Click Cloud Upload Daemon:")
                    .font(.caption.weight(.semibold))
                Text("Auto-signs and submits newly logged QSOs to LoTW in background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpCWAcademyMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "headphones.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Text("CW Academy Morse Tutor & Real-Time DSP Audio Decoder")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Koch Method: Lesson 18/40")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.15))
                    .foregroundStyle(.orange)
                    .cornerRadius(4)
            }
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVE CHARACTERS IN LESSON:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("K  M  R  S  U  A  P  T  L  O  W  I  .  N  J  E  F  0  Y")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Character Speed").font(.caption2).foregroundStyle(.secondary)
                    Text("20 WPM").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Effective (Farnsworth)").font(.caption2).foregroundStyle(.secondary)
                    Text("12 WPM").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Sidetone").font(.caption2).foregroundStyle(.secondary)
                    Text("700 Hz (Sine)").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Echo Accuracy").font(.caption2).foregroundStyle(.secondary)
                    Text("98.4%").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("GOERTZEL DSP AUDIO DECODER:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Peak: 700 Hz  |  SNR: +18.4 dB  |  Auto-Track: 21.8 WPM")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(.green)
                    Text("CQ CQ CQ DE EP2AES EP2AES K")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpHamClockMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "deskclock.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Text("HamClock Shack Dashboard & Remote Web Server")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("LAN Server: 8080 Active")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            }
            Divider()

            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text("UTC TIME").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text("16:15:20").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundStyle(.blue)
                    Text("LOCAL 19:45:20").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 4) {
                    Text("SOLAR INDICES").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Text("SFI 168").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                        Text("SSN 142").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                    }
                    Text("A: 6  |  Kp: 2 (Quiet)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 4) {
                    Text("IONOSPHERE").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text("SDO 304Å Live").font(.system(size: 11, weight: .bold)).foregroundStyle(.yellow)
                    Text("DRAP: 0.2 dB (Normal)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Image(systemName: "ipad.and.iphone").foregroundStyle(.indigo)
                Text("Broadcast to Tablet/iPad:")
                    .font(.caption.weight(.medium))
                Text("http://192.168.1.55:8080")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Spacer()
                Text("Zero Config")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpCallIntelligenceMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Text("Call Intelligence Panel (CIP) — Deep Operator & Tactical HUD")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("CIP Active")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15), in: Capsule())
            }
            Divider()

            // Callsign Entity Bar
            HStack(spacing: 12) {
                Text("🇲🇺").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("3B8/W1AW")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(.yellow)
                        Text("NEW DXCC")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Text("Mauritius · Indian Ocean (AF) · CQ 39 · ITU 53 · Grid LG89ts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Bearing: 165° SSE (LP 345°)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("Dist: 5,420 km · Sun: +18° Day")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

            // Badges Grid: SCP, LoTW & Clubs
            HStack(spacing: 8) {
                // SCP Matches
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 10)).foregroundStyle(.cyan)
                        Text("SCP Contesters:").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(["3B8/W1AW", "3B8AW", "3B8BA", "3B8CF"], id: \.self) { c in
                            Text(c)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(c == "3B8/W1AW" ? .yellow : .primary)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(c == "3B8/W1AW" ? Color.yellow.opacity(0.2) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }

                Spacer()

                // LoTW & Clubs
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(.green)
                        Text("LoTW Active (Sep 2026)").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                    }
                    HStack(spacing: 4) {
                        Text("CWops #1842").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        Text("SKCC #24500").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.mint)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        Text("LICW #920").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.purple)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            // Propagation & Sniper Banner
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("20m Path: 95% OPEN (+18 dB)").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                    Text("· MUF 31.2 MHz · FOT 26.5 MHz").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "scope").font(.system(size: 9)).foregroundStyle(.yellow)
                    Text("Sniper: Target 14026.0k (+6.0k)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15), in: Capsule())
            }
            .padding(6)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpPileupSniperMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack {
                Image(systemName: "scope")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Pileup Sniper & Split QSX Cockpit")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.circle.fill").font(.system(size: 10))
                    Text("Stepping UP · 88% Conf")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15), in: Capsule())
            }
            Divider()

            // Dual VFO Comparison
            HStack(spacing: 12) {
                // VFO-A
                VStack(alignment: .leading, spacing: 2) {
                    Text("VFO-A (DX RX):").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Text("14.020.000 MHz")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("Preserved on DX receiver").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

                // Target VFO-B
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("TARGET VFO-B (MY TX):").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                        Spacer()
                        Text("+6.0 kHz").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(.yellow)
                    }
                    Text("14.026.000 MHz")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.yellow)
                    Text("Optimal next predicted CQ target").font(.system(size: 8.5)).foregroundStyle(.yellow.opacity(0.8))
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.4), lineWidth: 1))
            }

            // Big Arming Button
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "scope").font(.system(size: 12, weight: .bold))
                    Text("ARM VFO-B TO 14.026.0 MHz (+6.0 kHz)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                Spacer()
            }

            // Split Spectrum Visualizer Track
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SPLIT SPECTRUM TRACK: UP 1.0 TO 8.0 kHz").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("3 Verified Historical Hits").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.5))
                        .frame(height: 24)

                    HStack {
                        Spacer().frame(width: 40)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 6, height: 6)
                        Spacer().frame(width: 60)
                        Circle().fill(Color.white.opacity(0.6)).frame(width: 6, height: 6)
                        Spacer().frame(width: 60)
                        Circle().fill(Color.white).frame(width: 7, height: 7)
                        Spacer().frame(width: 50)
                        ZStack {
                            Circle().stroke(Color.yellow, lineWidth: 1.5).frame(width: 14, height: 14)
                            Circle().fill(Color.yellow).frame(width: 5, height: 5)
                        }
                        Spacer()
                    }
                }
            }

            // Tactical Advice
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.system(size: 11))
                Text("Tactical Advice: DX stepping UP (+1.5 kHz/step). Last worked 14024.5 kHz. Target 14026.0 kHz for next CQ.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpGreylineOverlayMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sun.horizon.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Live Greyline Propagation Overlay & Station Solar HUD")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Astronomical Ephemeris")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .cornerRadius(4)
            }
            Divider()

            // Visual Twilight Matrix
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text("CIVIL TWILIGHT (0° TO -6°)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.orange.opacity(0.4), Color.purple.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("D-Layer Collapses").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("NAUTICAL TWILIGHT (-6° TO -12°)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    Rectangle()
                        .fill(Color(red: 0.1, green: 0.12, blue: 0.25))
                        .frame(height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Optimal Waveguide Duct").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("NIGHT (< -12°)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Nocturnal F2 Skywave").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Station HUD Telemetry Preview
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.horizon.fill").foregroundStyle(.orange)
                    Text("STATION HUD:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Text("GREYLINE ACTIVE (-4.2°)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.orange)
                }
                Spacer()
                Label("Sunset in 5h 20m", systemImage: "clock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Duct 95% (160/80m)").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("Great Circle Path Bonus: Up to +35 dB signal reinforcement along twilight corridor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpTacticalPilotMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.headline)
                    .foregroundStyle(.teal)
                Text("Tactical Pilot HUD & 11-Band HF Propagation Engine")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Engine: 11-Band Solar Raytrace")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15))
                    .foregroundStyle(.teal)
                    .cornerRadius(4)
            }
            Divider()

            HStack {
                Text("Target:")
                    .font(.caption.weight(.medium))
                Text("🇯🇵 Japan (JA) — Tokyo")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("Bearing: 068° SP | Dist: 7,620 km | MUF: 31.2 MHz")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.cyan)
            }

            // 11-Band Summary Matrix (Two Rows)
            VStack(spacing: 6) {
                // Lower Bands: 160m, 80m, 60m, 40m, 30m
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        Text("160m").font(.system(size: 8.5, weight: .bold))
                        Text("EXTINCT").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.red)
                        Text("D-Layer Cut").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("80m").font(.system(size: 8.5, weight: .bold))
                        Text("POOR").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.orange)
                        Text("15% Rel").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("60m").font(.system(size: 8.5, weight: .bold))
                        Text("FAIR").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.yellow)
                        Text("42% Rel").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("40m").font(.system(size: 8.5, weight: .bold))
                        Text("GOOD").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.green)
                        Text("+6 dB · 78%").font(.system(size: 7)).foregroundStyle(.green)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("30m").font(.system(size: 8.5, weight: .bold))
                        Text("OPEN").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.green)
                        Text("+10 dB · 85%").font(.system(size: 7)).foregroundStyle(.green)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                // Upper Bands: 20m, 17m, 15m, 12m, 10m, 6m
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        Text("20m").font(.system(size: 8.5, weight: .bold))
                        Text("STRONG").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.green)
                        Text("+18 dB · 96%").font(.system(size: 7, weight: .bold)).foregroundStyle(.green)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green, lineWidth: 1))

                    VStack(spacing: 2) {
                        Text("17m").font(.system(size: 8.5, weight: .bold))
                        Text("OPEN").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.green)
                        Text("+15 dB · 94%").font(.system(size: 7)).foregroundStyle(.green)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("15m").font(.system(size: 8.5, weight: .bold))
                        Text("OPTIMUM").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.cyan)
                        Text("+14 dB · 92%").font(.system(size: 7, weight: .bold)).foregroundStyle(.cyan)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("12m").font(.system(size: 8.5, weight: .bold))
                        Text("OPEN").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.green)
                        Text("+09 dB · 78%").font(.system(size: 7)).foregroundStyle(.green)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("10m").font(.system(size: 8.5, weight: .bold))
                        Text("FAIR").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.orange)
                        Text("+02 dB · 45%").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    VStack(spacing: 2) {
                        Text("6m").font(.system(size: 8.5, weight: .bold))
                        Text("ES WATCH").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.purple)
                        Text("Sporadic-E").font(.system(size: 7)).foregroundStyle(.purple)
                    }
                    .padding(4).frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            // 24H Timeline Sparkline
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("24H FORECAST TIMELINE (UTC)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Dynamic Peak: 14:00z · Best Band Now: 20m").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.yellow)
                }
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24) { hr in
                        let h: CGFloat = hr >= 10 && hr <= 17 ? CGFloat([20, 28, 34, 38, 42, 36, 30, 22][hr - 10]) : CGFloat.random(in: 6...14)
                        let isCurrent = hr == 11
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isCurrent ? Color.yellow : (h > 30 ? Color.green : (h > 18 ? Color.cyan : Color.white.opacity(0.15))))
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                            .overlay(isCurrent ? RoundedRectangle(cornerRadius: 1.5).stroke(Color.white, lineWidth: 1) : nil)
                    }
                }
                .frame(height: 44)
                .padding(4)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Text("Tactical Advice: Peak opening to East Asia active on 20m/15m until 18:30 UTC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpWeatherRadarMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cloud.bolt.rain.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Station Weather Safety & Antenna Protection Radar")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("🟢 Shack Safe")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
            }
            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Live Wind & Gusts", systemImage: "wind")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("14 km/h (Gusts: 22 km/h)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("Threshold: 65 km/h").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Label("Lightning Discharge", systemImage: "bolt.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Closest: 68 km SE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("Danger Zone: < 30 km").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(.green)
                Text("Safety Engine: Normal operating conditions. Towers, beams, and rotator safe to operate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

struct HelpSatelliteMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Text("Satellite Pass Radar & APRS High-Altitude Balloon")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("LEO Tracking Active")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundStyle(.cyan)
                    .cornerRadius(4)
            }
            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SATELLITE PASS: AO-91 (RadFxSat)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text("Elev: 44° (Max 68°)").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.blue)
                        Text("Az: 182° S").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text("Doppler: 435.250 MHz (+2.8 kHz)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text("APRS BALLOON: HAB-EP1").font(.system(size: 10, weight: .heavy)).foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text("Alt: 31,240 m").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                        Text("Ascent: +4.8 m/s").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text("Position: 35.68°N, 51.42°E (Tehran)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - Tactical Rover Mode Mockup

struct HelpRoverModeMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top HUD Status Bar
            HStack(spacing: 8) {
                Image(systemName: "shoeprints.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Tactical Rover Engine — Station Grid Projection")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("ACTIVE · 03:42:18")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: Capsule())
            }

            Divider()

            // Station Relocation Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOME STATION").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text("EP2AES · LM35ir")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PROJECTED ROVER GRID").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Text("LL46")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        Text("Kish Island (IOTA AS-166)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("DURATION").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text("Until End of UTC Day")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            // Stepped Compass & Geodesic Telemetry Grid
            HStack(spacing: 12) {
                // 4-Way Compass Stepper
                VStack(spacing: 4) {
                    Text("4-WAY COMPASS STEPPER").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    
                    Button(action: {}) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)

                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)

                        Text("LL46")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange)

                        Button(action: {}) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    }

                    Button(action: {}) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                // Telemetry Cards
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Distance & Bearing").font(.system(size: 9)).foregroundStyle(.secondary)
                            Text("1,048 km · 174° S (SSE)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Solar Times (Rover QTH)").font(.system(size: 9)).foregroundStyle(.secondary)
                            Text("Sunrise 02:44 · Sunset 14:18 UTC")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 10))
                        Text("Stamp MY_GRIDSQUARE = LL46 in outgoing QSOs")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Auto-Restores on Expiry")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(5)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - Spectrum Bandmap Mockup

struct HelpBandmapMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Text("Spectrum Bandmap & Waterfall Studio — 3-Pane Pro Layout")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 6) {
                    Text("20M (14 MHz)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.mint.opacity(0.15))
                        .foregroundStyle(.mint)
                        .cornerRadius(4)
                    Text("CAT: IC-7300 Live")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // 3-Pane Preview Simulation
            HStack(spacing: 8) {
                // Left: Vertical Frequency Ruler
                VStack(alignment: .leading, spacing: 4) {
                    Text("FREQUENCY RULER").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("14.074").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                            Text("FT8").font(.system(size: 8, weight: .heavy)).foregroundStyle(.orange)
                        }
                        Text("JA1ABC").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                        Text("VK2GR").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                        Divider()
                        HStack {
                            Text("14.025").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                            Text("CW DX").font(.system(size: 8, weight: .heavy)).foregroundStyle(.blue)
                        }
                        Text("K1TTT 599").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                    }
                    .padding(6)
                    .frame(width: 120, alignment: .leading)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }

                // Center: SDR Spectrum & Waterfall
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SDR SPECTRUM & WATERFALL").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                        Spacer()
                        Text("VFO A: 14.074.000").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                    }
                    
                    // Simulated Spectrum graph
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.6))
                            .frame(height: 70)
                        
                        // Signal peaks
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach([12, 18, 15, 25, 48, 55, 30, 16, 20, 38, 62, 28, 14, 22, 35, 18, 12, 24, 40, 15], id: \.self) { val in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(val > 45 ? Color.yellow : (val > 30 ? Color.green : Color.blue.opacity(0.6)))
                                    .frame(width: 6, height: CGFloat(val))
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // Waterfall Simulation bar
                    HStack(spacing: 0) {
                        ForEach([Color.purple, Color.blue, Color.cyan, Color.green, Color.yellow, Color.orange, Color.red], id: \.self) { c in
                            Rectangle().fill(c.opacity(0.7)).frame(height: 12)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // Right: DX Spot Hunter
                VStack(alignment: .leading, spacing: 4) {
                    Text("DX SPOT HUNTER").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("3Y0J").font(.system(size: 10, weight: .heavy)).foregroundStyle(.orange)
                            Spacer()
                            Text("ATNO").font(.system(size: 8, weight: .heavy)).foregroundStyle(.purple)
                        }
                        Text("14.024 CW · Bouvet").font(.system(size: 8.5)).foregroundStyle(.secondary)
                        HStack {
                            Text("DL7XYZ").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                            Spacer()
                            Text("+14 dB").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.green)
                        }
                        Text("14.074 FT8 · Berlin").font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(width: 120, alignment: .leading)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").foregroundStyle(.yellow).font(.caption)
                Text("Double-click any spot on the bandmap to QSY rig and auto-populate Quick Log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mint.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - QSL Card Label Studio Mockup

struct HelpQSLLabelStudioMockup: View {
    private func labelSlot(isSkipped: Bool) -> some View {
        VStack(spacing: 1) {
            if isSkipped {
                Text("SKIPPED")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.secondary)
                Image(systemName: "scissors")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                Text("TO: W1AW")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.primary)
                Text("14.074 FT8")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(.blue)
                Text("CONFIRMING")
                    .font(.system(size: 6))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 80, height: 32)
        .background(isSkipped ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isSkipped ? Color.secondary.opacity(0.3) : Color.accentColor.opacity(0.3), lineWidth: 0.8))
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "printer.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("QSL Card Label Studio & Interactive Peel-Off Matrix")
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("Avery 5160 (30 Labels/Sheet)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var sheetPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SHEET MATRIX PREVIEW (3 × 10)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                Spacer()
                Text("Click slot to skip used labels").font(.system(size: 8)).foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { col in
                            labelSlot(isSkipped: row == 0 && col < 2)
                        }
                    }
                }
            }
            .padding(6)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var calibrationView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STUDIO CALIBRATION").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("QSO Source:").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Recent Unconfirmed (24)").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
                HStack {
                    Text("Offset X / Y:").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("+0.5 mm / -0.2 mm").font(.system(size: 9, design: .monospaced)).foregroundStyle(.cyan)
                }
                HStack {
                    Text("Font & Layout:").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Standard 2-Way QSO").font(.system(size: 9, weight: .semibold)).foregroundStyle(.primary)
                }
                HStack {
                    Text("Manager Tag:").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("PSE QSL VIA BUREAU").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Label("Print Sheet", systemImage: "printer.fill")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(4)

                Label("Export PDF", systemImage: "doc.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView
            Divider()
            HStack(spacing: 12) {
                sheetPreview
                calibrationView
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - Club Membership Mockup

struct HelpClubMembershipMockup: View {
    private struct ClubStat: Identifiable {
        let id: String
        let count: String
        let color: Color
    }

    private let clubs: [ClubStat] = [
        ClubStat(id: "SKCC", count: "18,420", color: .orange),
        ClubStat(id: "CWops", count: "3,410", color: .blue),
        ClubStat(id: "FISTS", count: "15,200", color: .green),
        ClubStat(id: "LICW", count: "2,190", color: .teal),
        ClubStat(id: "30MDG", count: "4,850", color: .indigo)
    ]

    private func clubBadge(_ club: ClubStat) -> some View {
        VStack(spacing: 2) {
            Text(club.id).font(.system(size: 10, weight: .heavy)).foregroundStyle(club.color)
            Text(club.count).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .background(club.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3.sequence.fill")
                .font(.headline)
                .foregroundStyle(.purple)
            Text("International Club Memberships & Roster Auto-Detection")
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("6 Clubs Synced (38,400 Members)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var badgesRow: some View {
        HStack(spacing: 8) {
            ForEach(clubs) { club in
                clubBadge(club)
            }
        }
    }

    @ViewBuilder
    private var lookupCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOOKUP CALLSIGN:").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                Text("K6VVA")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("Rick · California, USA").font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("DETECTED CLUB AFFILIATIONS:").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Text("CWops #1428").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2).background(Color.blue.opacity(0.15)).cornerRadius(3)
                    Text("SKCC #9821S (Senator)").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange.opacity(0.15)).cornerRadius(3)
                    Text("FISTS #11204").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2).background(Color.green.opacity(0.15)).cornerRadius(3)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.purple)
                Text("Insert Exchange").font(.system(size: 9, weight: .bold)).foregroundStyle(.purple)
            }
            .padding(6)
            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView
            Divider()
            badgesRow
            lookupCard
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - Club Log Live Spots Mockup

struct HelpClubLogSpotsMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Club Log Live Activity Stream & Band Opportunity Engine")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Live Stream Connected")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            }

            Divider()

            // Top Recommended Band Card
            HStack(spacing: 12) {
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("TOP RECOMMENDED BAND:")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text("15M (21 MHz)")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    Text("84 Active Spots · 14 NEEDED DXCC ENTITIES · Dominant Mode: FT8")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("SCORE").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    Text("133.0").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(.green)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.25), lineWidth: 1))

            // Sample Live Spots Table
            VStack(spacing: 4) {
                HStack {
                    Text("CALLSIGN").font(.system(size: 8, weight: .bold)).frame(width: 70, alignment: .leading)
                    Text("FREQ & MODE").font(.system(size: 8, weight: .bold)).frame(width: 90, alignment: .leading)
                    Text("DXCC ENTITY").font(.system(size: 8, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                    Text("STATUS").font(.system(size: 8, weight: .bold)).frame(width: 80, alignment: .trailing)
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)

                VStack(spacing: 3) {
                    HStack {
                        Text("3Y0J").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(.orange).frame(width: 70, alignment: .leading)
                        Text("14.024 CW").font(.system(size: 9, design: .monospaced)).frame(width: 90, alignment: .leading)
                        Text("Bouvet Island").font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("ATNO NEW").font(.system(size: 8, weight: .heavy)).foregroundStyle(.purple).frame(width: 80, alignment: .trailing)
                    }
                    .padding(4).background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    HStack {
                        Text("VK9DX").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(.cyan).frame(width: 70, alignment: .leading)
                        Text("21.074 FT8").font(.system(size: 9, design: .monospaced)).frame(width: 90, alignment: .leading)
                        Text("Norfolk Island").font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("NEEDED BAND").font(.system(size: 8, weight: .bold)).foregroundStyle(.green).frame(width: 80, alignment: .trailing)
                    }
                    .padding(4).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }
}

// MARK: - Network Transceiver Emulator (NTE) Mockup

struct HelpNTEMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mockupTopBar
            Divider()
            frontPanelOled
            cardsGrid
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }

    private var mockupTopBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("Network Transceiver Emulator (NTE) — Node Emulation")
                .font(.subheadline.weight(.bold))
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("ONLINE · 3 Sockets")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.green.opacity(0.15), in: Capsule())

            HStack(spacing: 4) {
                Image(systemName: "link.circle.fill").font(.caption2)
                Text("Connect YAAM LAN")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.purple.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.purple)
        }
    }

    private var frontPanelOled: some View {
        VStack(spacing: 8) {
            oledHeader
            Divider().background(Color.white.opacity(0.2))
            oledMainFreq
            oledMeterAndPresets
        }
        .padding(10)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
    }

    private var oledHeader: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("RX READY")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.green)
            }
            Spacer()
            Text("IC-7300MK2 LAN EMULATOR")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.cyan)
            Spacer()
            HStack(spacing: 6) {
                Text("VFO A").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                Text("FIL 1 (3.0k)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Text("AGC FAST").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    private var oledMainFreq: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("20M")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                Text("BAND").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
            }

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("14.074.000")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(.green)
                    .shadow(color: Color.green.opacity(0.5), radius: 6)
                Text("MHz")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("USB-D")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.yellow)
                Text("DATA-1").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
        }
    }

    private var oledMeterAndPresets: some View {
        VStack(spacing: 4) {
            HStack {
                Text("SIG").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.72)
                    }
                }
                .frame(height: 6)
                Text("S9+10dB").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("PRESETS:").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    bandPresetChip(label: "40m", active: false)
                    bandPresetChip(label: "20m", active: true)
                    bandPresetChip(label: "15m", active: false)
                    bandPresetChip(label: "10m", active: false)
                }
                Spacer()
                HStack(spacing: 3) {
                    stepChip(label: "-10k")
                    stepChip(label: "+10k")
                    Text("PTT")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func bandPresetChip(label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(active ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(active ? .white : .secondary)
    }

    private func stepChip(label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(2)
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
    }

    private var cardsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            featureCard(
                icon: "network",
                title: "Protocol Server Endpoints",
                color: .blue,
                lines: [
                    "UDP 50001: Icom Control & Discovery",
                    "UDP 50002: CI-V Registers Streaming",
                    "UDP 50003: 48 kHz LPCM16 Audio",
                    "TCP 4532: Hamlib rigctld (WSJT-X/JTDX)"
                ]
            )

            featureCard(
                icon: "waveform.path",
                title: "Channel Physics Simulation",
                color: .orange,
                lines: [
                    "AWGN SNR: Calibrated -30 dB to +30 dB",
                    "Multipath Fading: Rayleigh & Rician",
                    "Doppler: ±500 Hz shift, ±100 Hz/min drift",
                    "Atmospheric Impulses: Poisson QRN bursts"
                ]
            )

            featureCard(
                icon: "waveform.badge.magnifyingglass",
                title: "Synthetic Signal Studio",
                color: .green,
                lines: [
                    "FT8 & FT4: CPFSK UTC-slot aligned",
                    "Pileup Generator: 5-8 synthetic callers",
                    "CW Beacon: 20 WPM raised-cosine (5ms)",
                    "Custom Call Injection: Callsign / Grid / SNR"
                ]
            )

            featureCard(
                icon: "chart.bar.xaxis",
                title: "Automated DSP Benchmarks",
                color: .purple,
                lines: [
                    "Sensitivity Sweep: +6 dB down to -24 dB",
                    "Decode Floor: Calculated via FT8Codec",
                    "Loopback Test: 1-Click YAAM client link",
                    "Report Export: Markdown & JSON logs"
                ]
            )
        }
    }

    private func featureCard(icon: String, title: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.primary)
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 3) {
                        Text("•").font(.system(size: 8)).foregroundStyle(color)
                        Text(line).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Multi-Rig FT8 Cluster Mockup

struct HelpMultiRigMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mockupTopBar
            Divider()
            mockupSlotsRow
            Divider()
            mockupOpportunityRadar
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 6)
    }

    private var mockupTopBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.split.3x1.fill")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("Multi-Rig FT8 Cluster Console (SO3R)")
                .font(.subheadline.weight(.bold))
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text("INTERLOCK: STRICT LOCKOUT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())

            HStack(spacing: 4) {
                Image(systemName: "clock.fill").font(.caption2)
                Text("12:04:15 UTC · :15 SLOT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.blue)
        }
    }

    private var mockupSlotsRow: some View {
        HStack(spacing: 8) {
            slotCard(name: "Rig 1", band: "20m (14.074)", driver: "Icom LAN", status: "RX DECODE", statusColor: .green, caller: "JA1ABC -08", country: "Japan")
            slotCard(name: "Rig 2", band: "40m (7.074)", driver: "Lab599 TX-500", status: "TX ARMED", statusColor: .orange, caller: "DL1XYZ -12", country: "Germany")
            slotCard(name: "Rig 3", band: "10m (28.074)", driver: "NTE Emulator", status: "MONITORING", statusColor: .cyan, caller: "W6XYZ DM13", country: "USA")
        }
    }

    private func slotCard(name: String, band: String, driver: String, status: String, statusColor: Color, caller: String, country: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.caption.weight(.bold))
                Spacer()
                Text(band).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                Text(driver).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text(status)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            // Mini waterfall mockup
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [.black, .blue.opacity(0.6), .purple.opacity(0.4), .orange.opacity(0.3), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 38)
                .overlay(
                    HStack {
                        Rectangle().fill(Color.red.opacity(0.8)).frame(width: 3)
                        Spacer()
                    }
                    .padding(.leading, 18)
                )
            HStack {
                Text(caller).font(.system(size: 9, weight: .bold, design: .monospaced))
                Spacer()
                Text(country).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var mockupOpportunityRadar: some View {
        HStack(spacing: 8) {
            Image(systemName: "radar")
                .foregroundStyle(.pink)
                .font(.caption)
            Text("Cross-Band DX Radar:")
                .font(.caption.weight(.bold))
            Text("JA1ABC (20m) · Tokyo, Japan")
                .font(.system(size: 10, design: .monospaced))
            Text("NEW DXCC")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.pink.opacity(0.2), in: Capsule())
                .foregroundStyle(.pink)
            Spacer()
            Text("Answer on Rig 1")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

