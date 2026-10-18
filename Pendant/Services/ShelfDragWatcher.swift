import AppKit

/// Notices a file drag (from Finder or any app) and reports where the pointer is, so the capsule can open on the
/// shelf when the drag nears the notch (requirements 4.6). Listens only; no permission needed.
///
/// Only a drag that *carries files* counts: every mouse press takes a snapshot of the drag pasteboard, and a drag is a file
/// drag only if that pasteboard was written afterwards (the drag session puts its items there) and holds file URLs.
/// Dragging a window, selecting text or resizing leaves it untouched, so they never open the shelf — an earlier version
/// trusted whatever the pasteboard still held from the last file drag.
@MainActor
final class ShelfDragWatcher {
    var onFileDrag: ((CGPoint) -> Void)?
    private var dragMonitor: Any?
    private var downMonitor: Any?
    private var baselineChangeCount = NSPasteboard(name: .drag).changeCount
    private var draggingFiles = false

    func start() {
        guard dragMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.pressed() }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle() }
        }
    }

    func stop() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let downMonitor { NSEvent.removeMonitor(downMonitor) }
        dragMonitor = nil
        downMonitor = nil
    }

    private func pressed() {
        baselineChangeCount = NSPasteboard(name: .drag).changeCount
        draggingFiles = false
    }

    private func handle() {
        if !draggingFiles {
            let board = NSPasteboard(name: .drag)
            guard board.changeCount != baselineChangeCount else { return } // nothing is being dragged (a window, a selection…)
            draggingFiles = board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            if !draggingFiles { baselineChangeCount = board.changeCount } // another kind of drag: stop asking
        }
        if draggingFiles { onFileDrag?(NSEvent.mouseLocation) }
    }
}
