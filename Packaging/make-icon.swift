// アプリアイコンを描いて Packaging/AppIcon.icns を作る
// 使い方: swift Packaging/make-icon.swift (リポジトリのルートで実行)
import AppKit

let grid = 32
let canvas = 1024
// macOS のアイコン用グリッドに合わせ、本体は 824pt の角丸正方形にする
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
let cell = body.width / CGFloat(grid)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let skyTop = (59, 125, 217)
let skyBottom = (143, 197, 240)
let cloud = rgb(255, 255, 255)
let hill = rgb(61, 143, 74)
let grass = rgb(92, 186, 74)
let dirt = rgb(140, 89, 43)
let soil = rgb(92, 59, 26)
let cat = rgb(255, 255, 255)
let catOutline = rgb(38, 44, 58)

// y=0 を上端としたマス目
var pixels = [[CGColor?]](repeating: [CGColor?](repeating: nil, count: grid), count: grid)

let groundRow = 23
for y in 0..<groundRow {
    let t = Double(y) / Double(groundRow - 1)
    let band = (t * 5).rounded() / 5
    let mix = { (a: Int, b: Int) in Int(Double(a) + (Double(b) - Double(a)) * band) }
    let color = rgb(mix(skyTop.0, skyBottom.0), mix(skyTop.1, skyBottom.1), mix(skyTop.2, skyBottom.2))
    for x in 0..<grid { pixels[y][x] = color }
}

func stamp(_ rows: [String], x: Int, y: Int, color: CGColor) {
    for (dy, row) in rows.enumerated() {
        for (dx, char) in row.enumerated() where char == "#" {
            let px = x + dx, py = y + dy
            if (0..<grid).contains(px), (0..<grid).contains(py) { pixels[py][px] = color }
        }
    }
}

stamp(["..##...", ".#####.", "#######"], x: 3, y: 4, color: cloud)
stamp(["...###.....", ".#######.#.", "###########"], x: 18, y: 7, color: cloud)

for x in 0..<grid {
    let t = Double(x) / Double(grid) * 2 * .pi
    let height = Int((3 + 2 * sin(t + 0.6) + 1 * sin(2 * t)).rounded())
    for y in max(0, groundRow - height)..<groundRow { pixels[y][x] = hill }
}

for x in 0..<grid {
    pixels[groundRow][x] = grass
    pixels[groundRow + 1][x] = soil
    for y in (groundRow + 2)..<grid { pixels[y][x] = dirt }
}
for (x, y) in [(2, 27), (9, 29), (14, 26), (21, 28), (27, 30), (30, 27), (5, 31), (17, 31)] {
    pixels[y][x] = soil
}
for x in stride(from: 1, to: grid, by: 4) where groundRow - 1 >= 0 {
    pixels[groundRow - 1][x] = grass
}

let catSprite = [
    "..............#..#",
    "..............####",
    "..............#.##",
    "#............#####",
    ".#..##############",
    "..#############...",
    "...############...",
    "...##........##...",
    "..##..........##..",
    ".##............##.",
]
let catOrigin = (x: (grid - catSprite[0].count) / 2, y: groundRow - catSprite.count)
var catCells = Set<[Int]>()
for (dy, row) in catSprite.enumerated() {
    for (dx, char) in row.enumerated() where char == "#" { catCells.insert([catOrigin.x + dx, catOrigin.y + dy]) }
}
// 明るい空でも輪郭が読めるよう、猫の周りを 1 マス暗く縁取る
for cellPosition in catCells {
    for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
        let x = cellPosition[0] + ox, y = cellPosition[1] + oy
        guard (0..<grid).contains(x), (0..<groundRow).contains(y), !catCells.contains([x, y]) else { continue }
        pixels[y][x] = catOutline
    }
}
for cellPosition in catCells { pixels[cellPosition[1]][cellPosition[0]] = cat }

func render(size: Int) -> Data {
    let scale = CGFloat(size) / CGFloat(canvas)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .none
    context.setShouldAntialias(false)

    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.addPath(shape)
    context.clip()
    for y in 0..<grid {
        for x in 0..<grid {
            guard let color = pixels[y][x] else { continue }
            context.setFillColor(color)
            let rect = CGRect(
                x: body.minX + CGFloat(x) * cell,
                y: body.maxY - CGFloat(y + 1) * cell,
                width: cell, height: cell
            ).insetBy(dx: -0.5, dy: -0.5)
            context.fill(rect)
        }
    }
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: URL(fileURLWithPath: "Packaging/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Packaging/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Packaging/AppIcon.icns" : "iconutil failed")
