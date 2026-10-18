import SwiftUI

/// Front-camera mirror (requirements 4.8).
@MainActor
final class MirrorModule: PendantModule {
    let id = "mirror"
    let displayName = "鏡子"
    let symbolName = "web.camera"
    let cells = CellRange(default: 2, range: 2...6)
    let requiredPermissions: [PendantPermission] = [.camera]
    var isEnabled = false

    private let camera = CameraController.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(MirrorView(camera: camera).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(MirrorModuleSettings(camera: camera)) }

    func activate() {}
    func deactivate() { camera.stop() }
}

private struct MirrorModuleSettings: View {
    let camera: CameraController
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("水平鏡像(像鏡子一樣)", isOn: $settings.mirrorFlip)
            Picker("鏡頭", selection: $settings.mirrorCameraID) {
                Text("自動(前鏡頭)").tag("")
                ForEach(camera.devices) { device in Text(device.name).tag(device.id) }
            }
            .frame(maxWidth: 300)
            .onChange(of: settings.mirrorCameraID) { _, _ in camera.restart() }
            Text("相機只在鏡子頁面顯示時啟動,收合或切換頁面後立刻關閉。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { camera.reloadDevices() }
    }
}
