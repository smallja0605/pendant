import AVFoundation
import SwiftUI

/// Mirror page: live front camera, flipped like a mirror. The camera runs only while the capsule is open on this page.
struct MirrorView: View {
    let camera: CameraController
    @Environment(\.capsuleExpanded) private var isExpanded
    @State private var settings = AppSettings.shared

    var body: some View {
        Group {
            switch camera.state {
            case .unknown:
                Color.clear
            case .notDetermined:
                AccessRequest(symbol: "web.camera", text: "要使用鏡子,需要先允許存取相機") { Task { await camera.requestAccess() } }
            case .denied:
                AccessGuide(symbol: "web.camera", text: "需要「相機」權限才能使用鏡子", pane: "Privacy_Camera")
            case .noCamera:
                Text("找不到相機").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        if camera.isRunning {
                            CameraPreview(session: camera.session, mirrored: settings.mirrorFlip)
                        } else {
                            // Never starts by itself: the user taps to turn the camera on (and taps again to turn it off).
                            VStack(spacing: 6) {
                                Image(systemName: "web.camera.fill").font(.system(size: 26, weight: .semibold))
                                Text("點一下開啟").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.1))
                        }
                    }
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        HapticService.shared.play(.dragStep)
                        if camera.isRunning { camera.stop() } else { camera.start() }
                    }
                    .accessibilityButton(camera.isRunning ? "關閉鏡子" : "開啟鏡子")
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .task { await camera.refreshAccess() }
        // The camera only ever runs while the capsule is open on this page, and only after a tap.
        .onChange(of: isExpanded) { _, open in if !open { camera.stop() } }
        .onDisappear { camera.stop() }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            // The connection exists only once the session runs; apply the mirror flag then.
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = AppSettings.shared.mirrorFlip
            }
        }
    }
}
