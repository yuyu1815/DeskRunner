import CoreGraphics

struct DesktopWidgetSpan: Equatable {
    var columns: Int
    var rows: Int

    static let medium = DesktopWidgetSpan(columns: 2, rows: 1)
}

// 出典 thdxg/macterm (MIT, LICENSE-macterm) DesktopWidgetGrid を簡略化して移植
/// 標準ウィジェットと同じ 180pt 格子、座標は AppKit のグローバル座標 (左下原点) で frame は影の余白を除いたカード本体
enum DesktopWidgetGrid {
    static let cell: CGFloat = 164
    static let gap: CGFloat = 16
    static var pitch: CGFloat { cell + gap }

    /// 標準ウィジェットのウィンドウが visibleFrame の左上から 8pt (原点 8, 47) に並ぶ実測から、カードは 16pt
    static let edgeInset = CGSize(width: 16, height: 16)

    /// 近くのウィジェットの格子に参加する距離 (カード間の隙間)
    static var joinDistance: CGFloat { pitch }

    static func dimensions(of span: DesktopWidgetSpan) -> CGSize {
        CGSize(
            width: CGFloat(span.columns) * cell + CGFloat(span.columns - 1) * gap,
            height: CGFloat(span.rows) * cell + CGFloat(span.rows - 1) * gap
        )
    }

    static func frame(topLeft: CGPoint, span: DesktopWidgetSpan) -> CGRect {
        let size = dimensions(of: span)
        return CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    /// 画面の既定の格子の左上マスの左上
    static func origin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.minX + edgeInset.width, y: visibleFrame.maxY - edgeInset.height)
    }

    static func topLeft(column: Int, row: Int, lattice: CGPoint) -> CGPoint {
        CGPoint(x: lattice.x + CGFloat(column) * pitch, y: lattice.y - CGFloat(row) * pitch)
    }

    /// frame が属する格子、join 距離内で最も近い neighbours の左上を通るもの、無ければ画面の既定
    static func lattice(for frame: CGRect, in visibleFrame: CGRect, neighbours: [CGRect]) -> CGPoint {
        let nearest = neighbours
            .filter { visibleFrame.contains(CGPoint(x: $0.midX, y: $0.midY)) }
            .map { (frame: $0, distance: distance(frame, $0)) }
            .filter { $0.distance <= joinDistance }
            .min { $0.distance < $1.distance }
        return nearest.map { CGPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? origin(in: visibleFrame)
    }

    /// ドロップされた frame が落ち着く左上、属する格子のマスのうち occupied と重ならず、ドロップ位置に最も近いもの
    static func snap(
        _ frame: CGRect,
        span: DesktopWidgetSpan,
        in visibleFrame: CGRect,
        avoiding occupied: [CGRect]
    ) -> CGPoint {
        let lattice = lattice(for: frame, in: visibleFrame, neighbours: occupied)
        return nearestFree(to: CGPoint(x: frame.minX, y: frame.maxY), span: span, lattice: lattice, in: visibleFrame, avoiding: occupied)
    }

    /// span のマスが画面に収まる格子の列範囲、収まらなければ nil
    private static func positions(from origin: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat) -> ClosedRange<Int>? {
        let first = Int(((lower - origin) / pitch).rounded(.up))
        let last = Int(((upper - length - origin) / pitch).rounded(.down))
        return first <= last ? first ... last : nil
    }

    /// 同じく行 (上から数える)
    private static func rowPositions(from origin: CGFloat, length: CGFloat, in visibleFrame: CGRect) -> ClosedRange<Int>? {
        let first = Int(((origin - visibleFrame.maxY) / pitch).rounded(.up))
        let last = Int(((origin - length - visibleFrame.minY) / pitch).rounded(.down))
        return first <= last ? first ... last : nil
    }

    /// target (カードの左上) に最も近い、画面内で occupied と重ならないマスの左上
    /// 距離は丸めたマスではなく target そのものから測る、マスに丸めてからだと最大で半マス (90pt) の誤差で遠いマスが同点になる
    /// 全て塞がっていれば最寄りのマスを画面内に寄せる
    private static func nearestFree(
        to target: CGPoint,
        span: DesktopWidgetSpan,
        lattice: CGPoint,
        in visibleFrame: CGRect,
        avoiding occupied: [CGRect]
    ) -> CGPoint {
        let size = dimensions(of: span)
        let nearest = (column: Int(((target.x - lattice.x) / pitch).rounded()), row: Int(((lattice.y - target.y) / pitch).rounded()))
        let columns = positions(from: lattice.x, length: size.width, lower: visibleFrame.minX, upper: visibleFrame.maxX)
            ?? nearest.column ... nearest.column
        let rows = rowPositions(from: lattice.y, length: size.height, in: visibleFrame) ?? nearest.row ... nearest.row
        var best: (topLeft: CGPoint, distance: CGFloat)?
        for column in columns {
            for row in rows {
                let topLeft = topLeft(column: column, row: row, lattice: lattice)
                let candidate = frame(topLeft: topLeft, span: span)
                // 辺が接するのは重なりではない (隙間はマスの pitch に含まれる)
                guard !occupied.contains(where: { $0.insetBy(dx: 1, dy: 1).intersects(candidate) }) else { continue }
                let distance = hypot(topLeft.x - target.x, topLeft.y - target.y)
                if distance < best?.distance ?? .infinity { best = (topLeft, distance) }
            }
        }
        return best?.topLeft ?? topLeft(
            column: min(max(nearest.column, columns.lowerBound), columns.upperBound),
            row: min(max(nearest.row, rows.lowerBound), rows.upperBound),
            lattice: lattice
        )
    }

    /// 2 つの矩形の隙間 (接する・重なるなら 0)
    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let dy = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        return hypot(dx, dy)
    }
}
