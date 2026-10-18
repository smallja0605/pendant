import AppKit
import SwiftUI

/// Text view that edits one note and styles light Markdown as you type: `**bold**`, `- ` lists and `- [ ]` / `- [x]`
/// to-dos (a click on the box toggles it). Return continues a list; Return on an empty item ends it.
struct NoteTextEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let fontSize: CGFloat
    /// Becomes first responder when true (the capsule is open).
    let wantsFocus: Bool
    let onChange: (String) -> Void
    /// Commands from the toolbar are posted through this controller.
    let commands: NoteEditorCommands

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.onToggleCheckbox = { [weak coordinator = context.coordinator] in coordinator?.styleAndReport(report: true) }
        context.coordinator.textView = textView
        commands.textView = textView

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NoteTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        commands.textView = textView
        let newFont = coordinator.fontSize != fontSize
        coordinator.fontSize = fontSize
        if coordinator.currentID != noteID || textView.string != text {
            // A different note, or an outside change (undo of a delete): load it.
            coordinator.currentID = noteID
            if textView.string != text { textView.string = text }
            coordinator.styleAndReport(report: false)
            if wantsFocus { focusSoon(textView) }
        } else if newFont {
            coordinator.styleAndReport(report: false)
        }
        if wantsFocus, !coordinator.focused { focusSoon(textView) }
        coordinator.focused = wantsFocus
    }

    private func focusSoon(_ textView: NSTextView) {
        DispatchQueue.main.async {
            guard let window = textView.window, window.isKeyWindow || window.canBecomeKey else { return }
            window.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        weak var textView: NoteTextView?
        var currentID: UUID?
        var fontSize: CGFloat = 13
        var focused = false

        init(_ parent: NoteTextEditor) {
            self.parent = parent
            fontSize = parent.fontSize
        }

        func textDidChange(_ notification: Notification) { styleAndReport(report: true) }

        func styleAndReport(report: Bool) {
            guard let textView else { return }
            // Never restyle while an input method is composing (Chinese / Japanese typing).
            if !textView.hasMarkedText() { NoteStyler.apply(to: textView, fontSize: fontSize) }
            if report { parent.onChange(textView.string) }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            if NoteMarkdown.isEmptyListLine(line) {
                textView.setSelectedRange(NSRange(location: lineRange.location, length: (line as NSString).length))
                textView.insertText("", replacementRange: textView.selectedRange())
                return false // the Return itself then adds the plain newline
            }
            guard let prefix = NoteMarkdown.continuation(of: line) else { return false }
            textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
            return true
        }
    }
}

/// Text view with a click on a to-do box toggling it.
final class NoteTextView: NSTextView {
    var onToggleCheckbox: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let text = string as NSString
        if index <= text.length, text.length > 0 {
            let lineRange = text.lineRange(for: NSRange(location: min(index, text.length - 1), length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            if let box = NoteMarkdown.checkboxRange(in: line) {
                let boxRange = NSRange(location: lineRange.location + box.lowerBound, length: box.count)
                if NSLocationInRange(index, NSRange(location: boxRange.location, length: boxRange.length)) {
                    let toggled = NoteMarkdown.togglingCheckbox(in: line)
                    insertText(toggled, replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
                    onToggleCheckbox?()
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

/// Styling pass over the whole text (notes are small).
@MainActor
enum NoteStyler {
    private static let bold = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")

    static func apply(to textView: NSTextView, fontSize: CGFloat) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let base = NSFont.systemFont(ofSize: fontSize)
        let boldFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: NSColor.white], range: full)
        let text = storage.string as NSString
        bold?.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.font, value: boldFont, range: match.range)
            for marker in [NSRange(location: match.range.location, length: 2), NSRange(location: NSMaxRange(match.range) - 2, length: 2)] {
                storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.35), range: marker)
            }
        }
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = text.substring(with: range)
            if let box = NoteMarkdown.checkboxRange(in: line) {
                let checked = NoteMarkdown.isChecked(line)
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue,
                                     range: NSRange(location: range.location + box.lowerBound, length: box.count))
                if checked {
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .foregroundColor: NSColor.white.withAlphaComponent(0.4)],
                                          range: NSRange(location: range.location + box.upperBound,
                                                         length: max(range.length - box.upperBound, 0)))
                }
            } else if line.hasPrefix("- ") {
                storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.5),
                                     range: NSRange(location: range.location, length: 1))
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.font: base, .foregroundColor: NSColor.white]
    }
}

/// Toolbar actions applied to the editor's current selection.
@MainActor
final class NoteEditorCommands {
    weak var textView: NSTextView?

    func bold() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selection = (textView.string as NSString).substring(with: range)
        textView.insertText(NoteMarkdown.toggledBold(selection), replacementRange: range)
    }

    func prefixLines(_ prefix: String) {
        guard let textView else { return }
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: textView.selectedRange())
        let block = text.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        let body = trailingNewline ? String(block.dropLast()) : block
        let result = NoteMarkdown.togglingPrefix(prefix, on: body) + (trailingNewline ? "\n" : "")
        textView.insertText(result, replacementRange: lineRange)
    }
}
