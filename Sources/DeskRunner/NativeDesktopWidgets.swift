import AppKit
import CoreGraphics

// 出典 thdxg/macterm (MIT, LICENSE-macterm) NativeDesktopWidgets を簡略化して移植
/// 標準ウィジェットは通知センター (com.apple.notificationcenterui) が持つ普通のウィンドウで、境界はウィンドウリストから権限なしで読める
enum NativeDesktopWidgets {
    static let hostBundleID = "com.apple.notificationcenterui"

    /// ウィジェットのウィンドウはカードの四辺に 8pt ずつ余白を持つ (中サイズは 360x180、カードは 344x164)
    static let windowInset: CGFloat = 8

    /// 標準ウィジェットのウィンドウレベル、デスクトップアイコンの 2 つ上
    static let widgetLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 2

    /// 標準ウィジェットのカードの frame (AppKit のグローバル座標)
    @MainActor
    static func frames() -> [CGRect] {
        // .optionAll は他の Space や非表示のウィジェットも返し (実測で同じ位置に 360x360 と 360x180 が重なる)、マスを塞ぐ幽霊になる
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        var hostPIDs: [pid_t: Bool] = [:]
        return widgetFrames(in: list, primaryScreenHeight: primaryHeight) { pid in
            if let known = hostPIDs[pid] { return known }
            let host = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == hostBundleID
            hostPIDs[pid] = host
            return host
        }
    }

    /// ウィンドウリスト (左上原点) から、ウィジェットのカードの frame を AppKit の座標で返す
    /// 通知センターは透明で空のウィンドウも同じ帯に持つので、ホスト・デスクトップの帯・alpha > 0・各辺がマスの整数倍の全てを満たすものだけを採る
    static func widgetFrames(
        in windows: [[String: Any]],
        primaryScreenHeight: CGFloat,
        isHost: (pid_t) -> Bool
    ) -> [CGRect] {
        let levels = (Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) ..< Int(CGWindowLevelForKey(.normalWindow))
        let frames: [CGRect] = windows.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  isWholeCells(width), isWholeCells(height),
                  isHost(pid)
            else { return nil }
            let window = CGRect(x: x, y: primaryScreenHeight - y - height, width: width, height: height)
            return window.insetBy(dx: windowInset, dy: windowInset)
        }
        // 同じ枠のウィンドウが複数あっても 1 つとして数える
        return frames.reduce(into: []) { unique, frame in
            if !unique.contains(frame) { unique.append(frame) }
        }
    }

    private static func isWholeCells(_ length: CGFloat) -> Bool {
        let cells = (length / DesktopWidgetGrid.pitch).rounded()
        return cells >= 1 && abs(length - cells * DesktopWidgetGrid.pitch) <= 1
    }
}
