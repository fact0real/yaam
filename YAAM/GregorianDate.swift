//
//  GregorianDate.swift
//  YAAM
//
//  Dates and times that are kept in the log or handed to other programs (ADIF QSO_DATE and
//  TIME_ON, cluster lines, calendar files, web queries) are written and read in the Gregorian
//  calendar with ASCII digits, whatever calendar and digits the Mac is set to.
//  Dates that are only shown on screen keep following the Mac's settings and do not use this.
//

import Foundation

nonisolated enum GregorianDate {
    /// A formatter for `format` that writes and reads the Gregorian calendar with ASCII digits.
    /// Without `timeZone` it keeps the formatter's own default, the Mac's time zone.
    static func formatter(_ format: String, timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if let timeZone { formatter.timeZone = timeZone }
        formatter.dateFormat = format
        return formatter
    }

    /// The Gregorian calendar in the Mac's time zone, for date arithmetic whose result is compared
    /// with, or stored next to, Gregorian dates (`Calendar.current` follows the Mac's calendar).
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }
}
