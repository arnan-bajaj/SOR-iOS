import SwiftUI
import WebKit

/// A page of the team website inside the app, already signed in. The app hands the website its Google token
/// (window.sorAppToken), and the website signs in with it instead of showing Google's page, which Google
/// doesn't allow inside an app's browser view. The website hides its own tab bar here (html.in-app).
struct WebPageView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let path: String
    @State private var token: (idToken: String, accessToken: String)?
    @State private var ready = false
    @State private var loading = true

    var body: some View {
        ZStack {
            AppBackground()
            if ready {
                WebView(url: AppModel.site.appending(path: path), token: token, loading: $loading)
                    .ignoresSafeArea(edges: .bottom)
            }
            if loading { ProgressView() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: AppModel.site.appending(path: path)) { Image(systemName: "safari") }
                    .accessibilityLabel("Open in Safari")
            }
        }
        .task {
            token = await model.googleTokenForWeb()
            ready = true
        }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let token: (idToken: String, accessToken: String)?
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "SORTeamApp/1.0" // the website adds html.in-app for this
        config.websiteDataStore = .default() // keeps the website signed in between visits
        if let token, let json = try? JSONSerialization.data(withJSONObject: ["idToken": token.idToken, "accessToken": token.accessToken]),
           let s = String(data: json, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: "window.sorAppToken = \(s);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        #if DEBUG
        web.isInspectable = true
        #endif
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.loading = false }

        /// The website's own pages stay here; everything else (Slack, Zoom, Google Docs, Maps) opens in its app or Safari.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            let ours = url.host == AppModel.site.host || url.host == "frc6059-9e793.firebaseapp.com" || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data"
            if ours || action.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        /// target=_blank links
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if url.host == AppModel.site.host { webView.load(action.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }
    }
}
