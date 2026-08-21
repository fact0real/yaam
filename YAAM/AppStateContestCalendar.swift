//
//  AppStateContestCalendar.swift
//  YAAM
//

import Foundation

extension AppState {
    private static let contestCalendarCacheKey = "contestCalendarCache.v1"

    func loadContestCalendarCache() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.contestCalendarCacheKey),
            let cache = try? JSONDecoder().decode(ContestCalendarCache.self, from: data)
        else {
            contestCalendarStatus = "Calendar not loaded yet"
            return
        }
        contestCalendarEntries = cache.entries
        contestCalendarLastUpdated = cache.updatedAt
        contestCalendarStatus = "Showing cached WA7BNM calendar"
    }

    func fetchContestCalendar(force: Bool = false) {
        guard !isFetchingContestCalendar else { return }
        if !force,
           let lastUpdated = contestCalendarLastUpdated,
           Date().timeIntervalSince(lastUpdated) < 60 * 60 * 6,
           !contestCalendarEntries.isEmpty {
            return
        }

        isFetchingContestCalendar = true
        contestCalendarStatus = "Refreshing WA7BNM contest calendar..."
        var request = URLRequest(url: ContestCalendarService.weeklyURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("YAAM/\(currentVersion) (+https://github.com/factoreal/YAAM)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let entries = data.flatMap { String(data: $0, encoding: .utf8) }.map(ContestCalendarService.parse) ?? []
            let responseOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingContestCalendar = false
                guard error == nil, responseOK, !entries.isEmpty else {
                    self.contestCalendarStatus = self.contestCalendarEntries.isEmpty
                        ? "Unable to load the calendar. Check the official WA7BNM page."
                        : "Using the last saved calendar; refresh did not complete."
                    return
                }

                let now = Date()
                self.contestCalendarEntries = entries
                self.contestCalendarLastUpdated = now
                self.contestCalendarStatus = "Loaded \(entries.count) contests from WA7BNM"
                if let encoded = try? JSONEncoder().encode(ContestCalendarCache(entries: entries, updatedAt: now)) {
                    UserDefaults.standard.set(encoded, forKey: Self.contestCalendarCacheKey)
                }
            }
        }.resume()
    }
}
