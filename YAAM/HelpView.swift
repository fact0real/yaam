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
                        question: "How do I export ADIF from SDR-Control for Mac?",
                        answer: "In SDR-Control for Mac:\n1. Open the Logbook window.\n2. Click the 'Export' button or go to Menu -> Logbook -> Export ADIF.\n3. Choose your destination folder to save the .adi file, then select it in this app."
                    )
                    
                    FAQItem(
                        question: "How do I export ADIF from MacLoggerDX?",
                        answer: "In MacLoggerDX:\n1. Go to File -> Export -> ADIF...\n2. Select your desired date range or export all records to a .adi file."
                    )
                    
                    FAQItem(
                        question: "Can I clean up ADIF logs without converting to CSV?",
                        answer: "Yes! Uncheck 'Convert Output to CSV / Excel'. The application will process, clean, and filter your log while saving the result in clean ADIF (.adi) format without trailing spaces."
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
