import SwiftUI
import WebKit

struct LoginView: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView(onDone: {
                onDone()
                dismiss()
            })
            .navigationTitle("Log in to Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct LoginWebView: UIViewRepresentable {
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onDone: () -> Void
        private var finished = false

        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            // httpOnly sessionid is only readable through the native cookie store
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [self] cookies in
                let ig = cookies.filter { $0.domain.hasSuffix("instagram.com") }
                guard !finished, ig.contains(where: { $0.name == "sessionid" }) else { return }
                finished = true
                Session.set(ig.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
                onDone()
            }
        }
    }
}
