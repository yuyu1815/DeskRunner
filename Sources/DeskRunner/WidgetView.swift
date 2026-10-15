import ServiceManagement
import SwiftUI

struct WidgetView: View {
    private static let sceneSize = CGSize(width: 320, height: 52)

    let sampler: MetricsSampler

    @AppStorage("showsPercentAsBar") private var showsPercentAsBar = false
    @State private var isShowingSettings = false
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    // 登録の実体はシステム側にあるので、操作後は必ずシステムの状態を読み直す
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("ログイン項目の変更に失敗: \(error)")
                }
                launchesAtLogin = SMAppService.mainApp.status == .enabled
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        )
    }

    var body: some View {
        let m = sampler.metrics
        let card = DesktopWidgetGrid.dimensions(of: .medium)
        VStack(alignment: .leading, spacing: 10) {
            RunnerView(size: Self.sceneSize, speed: Self.runnerSpeed(cpu: m.cpu ?? 0))
                .frame(width: Self.sceneSize.width, height: Self.sceneSize.height)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if m.isVPN {
                            Label("VPN", systemImage: "lock.shield.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        Button {
                            isShowingSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.primary.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("% をグラフで表示", isOn: $showsPercentAsBar)
                                Toggle("ログイン時に起動", isOn: launchAtLogin)
                            }
                            .toggleStyle(.switch)
                            .padding(12)
                            .onAppear { launchesAtLogin = SMAppService.mainApp.status == .enabled }
                        }
                    }
                }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    percentRow("CPU", m.cpu)
                    percentRow("メモリ", m.memory)
                    percentRow("ストレージ", m.storage)
                }
                VStack(alignment: .leading, spacing: 6) {
                    row("書き込み", m.diskWrite.map(Self.rate))
                    row("↓", m.networkIn.map(Self.rate))
                    row("↑", m.networkOut.map(Self.rate))
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .glassEffect(in: .rect(cornerRadius: 27))
        .padding(NativeDesktopWidgets.windowInset)
    }

    @ViewBuilder
    private func percentRow(_ label: String, _ value: Double?) -> some View {
        if showsPercentAsBar {
            HStack(spacing: 6) {
                Text(label).foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                ProgressView(value: min(100, value ?? 0), total: 100)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                Text(value.map(Self.percent) ?? "--")
                    .frame(width: 32, alignment: .trailing)
            }
        } else {
            row(label, value.map(Self.percent))
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "--")
        }
    }

    /// RunCat Neo の RunnerService.updateRunnerSpeed と同じ式
    static func runnerSpeed(cpu: Double) -> Float {
        max(1.0, min(20.0, Float(cpu) / 5.0))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}
