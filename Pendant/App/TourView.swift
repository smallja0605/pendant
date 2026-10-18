import SwiftUI

/// One page of the tour.
private struct TourPage {
    let title: String
    let points: [(symbol: String, text: String)]
    let picture: Picture

    enum Picture { case notch, music, modules, shelf, hud }
}

private let tourPages: [TourPage] = [
    TourPage(title: "動態島與小膠囊", points: [
        ("music.note", "音樂、計時器等進行中的事，會顯示在瀏海旁的小膠囊。"),
        ("cursorarrow.motionlines", "游標移上去會膨脹，點一下就展開成大膠囊。"),
        ("keyboard", "也可以用 ⌥Space 展開，←／→ 或 ⌘1…⌘9 切換分頁。"),
    ], picture: .notch),
    TourPage(title: "音樂", points: [
        ("hand.draw", "在小膠囊或音樂頁上雙指左右滑動：往左下一首，往右上一首。"),
        ("waveform", "換歌時，歌名與歌手會短暫浮現。"),
        ("airplayaudio", "展開後可以選 AirPlay 裝置、調整音量。"),
    ], picture: .music),
    TourPage(title: "待辦、日曆、計時器", points: [
        ("checklist", "待辦事項讀寫系統「提醒事項」，向左滑可以刪除。"),
        ("calendar", "日曆顯示當天行程，左右滑動切換日期。"),
        ("timer", "倒數與碼錶可以同時進行，結束時小膠囊會通知你。"),
    ], picture: .modules),
    TourPage(title: "檔案中轉站", points: [
        ("tray.and.arrow.down", "把檔案拖到瀏海，會暫存一份複本，原檔不動。"),
        ("eye", "按空白鍵快速預覽，也能直接 AirDrop。"),
        ("hand.point.up.left", "只有真的在拖檔案時才會自動打開。"),
    ], picture: .shelf),
    TourPage(title: "音量與亮度", points: [
        ("speaker.wave.2", "調整音量或亮度時，瀏海兩側會長出提示。"),
        ("sun.max", "圖示會隨音量與亮度變化。"),
        ("lock.shield", "要隱藏系統自己的提示，需要「輔助使用」權限。"),
    ], picture: .hud),
]

struct TourView: View {
    let onFinish: () -> Void

    /// Position along the strip: 0 = welcome, 1…5 = feature pages, 6 = done. Animated, so everything moves with it.
    @State private var position = TourView.startPosition
    @State private var settings = AppSettings.shared

    private let motion = Animation.spring(response: 0.46, dampingFraction: 0.88)
    private var lastFeature: Int { tourPages.count }
    private var donePosition: Int { tourPages.count + 1 }

