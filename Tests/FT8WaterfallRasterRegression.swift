import Foundation
import CoreGraphics
@main struct FT8WaterfallRasterRegression {
    static func main() async {
        let renderer = FT8WaterfallRasterizer()
        var rows = (0..<400).map { n in (0..<512).map { Float(($0 + n) % 256) / 255 } }
        let start = Date()
        _ = await renderer.image(rows: rows, revision: 0)
        for n in 1...100 {
            rows.removeFirst(); rows.append((0..<512).map { Float(($0 + n + 400) % 256) / 255 })
            let incremental = await renderer.image(rows: rows, revision: n)!
            if n == 100 {
                let reference = await FT8WaterfallRasterizer().image(rows: rows, revision: 0)!
                precondition((incremental.dataProvider!.data! as Data) == (reference.dataProvider!.data! as Data))
            }
        }
        let incrementalSeconds = Date().timeIntervalSince(start)
        let mapped = await renderer.mappedRowCount
        precondition(mapped == 500)
        let fullStart = Date()
        for n in 0..<100 { _ = await FT8WaterfallRasterizer().image(rows: rows, revision: n) }
        let fullSeconds = Date().timeIntervalSince(fullStart)
        let empty = await renderer.image(rows: [], revision: 101)
        precondition(empty == nil)
        let reset = await renderer.image(rows: [[.nan, .infinity, -1, 2]], revision: 102)
        precondition(reset?.width == 4 && reset?.height == 1)
        print("PASS identical pixels, rolling history, reset, nonfinite; incremental 100 frames \(incrementalSeconds)s; full \(fullSeconds)s; 500 vs 40,400 colorized rows")
    }
}
