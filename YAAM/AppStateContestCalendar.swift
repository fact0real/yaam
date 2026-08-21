//
//  AppStateContestCalendar.swift
//  YAAM
//

import Foundation
import UserNotifications

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
                self.scheduleContestInterestNotifications(entries)
                if let encoded = try? JSONEncoder().encode(ContestCalendarCache(entries: entries, updatedAt: now)) {
                    UserDefaults.standard.set(encoded, forKey: Self.contestCalendarCacheKey)
                }
            }
        }.resume()
    }

    private func scheduleContestInterestNotifications(_ entries: [ContestCalendarEntry]) {
        guard UserDefaults.standard.bool(forKey: "contestInterestNotifications") else { return }
        let tokens = (UserDefaults.standard.string(forKey: "contestPreferredModes") ?? "") + "," +
            (UserDefaults.standard.string(forKey: "contestInterestKeywords") ?? "")
        let interests = tokens.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !interests.isEmpty else { return }

        let delivered = Set(UserDefaults.standard.stringArray(forKey: "contestInterestNotificationIDs") ?? [])
        let matches = entries.filter { entry in
            let context = "\(entry.title) \(entry.modes) \(entry.bands) \(entry.geographicFocus)".uppercased()
            return !delivered.contains(entry.id) && interests.contains(where: context.contains)
        }
        guard !matches.isEmpty else { return }

        for entry in matches.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = "Contest match: \(entry.title)"
            content.body = entry.utcWindow
            content.sound = .default
            let request = UNNotificationRequest(identifier: "contest.\(entry.id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        let rememberedIDs = Array(Array(delivered.union(matches.map(\.id))).suffix(120))
        UserDefaults.standard.set(rememberedIDs, forKey: "contestInterestNotificationIDs")
    }
}
