#if DEBUG
import AppKit

extension MediaController {
    func debugInject(playing: Bool) {
        // PENDANT_DEBUG_MEDIA_TRACK="title|artist|album|seconds": another made-up track (to try the real lyrics lookup).
        let spec = ProcessInfo.processInfo.environment["PENDANT_DEBUG_MEDIA_TRACK"]?.split(separator: "|").map(String.init)
        if let spec, spec.count == 4 {
            simulate(title: spec[0], artist: spec[1], album: spec[2], playing: playing, key: "debug-\(spec[0])",
                     colors: [.systemPink, .systemOrange], position: 133, duration: Double(spec[3]) ?? 202)
            return
        }
        simulate(title: "歌曲名稱", artist: "歌手名稱", album: "專輯名稱",
                 playing: playing, key: "debug", colors: [.systemPink, .systemOrange, .systemPurple], position: 133)
    }
}
#endif
