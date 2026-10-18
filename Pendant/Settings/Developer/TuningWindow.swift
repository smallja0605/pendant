import AppKit
import SwiftUI

// Developer options: live tuning of layout / animation numbers. Opened with ⌥ held on the menu bar menu
// ("開發者選項…", ⌥⌘,). Values save automatically and survive relaunches (see `Tuning.save`).

@MainActor
final class TuningWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: TuningView()))
            window.title = "開發者選項"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 760))
            window.center()
            window.level = .floating
            self.window = window
        }
        if let window { WindowPresence.opened(window) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct TuningView: View {
    @State private var tuning = Tuning.shared
    @State private var copied = false

    private var groups: [(name: String, items: [TuningParameter])] {
        var order: [String] = []
        for parameter in Tuning.parameters where !order.contains(parameter.group) { order.append(parameter.group) }
        return order.map { name in (name, Tuning.parameters.filter { $0.group == name }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { TuningRow(parameter: $0, tuning: tuning) }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("重設全部") { tuning.resetAll() }
                Text("變更會自動儲存").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "已複製" : "複製全部數值") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tuning.report(), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
            }
            .padding(12)
        }
    }
}

private struct TuningRow: View {
    let parameter: TuningParameter
    let tuning: Tuning

    var body: some View {
        let value = Binding(
            get: { tuning[keyPath: parameter.keyPath] },
            set: {
                tuning[keyPath: parameter.keyPath] = $0
                tuning.save()
            }
        )
        HStack(spacing: 10) {
            Text(parameter.title).frame(width: 150, alignment: .leading)
            HapticSlider(value: value, in: parameter.range)
            NumberField(
                value: value, range: parameter.range,
                step: max((parameter.range.upperBound - parameter.range.lowerBound) / 100, 0.001),
                fractionDigits: 3, width: 72
            )
        }
    }
}
