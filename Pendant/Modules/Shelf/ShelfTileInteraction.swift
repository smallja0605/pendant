import AppKit
import QuickLookUI
import SwiftUI

/// Transparent AppKit layer over a shelf tile: click selection (with ⇧ / ⌘), dragging out as *copies*, and the keys
/// Space (Quick Look), ⌫ (remove) and ⌘A (select all). SwiftUI's own drag cannot restrict the operation to "copy".
struct ShelfTileInteraction: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags) -> Void
    /// Copies of the selected files to hand to the drag (called when a drag really starts).
    let dragURLs: () -> [URL]
    let dragImage: NSImage?
    let onQuickLook: () -> Void
    let onDelete: () -> Void
    let onSelectAll: () -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView() }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.onClick = onClick
        view.dragURLs = dragURLs
        view.dragImage = dragImage
        view.onQuickLook = onQuickLook
        view.onDelete = onDelete
        view.onSelectAll = onSelectAll
    }

    final class InteractionView: NSView, NSDraggingSource {
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var dragURLs: (() -> [URL])?
        var dragImage: NSImage?
        var onQuickLook: (() -> Void)?
        var onDelete: (() -> Void)?
        var onSelectAll: (() -> Void)?
        private var mouseDownPoint: NSPoint?
        private var dragStarted = false

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            mouseDownPoint = event.locationInWindow
            dragStarted = false
            onClick?(event.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragStarted, let start = mouseDownPoint,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4,
                  let urls = dragURLs?(), !urls.isEmpty else { return }
            dragStarted = true
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
                let image = index == 0 ? (dragImage ?? fileIcon) : fileIcon
                let size = NSSize(width: 44, height: 44)
                let origin = convert(event.locationInWindow, from: nil)
                let frame = NSRect(x: origin.x - size.width / 2 + CGFloat(index) * 3, y: origin.y - size.height / 2,
                                   width: size.width, height: size.height)
                item.setDraggingFrame(frame, contents: image)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 49: onQuickLook?()
            case 51, 117: onDelete?()
            default: super.keyDown(with: event)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "a" else { return false }
            onSelectAll?()
            return true
        }
    }
}

/// Quick Look for shelf files (Space).
@MainActor
final class ShelfPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = ShelfPreview()
    private var urls: [URL] = []

    func toggle(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { MainActor.assumeIsolated { urls.count } }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
