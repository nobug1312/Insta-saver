import SwiftUI
import WebKit

extension Color {
    static let termBG = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let termSurface = Color(red: 0.067, green: 0.071, blue: 0.082)
    static let termInk = Color(red: 0.043, green: 0.090, blue: 0.137)
    static let termFG = Color(red: 0.925, green: 0.933, blue: 0.949)
    static let termDim = Color(red: 0.627, green: 0.651, blue: 0.690)
    static let termLine = Color.white.opacity(0.1)
    static let termIce = Color(red: 0.498, green: 0.718, blue: 0.910)
    static let termGreen = Color(red: 0.365, green: 0.839, blue: 0.627)
    static let termRed = Color(red: 0.941, green: 0.471, blue: 0.510)
}

@Observable
@MainActor
final class HomeModel {
    var url = ""
    var result: Resolved?
    var selected: Set<UUID> = []
    var searching = false
    var saving = false
    var saved = 0
    var error: String?
    var notice: String?
    var needLogin = false
    var loggedIn = Session.get() != nil
    private var searchID = UUID()

    var items: [MediaItem] { result?.items ?? [] }

    func find() async {
        guard !saving else { return }
        let id = UUID()
        searchID = id
        searching = false
        result = nil
        selected = []
        saved = 0
        error = nil
        notice = nil
        needLogin = false
        guard let link = IGLink(url) else { error = "that doesn't look like an Instagram link"; return }
        searching = true
        defer { if searchID == id { searching = false } }
        do {
            let r = try await IGClient.resolve(link)
            guard searchID == id else { return }
            result = r
            selected = Set(r.items.map(\.id))
        } catch {
            guard searchID == id else { return }
            if case IGError.loginRequired = error { needLogin = true }
            self.error = error.localizedDescription
        }
    }

    func clear() {
        guard !saving else { return }
        searchID = UUID()
        url = ""
        result = nil
        selected = []
        searching = false
        saved = 0
        error = nil
        notice = nil
        needLogin = false
    }

    func save() async {
        let list = items.filter { selected.contains($0.id) }
        saving = true
        saved = 0
        error = nil
        notice = nil
        defer { saving = false }
        do {
            for item in list {
                try await Downloader.save(item)
                saved += 1
            }
            notice = "saved \(itemCount(list.count)) to Photos"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() async {
        Session.clear()
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        loggedIn = false
    }
}

private func itemCount(_ n: Int) -> String { "\(n) \(n == 1 ? "item" : "items")" }

struct HomeView: View {
    @State private var model = HomeModel()
    @State private var showLogin = false
    @State private var previewItem: MediaItem?
    @FocusState private var linkFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private var allSelected: Bool { model.selected.count == model.items.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if model.result == nil && !model.searching {
                    introduction
                }
                prompt
                status

                if model.searching {
                    fetching
                } else if let r = model.result {
                    results(r)
                } else if model.error == nil {
                    guide
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .fontDesign(.monospaced)
        .foregroundStyle(Color.termFG)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.termBG.ignoresSafeArea())
        .background(KeyboardDismissArea())
        .safeAreaInset(edge: .bottom) {
            if model.result != nil {
                saveBar
            }
        }
        .sensoryFeedback(.success, trigger: model.notice)
        .sensoryFeedback(.selection, trigger: model.selected)
        .sheet(isPresented: $showLogin) {
            LoginView { model.loggedIn = true }
        }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreview(items: model.items, initialItem: item, selected: $model.selected)
        }
    }

    private var header: some View {
        HStack {
            MetallicLogo()
            Spacer()
            if model.loggedIn {
                Menu {
                    Button("log out", role: .destructive) { Task { await model.logout() } }
                } label: {
                    Text("[ account ]")
                        .foregroundStyle(Color.termGreen)
                        .frame(minHeight: 44)
                }
            } else {
                Button { showLogin = true } label: {
                    Text("[ login ]")
                        .foregroundStyle(Color.termIce)
                        .frame(minHeight: 44)
                }
            }
        }
        .font(.subheadline)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep what\ninspires you.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fontDesign(.rounded)
                .accessibilityIdentifier("homeTitle")
            Text("From Instagram to your Photos.")
                .font(.subheadline)
                .fontDesign(.default)
                .foregroundStyle(Color.termDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
    private var prompt: some View {
        HStack(spacing: 10) {
            Text("$").foregroundStyle(Color.termGreen).fontWeight(.bold)
            TextField("Instagram link", text: $model.url, prompt: Text("Paste an Instagram link").foregroundStyle(Color.termDim))
                .accessibilityIdentifier("linkField")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.search)
                .focused($linkFocused)
                .onSubmit {
                    linkFocused = false
                    Task { await model.find() }
                }
            if !model.url.isEmpty || model.result != nil || model.error != nil || model.searching {
                Button {
                    linkFocused = false
                    model.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.termDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear link and results")
                .accessibilityIdentifier("clearLink")
            }
            // PasteButton reads the clipboard without the iOS paste-permission prompt
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first else { return }
                Task { @MainActor in
                    guard !model.saving else { return }
                    linkFocused = false
                    model.url = s
                    await model.find()
                }
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Paste Instagram link")
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(.termIce)
        }
        .disabled(model.saving)
        .padding(.leading, 14)
        .padding(6)
        .background(Color.termSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.termLine))
    }

    @ViewBuilder private var status: some View {
        if let e = model.error {
            VStack(alignment: .leading, spacing: 8) {
                Text("error: \(e)").foregroundStyle(Color.termRed)
                if model.needLogin {
                    Button { showLogin = true } label: { Text("$ login").foregroundStyle(Color.termIce) }
                }
            }
            .font(.subheadline)
        } else if let n = model.notice {
            Text("ok: \(n)").font(.subheadline).foregroundStyle(Color.termGreen)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 22) {
                guideStep("link", title: "Copy a link", detail: "From any Instagram post or reel.")
                guideStep("photo.on.rectangle.angled", title: "Preview & choose", detail: "Tap to view. Tick to keep.")
                guideStep("square.and.arrow.down", title: "Save to Photos", detail: "Your favourites, on your iPhone.")
            }
            .padding(20)
            .background(Color.termSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.termLine))
            Text("iOS · No ads · Public posts need no login")
                .font(.caption)
                .foregroundStyle(Color.termDim)
        }
        .fontDesign(.default)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
    }

