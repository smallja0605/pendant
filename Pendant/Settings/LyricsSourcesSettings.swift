import SwiftUI
import UniformTypeIdentifiers

/// The ordered list of lyrics sources (settings › 小工具 › 音樂): switch each on or off, move it up or down, set up the ones that need a
/// key or an address, add your own.
struct LyricsSourcesSection: View {
    @State private var settings = AppSettings.shared
    @State private var addPopover = AnchoredPopover()
    @State private var hovering = false
    @State private var dragging: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TipLabel(title: "歌詞來源", tip: "由上往下查詢：找到同步歌詞就停，沒有就用最先找到的純文字")
            VStack(spacing: 0) {
                ForEach(Array(settings.lyricsSources.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().opacity(0.4) }
                    LyricsSourceRow(
                        item: item, index: index, count: settings.lyricsSources.count, showsArrows: hovering, dragging: $dragging
                    )
                }
            }
            .padding(.horizontal, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // A drag cancelled outside any row never reports back: the next hover clears its mark.
            .onHover { hovering = $0; if $0 { dragging = nil } }
            .animation(.easeInOut(duration: 0.18), value: hovering)
            Button("新增來源") {
                addPopover.toggle(size: .zero, autoSize: true) { popover in
                    AnyView(LyricsSourceForm(draft: .newCustom, isNew: true, close: { popover.close() }))
                }
            }
            .background(PopoverAnchor(popover: addPopover))
        }
    }
}

private struct LyricsSourceRow: View {
    let item: LyricsSourceItem
    let index: Int
    let count: Int
    let showsArrows: Bool
    @Binding var dragging: String?
    @State private var settings = AppSettings.shared
    @State private var popover = AnchoredPopover()

    var body: some View {
        HStack(spacing: 8) {
            // The handle: drag it to move the source anywhere in the list.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    dragging = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
            Text(loc(item.name)).lineLimit(1)
            if item.needsSetup && !isReady {
                Text("未設定").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if item.needsSetup {
                Button { open() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .background(PopoverAnchor(popover: popover))
            }
            Group {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(index == count - 1)
            }
            .opacity(showsArrows ? 1 : 0)
            .allowsHitTesting(showsArrows)
            Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch)
        }
        .frame(minHeight: 34)
        .opacity(dragging == item.id ? 0.4 : 1)
        .onDrop(of: [.text], delegate: SourceDropDelegate(target: item.id, dragging: $dragging))
    }

    private var isReady: Bool {
        switch item.kind {
        case .musixmatch: LyricsKeychain.read(account: "musixmatch")?.isEmpty == false
        case .custom: !item.urlTemplate.isEmpty
        default: true
        }
    }

    private var enabled: Binding<Bool> {
        Binding(get: { item.enabled }, set: { value in update { $0.enabled = value } })
    }

    private func update(_ change: (inout LyricsSourceItem) -> Void) {
        guard let position = settings.lyricsSources.firstIndex(where: { $0.id == item.id }) else { return }
        change(&settings.lyricsSources[position])
    }

    private func move(_ offset: Int) {
        let target = index + offset
        guard settings.lyricsSources.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { settings.lyricsSources.swapAt(index, target) }
    }

    private func open() {
        popover.toggle(size: .zero, autoSize: true) { popover in
            AnyView(LyricsSourceForm(draft: item, isNew: false, close: { popover.close() }))
        }
    }
}

/// While a handle is dragged over a row the dragged source takes that row's place (the others slide), and the drop just ends it.
private struct SourceDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        let settings = AppSettings.shared
        guard let dragging, dragging != target,
              let from = settings.lyricsSources.firstIndex(where: { $0.id == dragging }),
              let to = settings.lyricsSources.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.lyricsSources.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The small form in a popover: a key for Musixmatch, or the name, address and answer format of a custom source.
private struct LyricsSourceForm: View {
    @State var draft: LyricsSourceItem
    let isNew: Bool
    let close: () -> Void
    @State private var settings = AppSettings.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.kind == .musixmatch {
                Text("Musixmatch API 金鑰").font(.headline)
                SecureField("貼上你的金鑰", text: $key).textFieldStyle(.roundedBorder)
                Text("金鑰只存在這台 Mac 的鑰匙圈。免費方案只會回傳部分純文字歌詞。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(isNew ? "新增歌詞來源" : "編輯來源").font(.headline)
                TextField("名稱", text: $draft.name).textFieldStyle(.roundedBorder)
                TextField("https://example.com/lyrics?title={title}&artist={artist}", text: $draft.urlTemplate)
                    .textFieldStyle(.roundedBorder)
                Text("可用 {title} {artist} {album} {duration}（秒）；只接受 https").font(.caption).foregroundStyle(.secondary)
                Picker("回應格式", selection: $draft.format) {
                    Text("歌詞文字（LRC 或純文字）").tag(LyricsSourceItem.Format.text)
                    Text("JSON").tag(LyricsSourceItem.Format.json)
                }
                if draft.format == .json {
                    TextField("歌詞所在的欄位，例如 data.lyrics.lrc", text: $draft.jsonPath).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                if draft.kind == .custom && !isNew {
                    Button("刪除", role: .destructive) { delete() }
                }
                Spacer()
                Button("取消") { close() }
                Button(isNew ? "加入" : "完成") { save() }
                    .keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(14)
        .frame(width: 340)
        .task { if draft.kind == .musixmatch { key = LyricsKeychain.read(account: "musixmatch") ?? "" } }
    }

    private var canSave: Bool {
        if draft.kind == .musixmatch { return true }
        return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.urlTemplate.hasPrefix("https://")
            && (draft.format == .text || !draft.jsonPath.isEmpty)
    }

    private func save() {
        if draft.kind == .musixmatch {
            LyricsKeychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: "musixmatch")
            draft.enabled = !key.isEmpty
        }
        if let position = settings.lyricsSources.firstIndex(where: { $0.id == draft.id }) {
            settings.lyricsSources[position] = draft
        } else {
            settings.lyricsSources.append(draft)
        }
        close()
    }

    private func delete() {
        settings.lyricsSources.removeAll { $0.id == draft.id }
        close()
    }
}

private extension LyricsSourceItem {
    static var newCustom: LyricsSourceItem {
        LyricsSourceItem(id: UUID().uuidString, kind: .custom, name: "", enabled: true)
    }
}
