import Foundation
import CoreGraphics

/// Serial, incremental pixel conversion. Only new rows are colorized; snapshots remain immutable.
actor FT8WaterfallRasterizer {
    private var converted: [[UInt32]] = []
    private var lastRow: [Float]?
    private var lastRevision: Int?
    private var width = 0
    private(set) var mappedRowCount = 0

    func image(rows: [[Float]], revision: Int) -> CGImage? {
        guard let row = rows.last, !row.isEmpty, rows.allSatisfy({ $0.count == row.count }) else {
            converted = []; lastRow = nil; lastRevision = revision; width = 0
            return nil
        }
        let appended = lastRevision.map { revision == $0 + 1 } == true
            && width == row.count && rows.count >= 2
            && rows[rows.count - 2] == lastRow
            && (rows.count == converted.count + 1 || rows.count == converted.count)
        if appended {
            if rows.count == converted.count { converted.removeFirst() }
            converted.append(Self.colorize(row)); mappedRowCount += 1
        } else {
            converted = rows.map(Self.colorize); mappedRowCount += rows.count
        }
        width = row.count; lastRow = row; lastRevision = revision
        var bytes = Data(capacity: width * rows.count * 4)
        for row in converted.reversed() {
            row.withUnsafeBytes { bytes.append(contentsOf: $0) }
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private nonisolated static func colorize(_ row: [Float]) -> [UInt32] {
        row.map { value in
            let finite = value.isFinite ? value : 0
            return palette[Int(min(255, max(0, finite * 255)))]
        }
    }
    private nonisolated static let palette = (0...255).map { waterfallRGB32(Float($0) / 255) }
    private nonisolated static func waterfallRGB32(_ rawValue: Float) -> UInt32 {
        let v = min(1.0, max(0.0, rawValue))
        let r: UInt8
        let g: UInt8
        let b: UInt8

        if v < 0.10 {
            // Inky space black to deep midnight navy (noise floor)
            let t = v / 0.10
            r = UInt8(1 * t)
            g = UInt8(2 * t)
            b = UInt8(10 * t)
        } else if v < 0.25 {
            // Faint noise: Deep navy to rich cobalt blue
            let t = (v - 0.10) / 0.15
            r = UInt8(1 + t * 5)
            g = UInt8(2 + t * 35)
            b = UInt8(10 + t * 135)
        } else if v < 0.45 {
            // Weak FT8 signal tones: Cobalt blue to electric glowing cyan
            let t = (v - 0.25) / 0.20
            r = UInt8(6 + t * 14)
            g = UInt8(37 + t * 185)
            b = UInt8(145 + t * 110)
        } else if v < 0.65 {
            // Solid FT8 tones: Electric cyan to brilliant neon emerald green
            let t = (v - 0.45) / 0.20
            r = UInt8(20 + t * 65)
            g = UInt8(222 + t * 33)
            b = UInt8(255 - t * 215)
        } else if v < 0.85 {
            // Strong signals: Neon green to bright sun yellow and amber
            let t = (v - 0.65) / 0.20
            r = UInt8(85 + t * 170)
            g = UInt8(255 - t * 45)
            b = UInt8(40 - t * 30)
        } else {
            // S9+ local signals: Flaming orange to white-hot peak
            let t = (v - 0.85) / 0.15
            r = 255
            let gVal = 210 * (1.0 - t * 0.4)
            g = UInt8(max(0, min(255, gVal)))
            b = UInt8(10 + t * 235)
        }

        return (0xFF << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
    }

}
