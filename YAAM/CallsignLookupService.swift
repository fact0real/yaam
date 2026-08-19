//
//  CallsignLookupService.swift
//  YAAM
//

import Foundation

actor CallsignLookupService {
    private struct CacheEntry {
        let savedAt: Date
        let result: CallsignLookupResult
    }

    private var cache: [String: CacheEntry] = [:]
    private var qrzSessionKey = ""
    private var hamqthSessionKey = ""
    private let cacheLifetime: TimeInterval = 24 * 60 * 60
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    func lookup(
        callsign rawCallsign: String,
        credentials: CallsignLookupCredentials,
        localFallback: CallsignLookupResult
    ) async -> CallsignLookupResult {
        let callsign = rawCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !callsign.isEmpty else { return localFallback }

        if let cached = cache[callsign], Date().timeIntervalSince(cached.savedAt) < cacheLifetime {
            var result = cached.result
            result.mergeMissing(from: localFallback)
            return result
        }

        async let qrz = lookupQRZ(callsign: callsign, credentials: credentials)
        async let hamqth = lookupHAMQTH(callsign: callsign, credentials: credentials)
        let (qrzResult, hamqthResult) = await (qrz, hamqth)

        var merged = qrzResult ?? CallsignLookupResult(callsign: callsign)
        if let hamqthResult { merged.mergeMissing(from: hamqthResult) }
        merged.mergeMissing(from: localFallback)

        if merged.hasUsefulData {
            cache[callsign] = CacheEntry(savedAt: Date(), result: merged)
        } else if merged.message.isEmpty {
            merged.message = "No callbook details were returned. You can still log the QSO manually."
        }
        pruneCache()
        return merged
    }

    func clearCache() {
        cache.removeAll()
        qrzSessionKey = ""
        hamqthSessionKey = ""
    }

    private func lookupQRZ(callsign: String, credentials: CallsignLookupCredentials) async -> CallsignLookupResult? {
        let username = credentials.qrzUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !credentials.qrzPassword.isEmpty else { return nil }

        if qrzSessionKey.isEmpty {
            qrzSessionKey = await createQRZSession(credentials: credentials) ?? ""
        }
        guard !qrzSessionKey.isEmpty else {
            return CallsignLookupResult(callsign: callsign, message: "QRZ XML login was unavailable; HAMQTH or local history may still provide details.")
        }

        do {
            var xml = try await requestXML(
                endpoint: "https://xmldata.qrz.com/xml/current/",
                form: ["s": qrzSessionKey, "callsign": callsign]
            )
            if xmlValue("Callsign", in: xml) == nil, xml.localizedCaseInsensitiveContains("session") {
                qrzSessionKey = await createQRZSession(credentials: credentials) ?? ""
                guard !qrzSessionKey.isEmpty else { return nil }
                xml = try await requestXML(
                    endpoint: "https://xmldata.qrz.com/xml/current/",
                    form: ["s": qrzSessionKey, "callsign": callsign]
                )
            }

            guard xml.range(of: "<Callsign", options: .caseInsensitive) != nil else { return nil }
            let firstName = xmlValue("fname", in: xml) ?? ""
            let lastName = xmlValue("name", in: xml) ?? ""
            let formattedName = xmlValue("name_fmt", in: xml) ?? [firstName, lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return CallsignLookupResult(
                callsign: callsign,
                name: formattedName,
                qth: xmlValue("addr2", in: xml) ?? "",
                grid: xmlValue("grid", in: xml) ?? "",
                country: xmlValue("land", in: xml) ?? xmlValue("country", in: xml) ?? "",
                dxcc: xmlValue("dxcc", in: xml) ?? "",
                cqZone: xmlValue("cqzone", in: xml) ?? "",
                ituZone: xmlValue("ituzone", in: xml) ?? "",
                email: xmlValue("email", in: xml) ?? "",
                latitude: xmlValue("lat", in: xml) ?? "",
                longitude: xmlValue("lon", in: xml) ?? "",
                sources: ["QRZ XML"]
            )
        } catch {
            return nil
        }
    }

    private func createQRZSession(credentials: CallsignLookupCredentials) async -> String? {
        do {
            let xml = try await requestXML(
                endpoint: "https://xmldata.qrz.com/xml/current/",
                form: [
                    "username": credentials.qrzUsername,
                    "password": credentials.qrzPassword,
                    "agent": credentials.agent
                ]
            )
            return xmlValue("Key", in: xml)
        } catch {
            return nil
        }
    }

    private func lookupHAMQTH(callsign: String, credentials: CallsignLookupCredentials) async -> CallsignLookupResult? {
        let username = credentials.hamqthUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !credentials.hamqthPassword.isEmpty else { return nil }

        if hamqthSessionKey.isEmpty {
            hamqthSessionKey = await createHAMQTHSession(credentials: credentials) ?? ""
        }
        guard !hamqthSessionKey.isEmpty else { return nil }

        do {
            var xml = try await requestXML(
                endpoint: "https://www.hamqth.com/xml.php",
                form: ["id": hamqthSessionKey, "callsign": callsign, "prg": credentials.agent]
            )
            if xmlValue("error", in: xml) != nil {
                hamqthSessionKey = await createHAMQTHSession(credentials: credentials) ?? ""
                guard !hamqthSessionKey.isEmpty else { return nil }
                xml = try await requestXML(
                    endpoint: "https://www.hamqth.com/xml.php",
                    form: ["id": hamqthSessionKey, "callsign": callsign, "prg": credentials.agent]
                )
            }
            guard xmlValue("callsign", in: xml) != nil || xml.range(of: "<search", options: .caseInsensitive) != nil else { return nil }

            let name = xmlValue("nick", in: xml) ?? xmlValue("adr_name", in: xml) ?? xmlValue("name", in: xml) ?? ""
            return CallsignLookupResult(
                callsign: callsign,
                name: name,
                qth: xmlValue("qth", in: xml) ?? xmlValue("adr_city", in: xml) ?? "",
                grid: xmlValue("grid", in: xml) ?? "",
                country: xmlValue("country", in: xml) ?? "",
                dxcc: xmlValue("adif", in: xml) ?? xmlValue("dxcc", in: xml) ?? "",
                cqZone: xmlValue("cq", in: xml) ?? "",
                ituZone: xmlValue("itu", in: xml) ?? "",
                email: xmlValue("email", in: xml) ?? "",
                latitude: xmlValue("latitude", in: xml) ?? "",
                longitude: xmlValue("longitude", in: xml) ?? "",
                sources: ["HAMQTH"]
            )
        } catch {
            return nil
        }
    }

    private func createHAMQTHSession(credentials: CallsignLookupCredentials) async -> String? {
        do {
            let xml = try await requestXML(
                endpoint: "https://www.hamqth.com/xml.php",
                form: [
                    "u": credentials.hamqthUsername,
                    "p": credentials.hamqthPassword,
                    "prg": credentials.agent
                ]
            )
            return xmlValue("session_id", in: xml)
        } catch {
            return nil
        }
    }

    private func requestXML(endpoint: String, form: [String: String]) async throws -> String {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml,text/xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(form)

        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<400).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func formBody(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func xmlValue(_ tag: String, in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<\\s*\(NSRegularExpression.escapedPattern(for: tag))\\b[^>]*>(.*?)<\\s*/\\s*\(NSRegularExpression.escapedPattern(for: tag))\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let valueRange = Range(match.range(at: 1), in: xml) else { return nil }
        let value = String(xml[valueRange])
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func pruneCache() {
        guard cache.count > 500 else { return }
        let cutoff = Date().addingTimeInterval(-cacheLifetime)
        cache = cache.filter { $0.value.savedAt >= cutoff }
        if cache.count > 500 {
            let keep = cache.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(500)
            cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