    /// Normally the welcome page; PENDANT_DEBUG_TOUR_PAGE=n opens feature page n (0-based; 9 = the last page) in debug builds.
    private static var startPosition: Int {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["PENDANT_DEBUG_TOUR_PAGE"], let value = Int(raw) {
            return value < 0 ? 0 : min(value + 1, tourPages.count + 1)
        }
        #endif
        return 0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Every page (and the window footer) sits on one strip and slides with `position`; there is nothing to insert or
            // remove, so nothing can linger or overlap. The footer stays put between the feature pages and rides along
            // with the strip when the welcome or the done page comes in.
            ZStack(alignment: .topLeading) {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                Color.black.opacity(0.3)
                piece(0, width: width) { welcomeBackground }
                piece(0, width: width) { welcome }
                ForEach(tourPages.indices, id: \.self) { index in
                    piece(index + 1, width: width) { featureBody(tourPages[index]).padding(.bottom, footerHeight) }
                }
                piece(donePosition, width: width) { done }
                footer
                    .frame(width: width, height: footerHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(x: footerOffset(width: width))
            }
            .frame(width: width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        #if DEBUG
        .task {
            // PENDANT_DEBUG_TOUR_AUTO=1: advances through all pages by itself (screen recordings of the transitions).
            guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_TOUR_AUTO"] != nil else { return }
            while position < donePosition {
                try? await Task.sleep(for: .seconds(1.4))
                go(to: position + 1)
            }
        }
        #endif
    }

    private let footerHeight: CGFloat = 76

    private func piece<Content: View>(_ slot: Int, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .offset(x: (CGFloat(slot) - CGFloat(position)) * width)
    }

    private func footerOffset(width: CGFloat) -> CGFloat {
        let current = CGFloat(position)
        if current < 1 { return (1 - current) * width }
        if current > CGFloat(lastFeature) { return -(current - CGFloat(lastFeature)) * width }
        return 0
    }

    private func go(to target: Int) {
        withAnimation(motion) { position = min(max(target, 0), donePosition) }
    }

    /// The feature page shown (clamped), for the footer's dots and buttons.
    private var page: Int { min(max(position - 1, 0), lastFeature - 1) }

    // MARK: Scenes

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104)
            Text("歡迎使用 Pendant").font(.system(size: 34, weight: .bold))
            Text("把瀏海變成可以互動的動態島").font(.system(size: 16)).foregroundStyle(.secondary)
            Button { go(to: 1) } label: {
                Text("開始導覽").font(.system(size: 15, weight: .semibold)).frame(width: 150, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 14)
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("準備好了").font(.system(size: 30, weight: .bold))
            Text("把游標移到瀏海試試看。\n設定隨時可以在選單列圖示、或在瀏海上按右鍵打開。").multilineTextAlignment(.center)
                .font(.system(size: 15)).foregroundStyle(.secondary)
            Button(action: onFinish) {
                Text("完成").font(.system(size: 15, weight: .semibold)).frame(width: 150, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 10)
            Button { go(to: lastFeature) } label: {
                Text("上一步").frame(width: 96, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 2)
        }
    }

    private var welcomeBackground: some View {
        // Part of the window background, so the colour runs up under the title bar as well (no band at the top).
        ZStack {
            RadialGradient(colors: [Color.pink.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.purple.opacity(0.30), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 460)
        }
    }

    private func featureBody(_ item: TourPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                Text("Pendant").font(.system(size: 15, weight: .bold))
            }
            .padding(.top, 38)
            Text(item.title).font(.system(size: 30, weight: .bold)).padding(.top, 18)
            HStack(alignment: .center, spacing: 30) {
                TourPicture(kind: item.picture)
                    .frame(width: 330, height: item.picture == .modules ? 132 : 210)
                    .frame(height: 210, alignment: .top) // the picture hangs from the top of its row, no gap above it
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(item.points.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.points[index].symbol)
                                .font(.system(size: 14, weight: .semibold)).frame(width: 20)
                                .foregroundStyle(Color.accentColor)
                            Text(item.points[index].text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 22)
            Spacer(minLength: 12)
            toggleCard(for: item.picture)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func toggleCard(for picture: TourPage.Picture) -> some View {
        switch picture {
        case .notch:
            card("登入時自動啟動", "不用每次手動打開 Pendant。", isOn: Binding(
                get: { LoginItem.isEnabled }, set: { LoginItem.set($0) }
            ))
        case .music: card("雙指左右滑動切歌", "也可以到「設定 → 手勢操控」調整靈敏度。", isOn: $settings.swipeTracksEnabled)
        case .modules:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("第一次使用時 macOS 會詢問權限").font(.system(size: 14, weight: .semibold))
                    Text("行事曆、提醒事項、相機都只在你用到那個功能時才會詢問。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .shelf: card("拖曳檔案時自動打開檔案中轉站", "靠近瀏海時展開，沒放下就自動收起。", isOn: $settings.dragOpensShelf)
        case .hud:
            card("調整音量時顯示", "亮度可以到「設定 → 動態島」另外開關。", isOn: $settings.hudVolume)
        }
    }

    private func card(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Back and next are the same size (the back one without a background), so the dots, centred on the window, stay centred.
    private var footer: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(tourPages.indices, id: \.self) { index in
                    Circle().fill(index == page ? Color.accentColor : Color.white.opacity(0.25)).frame(width: 7, height: 7)
                }
            }
            HStack {
                Button { go(to: position - 1) } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 96, height: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button { go(to: position + 1) } label: {
                    Text("下一步").font(.system(size: 14, weight: .semibold)).frame(width: 96, height: 32)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

}

// MARK: Pictures

/// The little desktop with a mock-up of the feature.
private struct TourPicture: View {
    let kind: TourPage.Picture

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.5), Color(red: 0.42, green: 0.2, blue: 0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 0) {
                switch kind {
                case .notch: MockCapsule(width: 188, height: 30) { MockCover(); Spacer(); MockBars() }
                case .music:
                    MockCapsule(width: 188, height: 30) { MockCover(); Spacer(); MockBars() }
                    // Like the real controls: previous on the left, next on the right.
                    HStack(spacing: 44) {
                        VStack(spacing: 6) {
                            Image(systemName: "backward.end.fill").font(.system(size: 20, weight: .bold))
                            Text("向右滑\n上一首").multilineTextAlignment(.center).font(.system(size: 12, weight: .semibold))
                        }
                        VStack(spacing: 6) {
                            Image(systemName: "forward.end.fill").font(.system(size: 20, weight: .bold))
                            Text("向左滑\n下一首").multilineTextAlignment(.center).font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9)).padding(.top, 38)
                case .modules:
                    MockExpanded()
                case .shelf:
                    MockCapsule(width: 188, height: 30) { Spacer() }
                    HStack(spacing: 10) {
                        ForEach(["doc.fill", "photo.fill", "doc.zipper"], id: \.self) { symbol in
                            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white.opacity(0.92))
                                .frame(width: 54, height: 54)
                                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.top, 34)
                    Image(systemName: "arrow.up.doc.fill").font(.system(size: 22)).foregroundStyle(.white).padding(.top, 12)
                case .hud:
                    MockHUD()
                }
            }
            .padding(.top, 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MockCapsule<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            NotchShape(bottomRadius: 11).fill(Color.black).frame(width: width + 16, height: height)
            HStack(spacing: 0) { content }.padding(.horizontal, 9).frame(width: width, height: height)
        }
    }
}

private struct MockCover: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)).frame(width: 18, height: 18)
    }
}

private struct MockBars: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach([7.0, 12.0, 9.0], id: \.self) { height in Capsule().fill(.white).frame(width: 2.5, height: height) }
        }
    }
}

private struct MockExpanded: View {
    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: 18).fill(Color.black).frame(width: 330, height: 132)
            HStack(spacing: 10) {
                ForEach(["checklist", "calendar", "timer"], id: \.self) { symbol in
                    VStack(spacing: 8) {
                        Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white)
                        Capsule().fill(.white.opacity(0.35)).frame(width: 50, height: 5)
                        Capsule().fill(.white.opacity(0.2)).frame(width: 38, height: 5)
                    }
                    .frame(width: 86, height: 96)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 20) // tiles: 20 pt below the top edge, 16 pt above the bottom edge (no empty band inside the capsule)
        }
    }
}

private struct MockHUD: View {
    var body: some View {
        MockCapsule(width: 300, height: 30) {
            HUDIcon(kind: .volume, level: 0.7, muted: false).frame(width: 16, height: 16)
            Text("音量").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.leading, 6)
            Spacer()
            Text("70%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            HUDBar(level: 0.7).frame(width: 32, height: 4).padding(.leading, 6)
        }
    }
}
