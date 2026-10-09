//
//  MacCalendarService.swift
//  YAAM
//
//  Integration service for scheduling Ham Radio Contest & DX sessions into macOS Calendar.
//

import Foundation
import AppKit

final class MacCalendarService {
    static let shared = MacCalendarService()
    private init() {}

    /// Exports a single day solar forecast session to macOS Calendar.
    func addDayToCalendar(point: SolarForecastPoint, completion: ((Bool, String) -> Void)? = nil) {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: point.date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)

        let title = "📡 Ham Radio DX: \(point.shortDayName), \(point.fullDateFormatted) (SFI \(point.solarFlux), Kp \(point.kpIndex))"
        let description = """
        NOAA 27-Day Solar Forecast & HF Propagation Outlook
        Rating: \(point.propagationCondition.rating)
        Solar Flux Index (SFI): \(point.solarFlux)
        Kp-Index: \(point.kpIndex) (\(point.geomagneticState.name))
        A-Index (Ap): \(point.aIndex)
        Recommended Open Bands: \(point.propagationCondition.bestBands)

        Scheduled via YAAM (Yet Another ADIF Manager) DX Advisor.
        """

        saveAndOpenICS(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: true,
            description: description,
            location: "Ham Radio Shack / HF Bands",
            completion: completion
        )
    }

    /// Exports a multi-day prime contest / DX window to macOS Calendar.
    func addWindowToCalendar(window: PrimeContestWindow, completion: ((Bool, String) -> Void)? = nil) {
        guard let first = window.points.first, let last = window.points.last else { return }
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: first.date)
        let lastDayStart = calendar.startOfDay(for: last.date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDayStart) ?? lastDayStart.addingTimeInterval(86400)

        let title = "🏆 Ham Radio Contest & DX Prime Window (\(window.dateRangeString))"
        let description = """
        ★ Optimal HF Contest & DX Operating Window ★
        Duration: \(window.daysCount) Days (\(window.dateRangeString))
        Condition Rating: \(window.rating) (Propagation Score: \(window.score)/100)
        Average Solar Flux (SFI): \(window.averageSFI)
        Maximum Kp-Index: \(window.maxKp) (\(window.maxKp <= 2 ? "Quiet / Unperturbed Ionosphere" : "Moderate"))
        Average A-Index (Ap): \(window.averageAp)
        Prime HF Bands: \(window.targetBands)

        Forecast by YAAM DX Advisor / NOAA SWPC Space Weather.
        """

        saveAndOpenICS(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: true,
            description: description,
            location: "Amateur Radio Shack / HF Contest Bands",
            completion: completion
        )
    }

    private func saveAndOpenICS(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        description: String,
        location: String,
        completion: ((Bool, String) -> Void)?
    ) {
        let dateFormatter = GregorianDate.formatter(
            isAllDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss'Z'",
            timeZone: TimeZone(secondsFromGMT: 0)
        )

        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)
        let nowStr = dateFormatter.string(from: Date())
        let uid = UUID().uuidString

        let cleanDesc = description
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")

        let icsContent = """
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//YAAM//Ham Radio DX Advisor//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:\(uid)@yaam.app
DTSTAMP:\(nowStr)
\(isAllDay ? "DTSTART;VALUE=DATE:\(startStr)" : "DTSTART:\(startStr)")
\(isAllDay ? "DTEND;VALUE=DATE:\(endStr)" : "DTEND:\(endStr)")
SUMMARY:\(title)
DESCRIPTION:\(cleanDesc)
LOCATION:\(location)
STATUS:CONFIRMED
BEGIN:VALARM
TRIGGER:-P1D
ACTION:DISPLAY
DESCRIPTION:Reminder: Upcoming Ham Radio Contest & DX Session
END:VALARM
BEGIN:VALARM
TRIGGER:-PT1H
ACTION:DISPLAY
DESCRIPTION:Reminder: Ham Radio Contest & DX Session starting soon
END:VALARM
END:VEVENT
END:VCALENDAR
"""

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("YAAM_Radio_Session_\(UUID().uuidString.prefix(8)).ics")

        do {
            try icsContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let success = NSWorkspace.shared.open(fileURL)
            DispatchQueue.main.async {
                completion?(success, success ? "Event created in macOS Calendar" : "Could not open Calendar app")
            }
        } catch {
            DispatchQueue.main.async {
                completion?(false, error.localizedDescription)
            }
        }
    }
}
