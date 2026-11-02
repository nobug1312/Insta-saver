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

    var items: [MediaItem] { result?.items ?? [] }

    func find() async {
        guard let link = IGLink(url) else { error = "that doesn't look like an Instagram link"; return }
        searching = true
        error = nil
        notice = nil
        needLogin = false
        result = nil
        defer { searching = false }
        do {
            let r = try await IGClient.resolve(link)
            result = r
            selected = Set(r.items.map(\.id))
        } catch {
            if case IGError.loginRequired = error { needLogin = true }
            self.error = error.localizedDescription
        }
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
    private var allSelected: Bool { model.selected.count == model.items.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
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
        .safeAreaInset(edge: .bottom) { if model.result != nil { saveBar } }
        .sensoryFeedback(.success, trigger: model.notice)
        .sensoryFeedback(.selection, trigger: model.selected)
        .sheet(isPresented: $showLogin) {
            LoginView { model.loggedIn = true }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 0) {
                Text("~/").foregroundStyle(Color.termDim)
                Text("insta-saver").foregroundStyle(Color.termIce)
            }
            .font(.title3.bold())
            Spacer()
            if model.loggedIn {
                Menu {
                    Button("log out", role: .destructive) { Task { await model.logout() } }
                } label: {
                    Text("account").foregroundStyle(Color.termGreen)
                }
            } else {
                Button { showLogin = true } label: { Text("[ login ]").foregroundStyle(Color.termIce) }
            }
        }
        .font(.subheadline)
    }

    private var prompt: some View {
        HStack(spacing: 10) {
            Text("$").foregroundStyle(Color.termGreen).fontWeight(.bold)
            TextField("", text: $model.url, prompt: Text("paste an instagram link").foregroundStyle(Color.termDim))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.search)
                .onSubmit { Task { await model.find() } }
            // PasteButton reads the clipboard without the iOS paste-permission prompt
            PasteButton(payloadType: String.self) { strings in
                guard let s = strings.first else { return }
                Task { @MainActor in
                    model.url = s
                    await model.find()
                }
            }
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(.termIce)
        }
        .padding(.leading, 14)
        .padding(6)
        .background(Color.termSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.termLine))
    }

    @ViewBuilder private var status: some View {
        if let e = model.error {
            VStack(alignment: .leading, spacing: 8) {
                Text("error: \(e)").foregroundStyle(Color.termRed)
                if model.needLogin && !model.loggedIn {
                    Button { showLogin = true } label: { Text("$ login").foregroundStyle(Color.termIce) }
                }
            }
            .font(.subheadline)
        } else if let n = model.notice {
            Text("ok: \(n)").font(.subheadline).foregroundStyle(Color.termGreen)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("# how it works").foregroundStyle(Color.termDim)
            Text("1. in Instagram tap ••• or Share")
            Text("2. choose \"Copy link\"")
            Text("3. come back here and tap Paste")
            Text("# private accounts and stories need login").foregroundStyle(Color.termDim).padding(.top, 8)
        }
        .font(.subheadline)
    }

    private var fetching: some View {
        HStack(spacing: 6) {
            Text("fetching")
            Text("█").foregroundStyle(Color.termIce)
        }
        .font(.subheadline)
        .accessibilityLabel("Loading")
    }

    private func results(_ r: Resolved) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(r.user.map { "@\($0.username)" } ?? "-")  \(r.kind.lowercased())  \(itemCount(r.items.count))")
                    .foregroundStyle(Color.termDim)
                Spacer()
                if r.items.count > 1 {
                    Button { model.selected = allSelected ? [] : Set(model.items.map(\.id)) } label: {
                        Text(allSelected ? "[ none ]" : "[ all ]").foregroundStyle(Color.termIce)
                    }
                }
            }
            .font(.footnote)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(r.items.enumerated()), id: \.element.id) { i, item in
                    Tile(item: item, index: i, selected: model.selected.contains(item.id)) {
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
        let w = 12
        let filled = n == 0 ? 0 : model.saved * w / n
        let bar = "[" + String(repeating: "#", count: filled) + String(repeating: "-", count: w - filled) + "]"
        let title = model.saving ? "saving \(bar) \(model.saved)/\(n)"
            : n == 0 ? "$ select items" : "$ save \(itemCount(n))"

        return Button { Task { await model.save() } } label: {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(enabled ? Color.termInk : Color.termDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Color.termIce : Color.termLine, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.termBG.opacity(0.96).ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(Color.termLine).frame(height: 1) }
    }
}

private struct Tile: View {
    let item: MediaItem
    let index: Int
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                Color.termLine.opacity(0.5)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: item.thumb) { $0.resizable().scaledToFill() } placeholder: { EmptyView() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(selected ? 1 : 0.55)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.termIce : Color.termLine, lineWidth: selected ? 2 : 1))
                Text("\(selected ? "[x]" : "[ ]") \(String(format: "%02d", index + 1)).\(item.isVideo ? "mp4" : "jpg")")
                    .font(.caption)
                    .foregroundStyle(selected ? Color.termFG : Color.termDim)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isVideo ? "Video \(index + 1)" : "Photo \(index + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
