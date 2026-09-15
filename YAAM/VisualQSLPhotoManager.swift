//
//  VisualQSLPhotoManager.swift
//  YAAM
//
//  Asynchronous Image Fetcher & In-Memory Cache for QRZ & HamQTH QSL Card & Shack Photos.
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class VisualQSLPhotoManager: ObservableObject {
    static let shared = VisualQSLPhotoManager()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB max memory cache
    }

    func cachedImage(for urlString: String) -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        return cache.object(forKey: url as NSURL)
    }

    func loadImage(from urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        let nsURL = url as NSURL

        if let cached = cache.object(forKey: nsURL) {
            return cached
        }

        if let existingTask = inFlightTasks[urlString] {
            return await existingTask.value
        }

        let task = Task<NSImage?, Never> { @MainActor in
            defer { self.inFlightTasks.removeValue(forKey: urlString) }
            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                request.setValue("YAAM-macOS/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                guard let image = NSImage(data: data) else { return nil }
                self.cache.setObject(image, forKey: nsURL, cost: data.count)
                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[urlString] = task
        return await task.value
    }
}

// MARK: - SwiftUI Thumbnail Component

struct VisualQSLThumbnailView: View {
    let urlString: String
    let callsign: String
    var size: CGFloat = 46
    var onTap: (() -> Void)? = nil

    @State private var image: NSImage? = nil
    @State private var isLoading = false
    @State private var isHovered = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .frame(width: size, height: size)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary.opacity(0.6))
                }

                // Hover / Action Indicator
                if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: size, height: size)

                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isHovered ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task(id: urlString) {
            guard !urlString.isEmpty else {
                image = nil
                return
            }
            if let cached = VisualQSLPhotoManager.shared.cachedImage(for: urlString) {
                image = cached
                return
            }
            isLoading = true
            image = await VisualQSLPhotoManager.shared.loadImage(from: urlString)
            isLoading = false
        }
        .help("Click to inspect \(callsign)'s QSL card & shack photo")
    }
}