    private func guideStep(_ icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.termIce)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Color.termDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var fetching: some View {
        HStack(spacing: 6) {
            ProgressView().tint(.termIce)
            Text("fetching media…")
        }
        .font(.subheadline)
        .accessibilityLabel("Loading")
    }

    private func results(_ r: Resolved) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.user.map { "@\($0.username)" } ?? r.kind)
                    .font(.headline)
                Text("\(itemCount(r.items.count)) · tap photo to preview")
                    .font(.caption)
                    .foregroundStyle(Color.termDim)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(r.items.enumerated()), id: \.element.id) { i, item in
                    Tile(item: item, index: i, selected: model.selected.contains(item.id), preview: {
                        linkFocused = false
                        previewItem = item
                    }) {
                        model.selected.formSymmetricDifference([item.id])
                    }
                }
            }
            .disabled(model.saving)
        }
    }

    private var saveBar: some View {
        let n = model.selected.count
        let enabled = n > 0 && !model.saving
        let title = model.saving ? "Saving \(model.saved) of \(n)…"
            : n == 0 ? "Select items to save" : "Save \(itemCount(n)) to Photos"

        return VStack(spacing: 10) {
            if model.items.count > 1 {
                Button {
                    model.selected = allSelected ? [] : Set(model.items.map(\.id))
                } label: {
                    HStack(spacing: 10) {
                        Text(allSelected ? "[x]" : "[ ]")
                        Text(allSelected ? "deselect all" : "select all")
                        Spacer(minLength: 4)
                        Text("\(n)/\(model.items.count)")
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.termIce)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.termSurface, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.saving)
                .accessibilityValue("\(n) of \(model.items.count) selected")
                .accessibilityIdentifier("selectAll")
            }
            Button { Task { await model.save() } } label: {
                Label(title, systemImage: "square.and.arrow.down")
                    .fontWeight(.semibold)
                    .foregroundStyle(enabled ? Color.termInk : Color.termDim)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 12)
                    .background(enabled ? Color.termIce : Color.termLine, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier("saveMedia")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.termBG.opacity(0.96).ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(Color.termLine).frame(height: 1) }
    }
}

private struct MetallicLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lettering: some View {
        HStack(spacing: 0) {
            Text("~").foregroundStyle(Color.termGreen)
            Text("/IGSave")
                .foregroundStyle(Color.termIce)
        }
        .font(.system(.title3, design: .monospaced, weight: .bold))
    }

    var body: some View {
        lettering
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1 / 30,
                                                paused: ProcessInfo.processInfo.arguments.contains("--ui-testing"))) { context in
                            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.10), location: 0.25),
                                    .init(color: .white.opacity(0.85), location: 0.5),
                                    .init(color: .black.opacity(0.25), location: 0.65),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: geometry.size.width)
                                .offset(x: (phase * 3 - 1.5) * geometry.size.width)
                        }
                    }
                    .mask(lettering)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("IGSave")
    }
}

private struct KeyboardDismissArea: UIViewRepresentable {
    func makeUIView(context: Context) -> DismissView { DismissView() }
    func updateUIView(_ uiView: DismissView, context: Context) {}

    static func dismantleUIView(_ uiView: DismissView, coordinator: ()) {
        uiView.detach()
    }
    final class DismissView: UIView, UIGestureRecognizerDelegate {
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window?.addGestureRecognizer(tap)
        }

        func detach() { tap.view?.removeGestureRecognizer(tap) }

        @objc private func dismissKeyboard() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct Tile: View {
    let item: MediaItem
    let index: Int
    let selected: Bool
    let preview: () -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: preview) {
                Color.termLine.opacity(0.5)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .overlay {
                        MediaThumbnail(url: item.thumb ?? item.url, isVideo: item.isVideo)
                            .accessibilityIdentifier("thumbnail-\(index)")
                    }

                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: item.isVideo ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .padding(10)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.termLine))
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(item.isVideo ? "video" : "photo") \(index + 1)")
            .accessibilityIdentifier("preview-\(index)")
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(selected ? "[x]" : "[ ]")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(selected ? Color.termIce : Color.termDim)
                    Text("\(String(format: "%02d", index + 1)).\(item.isVideo ? "mp4" : "jpg")")
                        .font(.caption)
                        .foregroundStyle(Color.termDim)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? Color.termIce.opacity(0.08) : Color.termSurface,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(selected ? "Deselect" : "Select") item \(index + 1)")
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityIdentifier("select-\(index)")
        }
    }
}

private struct MediaThumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: isVideo ? "video" : "photo")
                    .foregroundStyle(Color.termDim)
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            let thumbnail = await ThumbnailStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = thumbnail
        }
    }
}
