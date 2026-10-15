import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWindow?
    private let sampler = MetricsSampler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = DesktopWindow(content: WidgetView(sampler: sampler))
        window.orderFrontRegardless()
        self.window = window
        sampler.start()
    }
}
