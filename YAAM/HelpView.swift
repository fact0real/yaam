//
//  HelpView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Title
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("User Guide & FAQ")
                        .font(.title2)
                        .bold()
                    Text("ADIF Log Processor & Converter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Interactive Accordion FAQ List
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FAQItem(
                        question: "How do I convert ADIF files to CSV / Excel?",
                        answer: "1. Click 'ADIF File' to pick an input (.adi or .adif) file.\n2. Ensure 'Convert Output to CSV / Excel' is checked.\n3. Click 'Process' to generate the file, then click 'Open Output File' to view it in Microsoft Excel."
                    )
                    
                    FAQItem(
                        question: "How does the UTC Contest Filter work?",
                        answer: "Enable 'UTC Time Filter (Contest Mode)' and enter:\n- Start Date & End Date (YYYYMMDD).\n- Start Time & End Time (HHMMSS).\nThis allows filtering logs across multi-day contests or overnight UTC boundaries (e.g., 20260727 190000 to 20260728 020000)."
                    )
                    
                    FAQItem(
                        question: "How do I find the ADIF log file in WSJT-X?",
                        answer: "In WSJT-X on macOS:\n1. Open WSJT-X and go to the top menu: File -> Open log directory.\n2. Locate the file named 'wsjtx_log.adi'.\n\nAlternatively, navigate in Finder to:\n~/.local/share/WSJT-X/wsjtx_log.adi"
                    )
                    
                    FAQItem(
                        question: "How do I sync an external ADIF log?",
                        answer: "Open Settings -> External ADIF, choose a live .adi/.adif file, then click Sync Now or enable automatic sync. This works with WSJT-X, JTDX, GridTracker, Log4OM, N1MM, MacLoggerDX, SDR-Control ADIF exports, and other apps that write ADIF."
                    )
                    
                    FAQItem(
                        question: "How do I export ADIF from MacLoggerDX?",
                        answer: "In MacLoggerDX:\n1. Go to File -> Export -> ADIF...\n2. Select your desired date range or export all records to a .adi file."
                    )
                    
                    FAQItem(
                        question: "Can I clean up ADIF logs without converting to CSV?",
                        answer: "Yes! Uncheck 'Convert Output to CSV / Excel'. The application will process, clean, and filter your log while saving the result in clean ADIF (.adi) format without trailing spaces."
                    )

                    FAQItem(
                        question: "How do I use DX Advisor?",
                        answer: "Open DX Advisor to see live propagation, VOACAP-style path suggestions, band opportunities, unconfirmed DXCC targets, callsigns with no confirmed QSOs, bulk QSL email tools, and email history. Enter your Grid Locator, radio power, antenna and height in Settings -> General for better recommendations."
                    )

                    FAQItem(
                        question: "What does the VOACAP-style planner calculate?",
                        answer: "YAAM estimates path quality from your Grid Locator to worked countries in your log. It combines distance, bearing, current UTC hour, target day/night window, HamQSL propagation conditions, station power, antenna details, and whether a country still needs confirmation. It is a practical planner, not the original VOACAP engine."
                    )

                    FAQItem(
                        question: "How do I compare multiple callsigns in Global Leaderboard?",
                        answer: "Open Global Leaderboard and enter at least three callsigns separated by commas or spaces, then click Compare. Use Random 3 to automatically pick three comparison callsigns. YAAM shows your station against each rival for QSO rank, band rank, and DXCC rank."
                    )

                    FAQItem(
                        question: "How do I send bulk confirmation request emails?",
                        answer: "First enrich your log so EMAIL fields are available. Then open DX Advisor and use Bulk QSL Email. Choose a template and click Send Bulk. YAAM sends to callsigns that have no confirmed QSOs and have an email address, with a safety limit of 25 emails per run."
                    )

                    FAQItem(
                        question: "How do I configure SMTP for email sending?",
                        answer: "Open SMTP settings and enter your email address, SMTP host, port, and password. For Gmail or Google Workspace, use an App Password rather than your normal account password. Bulk email uses the same SMTP settings as single-recipient email."
                    )
                }
                .padding(.trailing, 8)
            }
        }
        .padding(20)
    }
}

// MARK: - FAQ Accordion Item Component (With Focus Ring Fix)
struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(question)
                .font(.headline)
        }
        .buttonStyle(.plain) // Fixes blue focus border on macOS
        .focusEffectDisabled() // Ensures no outline frame on hover/focus
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
