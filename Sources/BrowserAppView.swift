import Combine
import SwiftUI
import WebKit

@MainActor
final class BrowserEngine: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var addressText = ""
    @Published var title = "Browser"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published private(set) var pageText = ""
    @Published private(set) var hasLoadedPage = false

    private var cancellables = Set<AnyCancellable>()

    var insightContext: String? {
        guard hasLoadedPage else { return nil }
        var parts = ["The user has a live browser page open."]
        if !title.isEmpty {
            parts.append("Title: \(title)")
        }
        if !addressText.isEmpty {
            parts.append("URL: \(addressText)")
        }
        let clip = String(pageText.prefix(3500)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !clip.isEmpty {
            parts.append("Visible page text:\n\(clip)")
        }
        return parts.joined(separator: "\n")
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .black
        webView.isOpaque = false
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        bindWebView()
    }

    func loadHomeIfNeeded() {
        guard !hasLoadedPage, webView.url == nil else { return }
        load(resolvedURL(from: "https://www.google.com"))
    }

    func submitAddress(_ raw: String) {
        load(resolvedURL(from: raw))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    private func load(_ url: URL) {
        addressText = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    private func bindWebView() {
        webView.publisher(for: \.canGoBack)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canGoBack = value }
            .store(in: &cancellables)
        webView.publisher(for: \.canGoForward)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canGoForward = value }
            .store(in: &cancellables)
        webView.publisher(for: \.isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isLoading = value }
            .store(in: &cancellables)
        webView.publisher(for: \.title)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                let next = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !next.isEmpty {
                    self?.title = next
                }
            }
            .store(in: &cancellables)
        webView.publisher(for: \.url)
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                guard let url else { return }
                self?.addressText = url.absoluteString
            }
            .store(in: &cancellables)
    }

    private func resolvedURL(from raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return URL(string: "https://www.google.com")!
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme == "http" || scheme == "https" {
            return url
        }
        let looksLikeDomain = trimmed.contains(".") && !trimmed.contains(" ")
        if looksLikeDomain {
            return URL(string: "https://\(trimmed)") ?? URL(string: "https://www.google.com")!
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url ?? URL(string: "https://www.google.com")!
    }

    private func capturePageText() {
        let script = "(document.body && document.body.innerText) ? document.body.innerText : ''"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            let text = (result as? String ?? "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.pageText = text
            }
        }
    }
}

extension BrowserEngine: WKNavigationDelegate, WKUIDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.hasLoadedPage = true
            self.isLoading = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.hasLoadedPage = true
            self.isLoading = false
            if let url = self.webView.url {
                self.addressText = url.absoluteString
            }
            self.capturePageText()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            Task { @MainActor in
                self.webView.load(URLRequest(url: url))
            }
        }
        return nil
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserAppView: View {
    @ObservedObject var engine: BrowserEngine
    @Environment(\.dismiss) private var dismiss
    @State private var addressField = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("Close") {
                    Keyboard.dismiss()
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

                Button {
                    engine.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(!engine.canGoBack)
                .foregroundStyle(.white.opacity(engine.canGoBack ? 0.95 : 0.28))

                Button {
                    engine.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(!engine.canGoForward)
                .foregroundStyle(.white.opacity(engine.canGoForward ? 0.95 : 0.28))

                TextField("Search or enter website", text: $addressField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        Keyboard.dismiss()
                        engine.submitAddress(addressField)
                    }

                Button {
                    Keyboard.dismiss()
                    if addressField.trimmingCharacters(in: .whitespacesAndNewlines) != engine.addressText {
                        engine.submitAddress(addressField)
                    } else {
                        engine.reloadOrStop()
                    }
                } label: {
                    Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))

            ZStack(alignment: .top) {
                BrowserWebView(webView: engine.webView)
                    .ignoresSafeArea(edges: .bottom)

                if engine.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.18))
                }
            }
        }
        .background(Color.black.ignoresSafeArea(.container))
        .keyboardDoneButton()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            engine.loadHomeIfNeeded()
            addressField = engine.addressText.isEmpty ? "https://www.google.com" : engine.addressText
        }
        .onChange(of: engine.addressText) { _, newValue in
            addressField = newValue
        }
        }
    }
}
