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
        ModuleForm(moduleID: "mirror") {
            Toggle("水平鏡像", isOn: $settings.mirrorFlip)
            DropdownRow(title: "鏡頭", selection: $settings.mirrorCameraID,
                        options: [("", "自動 (前鏡頭)")] + camera.devices.map { ($0.id, $0.name) })
            .onChange(of: settings.mirrorCameraID) { _, _ in camera.restart() }
        }
        .onAppear { camera.reloadDevices() }
    }
}
