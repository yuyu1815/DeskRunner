import AppKit
import SwiftUI

/// RunCat Neo (Apache-2.0) の RunnerLayer を簡略化して移植し、平原の背景を足したもの
struct RunnerView: NSViewRepresentable {
    let size: CGSize
    let speed: Float

    func makeNSView(context: Context) -> RunnerNSView { RunnerNSView(size: size) }

    func updateNSView(_ view: RunnerNSView, context: Context) {
        view.setSpeed(speed)
    }
}

final class RunnerNSView: NSView {
    private static let groundTop: CGFloat = 3

    private let size: CGSize
    private let scene = CALayer()
    private var tinted: [(layer: CALayer, color: NSColor)] = []

    init(size: CGSize) {
        self.size = size
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        scene.frame = bounds
        scene.masksToBounds = true
        scene.cornerRadius = 12
        layer?.addSublayer(scene)

        let sky = CAGradientLayer()
        sky.frame = scene.bounds
        sky.colors = [Palette.horizon.cgColor, Palette.sky.cgColor]
        scene.addSublayer(sky)

        let dirt = CALayer()
        dirt.frame = CGRect(x: 0, y: 0, width: size.width, height: Self.groundTop)
        dirt.backgroundColor = Palette.dirt.cgColor
        scene.addSublayer(dirt)

        addScrolling(.clouds, y: size.height - 8, pointsPerSecond: 0.6, color: Palette.cloud)
        addScrolling(.hills, y: Self.groundTop, pointsPerSecond: 1.5, color: Palette.hill)
        addScrolling(.soil, y: 0, pointsPerSecond: 6, color: Palette.soil)
        addScrolling(.grass, y: Self.groundTop, pointsPerSecond: 6, color: Palette.grass)
        addCat()
        updateColor()
    }

    private enum Palette {
        static let sky = NSColor(srgbRed: 0.23, green: 0.49, blue: 0.85, alpha: 1)
        static let horizon = NSColor(srgbRed: 0.56, green: 0.77, blue: 0.94, alpha: 1)
        static let cloud = NSColor.white.withAlphaComponent(0.9)
        static let hill = NSColor(srgbRed: 0.24, green: 0.56, blue: 0.29, alpha: 1)
        static let grass = NSColor(srgbRed: 0.36, green: 0.73, blue: 0.29, alpha: 1)
        static let dirt = NSColor(srgbRed: 0.55, green: 0.35, blue: 0.17, alpha: 1)
        static let soil = NSColor(srgbRed: 0.36, green: 0.23, blue: 0.10, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { size }

    private func addScrolling(_ art: PixelArt, y: CGFloat, pointsPerSecond: Double, color: NSColor) {
        let repeats = Int((size.width / CGFloat(art.width)).rounded(.up)) + 1
        let mask = CALayer()
        mask.contents = art.image(repeating: repeats)
        mask.magnificationFilter = .nearest
        mask.anchorPoint = .zero
        mask.frame = CGRect(x: 0, y: 0, width: CGFloat(art.width * repeats), height: CGFloat(art.height))

        let scroll = CABasicAnimation(keyPath: "position.x")
        scroll.fromValue = 0
        scroll.toValue = -CGFloat(art.width)
        scroll.duration = Double(art.width) / pointsPerSecond
        scroll.repeatCount = .infinity
        mask.add(scroll, forKey: "scroll")

        let tint = CALayer()
        tint.frame = CGRect(x: 0, y: y, width: size.width, height: CGFloat(art.height))
        tint.mask = mask
        scene.addSublayer(tint)
        tinted.append((tint, color))
    }

    private func addCat() {
        let frames = (0..<5).compactMap { i in
            // .app では Contents/Resources、swift run では SwiftPM のリソースバンドルから読む
            Bundle.main.image(forResource: "cat-frame-\(i)") ?? Bundle.module.image(forResource: "cat-frame-\(i)")
        }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.duration = Double(frames.count) / 2.0
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false

        // 猫の画像は下端 1.5pt が透明なので、その分下げて足を地面に付ける
        let cat = CALayer()
        cat.frame = CGRect(x: 20, y: Self.groundTop - 1.5, width: 28, height: 18)
        let mask = CALayer()
        mask.frame = cat.bounds
        mask.contentsGravity = .resizeAspect
        mask.add(animation, forKey: "running")
        cat.mask = mask
        scene.addSublayer(cat)
        tinted.append((cat, .labelColor))
    }

    override func viewDidChangeEffectiveAppearance() {
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (layer, color) in tinted {
                layer.backgroundColor = color.cgColor
            }
        }
    }

    func setSpeed(_ speed: Float) {
        guard scene.speed != speed else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.timeOffset = scene.convertTime(CACurrentMediaTime(), from: nil)
        scene.beginTime = CACurrentMediaTime()
        scene.speed = speed
        CATransaction.commit()
    }
}
