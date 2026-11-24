import SwiftUI
import WebKit
import UniformTypeIdentifiers

enum ShineConfig {
    /// The deployed Shine site. This is the only place the origin is written
    /// down, so pointing the app somewhere else is a one line change.
    static let origin = URL(string: "https://shineaimobile.pages.dev/")!
}

struct ShineWebView: UIViewRepresentable {
    @Binding var isRefreshing: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // The default store is persistent, which is what keeps conversation
        // history, provider keys and the theme toggle across launches - the site
        // keeps all of it in localStorage.
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        // Black rather than the default white, so there is no flash of the wrong
        // colour while the first page paints.
        webView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.attach(to: webView)
        webView.scrollView.refreshControl = context.coordinator.refreshControl

        webView.load(URLRequest(url: ShineConfig.origin))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Deliberately does not touch refreshControl. Ending the spinner here
        // would cancel it the instant the pull set isRefreshing, because that
        // binding change is what triggers this call in the first place. The
        // navigation callbacks own the spinner's lifecycle instead.
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: ShineWebView
        private(set) var refreshControl = UIRefreshControl()
        private weak var webView: WKWebView?

        /// Where each in-flight download is being written. WKDownload never hands
        /// the finished file back, so the path chosen up front is recorded here.
        private var destinations: [ObjectIdentifier: URL] = [:]

        private var reloadObserver: NSObjectProtocol?

        init(_ parent: ShineWebView) {
            self.parent = parent
            super.init()
            refreshControl.tintColor = .white
            refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            // "Retry" in the error banner cannot reach into SwiftUI's state from
            // the button itself, so it posts this instead.
            reloadObserver = NotificationCenter.default.addObserver(
                forName: .shineReload, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.parent.loadError = nil
                self.webView?.reload()
            }
        }

        deinit {
            if let reloadObserver {
                NotificationCenter.default.removeObserver(reloadObserver)
            }
        }

        // MARK: - Pull to refresh

        @objc private func handleRefresh() {
            parent.isRefreshing = true
            webView?.reload()
        }

        private func finishRefresh() {
            refreshControl.endRefreshing()
            if parent.isRefreshing { parent.isRefreshing = false }
        }

        // MARK: - Navigation

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loadError = nil
            finishRefresh()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loadError = error.localizedDescription
            finishRefresh()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            // A cancelled provisional load is what a normal redirect looks like,
            // not a failure worth showing the user.
            guard nsError.code != NSURLErrorCancelled else { return }
            parent.loadError = error.localizedDescription
            finishRefresh()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow)
                return
            }

            // The site puts a download button on every code block, and also
            // generates images. Let WebKit turn those into real downloads.
            if action.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            // target="_blank" gives targetFrame == nil. Same-origin links load in
            // place; anything else belongs in Safari rather than a web view that
            // has no address bar to show where it is.
            if action.targetFrame == nil, url.scheme != "about" {
                if url.host == ShineConfig.origin.host {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Content the web view cannot render - a stray PDF, say - is a
            // download rather than a blank screen.
            decisionHandler(response.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, didTerminateWithError error: Error) {
            parent.loadError = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The site is a long lived single page app; a killed content process
            // is nearly always recoverable with a plain reload.
            webView.reload()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Returning nil stops target="_blank" from opening a second, blank
            // web view on top of the app.
            nil
        }

        // MARK: - Downloads

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let destination = ShineDownloads.destination(for: suggestedFilename)
            destinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            ShineDownloads.share(url)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            destinations.removeValue(forKey: ObjectIdentifier(download))
            ShineDownloads.reportFailure(error)
        }

        // MARK: - JavaScript dialogs

        // The site uses window.confirm for the "Control PC" approval prompts.
        // WKWebView silently drops those calls unless they are handled here,
        // which would leave the approval hanging with no way to answer it.

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let host = UIViewController.topMost else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: "Shine", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            host.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let host = UIViewController.topMost else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: "Shine", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completionHandler(true) })
            host.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard let host = UIViewController.topMost else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(title: "Shine", message: prompt, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = defaultText
                field.autocapitalizationType = .sentences
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            host.present(alert, animated: true)
        }

        // MARK: - Microphone and camera

        // This is what makes Shine Live work. Without it, getUserMedia() is
        // refused outright and the site gets no microphone and no camera - the
        // usage strings in Info.plist alone are never enough. Granting here is
        // what causes iOS to raise the real system permission prompt.
        //
        // Attachments need no code of their own: WebKit presents the system
        // upload panel, which offers Take Photo, Photo Library and Browse on
        // every iOS version this app supports.
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}

extension UIViewController {
    /// The view controller currently on screen, for presenting alerts and pickers.
    static var topMost: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
