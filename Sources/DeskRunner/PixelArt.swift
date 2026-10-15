import CoreGraphics
import Foundation

struct PixelArt: Sendable {
    let width: Int
    let height: Int
    private let isFilled: @Sendable (_ x: Int, _ y: Int) -> Bool

    init(width: Int, height: Int, isFilled: @escaping @Sendable (_ x: Int, _ y: Int) -> Bool) {
        self.width = width
        self.height = height
        self.isFilled = isFilled
    }

    init(width: Int, height: Int, stamps: [(x: Int, rows: [String])]) {
        var filled = Set<Int>()
        for stamp in stamps {
            for (y, row) in stamp.rows.enumerated() {
                for (dx, char) in row.enumerated() where char == "#" {
                    filled.insert(y * width + stamp.x + dx)
                }
            }
        }
        let filledCells = filled
        self.init(width: width, height: height) { x, y in filledCells.contains(y * width + x) }
    }

    func image(repeating count: Int) -> CGImage? {
        let totalWidth = width * count
        var pixels = [UInt8](repeating: 0, count: totalWidth * height * 4)
        for y in 0..<height {
            for x in 0..<totalWidth where isFilled(x % width, y) {
                let offset = (y * totalWidth + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: [255, 255, 255, 255])
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: totalWidth,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: totalWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

extension PixelArt {
    static let grass = PixelArt(width: 32, height: 2, stamps: [(x: 0, rows: [
        "..#.#........#.#........#.#.#...",
        "...#..........#..........###....",
    ])])

    static let soil = PixelArt(width: 32, height: 3, stamps: [(x: 0, rows: [
        "################################",
        "......#............#.........#..",
        "...........#...........#........",
    ])])

    static let hills = PixelArt(width: 76, height: 10) { x, y in
        let t = Double(x) / 76 * 2 * .pi
        let height = Int((4 + 3 * sin(t) + 1.5 * sin(2 * t + 1)).rounded())
        return y >= 10 - min(9, max(1, height))
    }

    static let clouds = PixelArt(width: 120, height: 3, stamps: [
        (x: 8, rows: [
            "....###.....",
            ".#######.##.",
            "############",
        ]),
        (x: 70, rows: [
            "..##...",
            ".#####.",
            "#######",
        ]),
    ])
}
