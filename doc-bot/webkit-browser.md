---
alwaysApply: false
title: "WebKit & Browser Development Guidelines"
description: "WebKit and browser-specific development guidelines including WebView configuration, tab management, and JavaScript bridge patterns"
keywords: ["WebKit", "WKWebView", "browser", "tab management", "JavaScript bridge", "navigation", "downloads", "cookies", "security"]
---

# WebKit & Browser Development Guidelines

## WebView Configuration

### Basic WebView Setup
```swift
import WebKit

class BrowserWebView {
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        
        // Enable JavaScript
        configuration.preferences.javaScriptEnabled = true
        
        // Set user agent
        configuration.applicationNameForUserAgent = UserAgentManager.shared.userAgent
        
        // Configure content blockers
        configuration.userContentController = makeUserContentController()
        
        // Enable developer extras in debug
        #if DEBUG
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        
        return webView
    }()
}
```

### User Scripts Management
```swift
private func makeUserContentController() -> WKUserContentController {
    let controller = WKUserContentController()
    
    // Add content blocking scripts
    let contentBlockingScript = WKUserScript(
        source: ContentBlockingUserScript.source,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
    controller.addUserScript(contentBlockingScript)
    
    // Add message handlers
    controller.add(self, name: "duckduckgo")
    
    return controller
}
```

## Tab Management

### Tab Model
```swift
class Tab: NSObject {
    let id = UUID()
    private(set) var url: URL?
    private(set) var title: String?
    private(set) var favicon: UIImage?
    
    weak var webView: WKWebView?
    weak var delegate: TabDelegate?
    
    private var observations: Set<NSKeyValueObservation> = []
    
    init(url: URL? = nil) {
        self.url = url
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let webView = WKWebView(frame: .zero, configuration: TabManager.shared.configuration)
        self.webView = webView
        
        // Observe properties
        observations.insert(
            webView.observe(\.url) { [weak self] _, _ in
                self?.urlDidChange()
            }
        )
        
        observations.insert(
            webView.observe(\.title) { [weak self] webView, _ in
                self?.title = webView.title
                self?.delegate?.tab(self!, didUpdateTitle: webView.title)
            }
        )
        
        observations.insert(
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                self?.delegate?.tab(self!, didUpdateProgress: webView.estimatedProgress)
            }
        )
    }
}
```

### Tab Lifecycle
```swift
extension Tab {
    func load(url: URL) {
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stop() {
        webView?.stopLoading()
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func close() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }
}
```

## Navigation Handling

### Navigation Delegate
```swift
extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        
        // Handle special URLs
        if let url = url, URLSchemeHandler.shared.canHandle(url) {
            URLSchemeHandler.shared.handle(url)
            return .cancel
        }
        
        // Apply content blocking
        if contentBlocker.shouldBlock(url) {
            return .cancel
        }
        
        // Check for downloads
        if shouldDownload(navigationAction) {
            startDownload(from: navigationAction.request)
            return .cancel
        }
        
        return .allow
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateProgressBar(animated: true)
        updateNavigationButtons()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideProgressBar()
        captureHistory()
        updateFavicon()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
}
```

## JavaScript Bridge

### Message Handling
```swift
extension BrowserViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        
        switch message.name {
        case "duckduckgo":
            handleDuckDuckGoMessage(dict)
        case "autofill":
            handleAutofillMessage(dict)
        case "tracker":
            handleTrackerMessage(dict)
        default:
            break
        }
    }
    
    private func handleDuckDuckGoMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        
        switch action {
        case "openSettings":
            presentSettings()
        case "reportBrokenSite":
            presentBrokenSiteReport()
        default:
            break
        }
    }
}
```

### JavaScript Injection
```swift
extension WKWebView {
    func evaluateJavaScriptSafely(_ script: String) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    func injectPrivacyProtection() async {
        let script = """
        (function() {
            // Override fingerprinting methods
            const originalCanvas = HTMLCanvasElement.prototype.toDataURL;
            HTMLCanvasElement.prototype.toDataURL = function() {
                return "";
            };
            
            // Block tracking pixels
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.tagName === 'IMG' && isTrackingPixel(node.src)) {
                            node.remove();
                        }
                    });
                });
            });
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
        
        try? await evaluateJavaScriptSafely(script)
    }
}
```

## Cookie Management

### Cookie Handling
```swift
extension BrowserViewController {
    func clearCookies(completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = Set([WKWebsiteDataTypeCookies])
        
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let fireproofedDomains = FireproofingManager.shared.fireproofedDomains
            
            let recordsToDelete = records.filter { record in
                !fireproofedDomains.contains(where: { record.displayName.contains($0) })
            }
            
            dataStore.removeData(ofTypes: dataTypes, for: recordsToDelete) {
                completion()
            }
        }
    }
}
```

## Download Management

### Download Delegate
```swift
extension BrowserViewController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsURL.appendingPathComponent(suggestedFilename)
        
        // Check if file exists and generate unique name if needed
        return FileManager.default.uniqueURL(for: destinationURL)
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // Handle download failure
        if let resumeData = resumeData {
            // Store resume data for later
            DownloadManager.shared.storeResumeData(resumeData, for: download)
        }
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        // Handle successful download
        DownloadManager.shared.completeDownload(download)
    }
}
```

## Performance Optimization

### Memory Management
```swift
class TabManager {
    private let maxInMemoryTabs = 5
    private var tabs: [Tab] = []
    
    func optimizeMemory() {
        let activeTabs = tabs.filter { $0.isActive }
        let inactiveTabs = tabs.filter { !$0.isActive }
            .sorted { $0.lastAccessDate < $1.lastAccessDate }
        
        // Suspend inactive tabs if we have too many in memory
        if activeTabs.count + inactiveTabs.count > maxInMemoryTabs {
            let tabsToSuspend = inactiveTabs.prefix(inactiveTabs.count - (maxInMemoryTabs - activeTabs.count))
            tabsToSuspend.forEach { $0.suspend() }
        }
    }
}

extension Tab {
    func suspend() {
        // Take snapshot
        webView?.takeSnapshot(with: nil) { [weak self] image, error in
            self?.snapshot = image
            self?.webView?.removeFromSuperview()
            self?.webView = nil
        }
    }
    
    func resume() {
        guard webView == nil else { return }
        setupWebView()
        if let url = url {
            load(url: url)
        }
    }
}
```

## Security Considerations

### Certificate Validation
```swift
extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        
        // Perform certificate pinning for DuckDuckGo domains
        if CertificatePinning.shared.shouldPin(host: challenge.protectionSpace.host) {
            do {
                try CertificatePinning.shared.validate(serverTrust, host: challenge.protectionSpace.host)
                let credential = URLCredential(trust: serverTrust)
                return (.useCredential, credential)
            } catch {
                return (.cancelAuthenticationChallenge, nil)
            }
        }
        
        return (.performDefaultHandling, nil)
    }
}
```