import AppKit
import SwiftUI

final class DesktopWindow: NSPanel {
    private static let span = DesktopWidgetSpan.medium

    /// ウィンドウはカードの四辺に標準ウィジェットと同じ余白を持つ
    static var size: CGSize {
        let card = DesktopWidgetGrid.dimensions(of: span)
        return CGSize(width: card.width + 2 * NativeDesktopWidgets.windowInset, height: card.height + 2 * NativeDesktopWidgets.windowInset)
    }

    private var dragReleaseTimer: Timer?
    /// settle による移動の最中だけ非 nil、この間の didMove はユーザーのドラッグとして扱わない
    private var settleTarget: CGRect?

    init(content: some View) {
        super.init(
            contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(NativeDesktopWidgets.widgetLevel)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: content)
        hosting.menu = Self.makeMenu()
        contentView = hosting
        setFrameAutosaveName("DeskRunner.DesktopWindow")
        // 旧サイズで保存された frame が復元されても大きさは固定する
        setContentSize(Self.size)
        settle(animated: false)

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchForDragRelease() }
        }
        // 解像度や Dock の変更で格子の位置が変わる
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle(animated: false) }
        }
    }

    // ドラッグ開始 (ウィンドウ移動の追跡はこの中で走る) で吸着アニメーションを止め、掴んだ位置から動かせるようにする
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { cancelSettle() }
        super.sendEvent(event)
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    // 最後の didMove がマウスを離した後に届くこともあるので、ボタンの状態に関わらず離れるまで待つ
    private func watchForDragRelease() {
        guard settleTarget == nil, dragReleaseTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dragReleaseTimer = nil
                // Command を押したままなら標準ウィジェットと同じく格子に吸着させない
                if !NSEvent.modifierFlags.contains(.command) { self.settle(animated: true) }
            }
        }
        dragReleaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelSettle() {
        guard settleTarget != nil else { return }
        settleTarget = nil
        // 進行中のアニメーションは同じキーの 0 秒アニメーションで現在位置に置き換えて止める
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().setFrame(frame, display: true)
        }
    }

    private func settle(animated: Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        let inset = NativeDesktopWidgets.windowInset
        let topLeft = DesktopWidgetGrid.snap(
            frame.insetBy(dx: inset, dy: inset),
            span: Self.span,
            in: screen.visibleFrame,
            avoiding: NativeDesktopWidgets.frames()
        )
        let target = DesktopWidgetGrid.frame(topLeft: topLeft, span: Self.span).insetBy(dx: -inset, dy: -inset)
        guard target != frame else { return }

        settleTarget = target
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(target, display: true)
            settleTarget = nil
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            // 中断されて次の settle が始まっていたら、そちらの状態は消さない
            MainActor.assumeIsolated { if self?.settleTarget == target { self?.settleTarget = nil } }
        }
    }
}
