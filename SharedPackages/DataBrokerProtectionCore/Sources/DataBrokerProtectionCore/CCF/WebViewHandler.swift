//
//  WebViewHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import WebKit
import PrivacyConfig
import BrowserServicesKit
import UserScript
import Common
import os.log

public protocol WebViewHandler: NSObject {
    func initializeWebView(showWebView: Bool) async
    func load(url: URL) async throws
    func takeSnaphost(path: String, fileName: String) async throws
    func saveHTML(path: String, fileName: String) async throws
    func waitForWebViewLoad() async throws
    func finish() async
    func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) async
    func evaluateJavaScript(_ javaScript: String) async throws
    func setCookies(_ cookies: [HTTPCookie]) async
}

@MainActor
public final class DataBrokerProtectionWebViewHandler: NSObject, WebViewHandler {
    private var activeContinuation: CheckedContinuation<Void, Error>?

    private let isFakeBroker: Bool
    private let executionConfig: BrokerJobExecutionConfig
    private let challengePixelDataBroker: String?
    private let challengePixelBrokerVersion: String?
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private(set) var webViewConfiguration: WKWebViewConfiguration?
    private var userContentController: DataBrokerUserContentController?

    private var webView: WebView?

#if os(macOS)
    private var urlObservation: NSKeyValueObservation?
    private var window: NSWindow?
    private var addressBarTextField: NSTextField?
    private var toolbar: NSToolbar?
    private var didDetectChallenge = false
    private var didReportChallengeClearance = false
    private var cloudflareChallengeTask: Task<Void, Never>?
    private var expectedBrokerURL: URL?
    private var isCloudflareChallengeResponse = false
    private var isAwaitingCloudflareDestination = false
    private let actionLogContext: PIRActionLogContext?
    private let cloudflareChallengeEventHandler: ((String) -> Void)?
#elseif os(iOS)
    private var window: UIWindow?
#endif

    private var timer: Timer?

    public init(privacyConfig: PrivacyConfigurationManaging,
                prefs: ContentScopeProperties,
                delegate: CCFCommunicationDelegate,
                isFakeBroker: Bool = false,
                executionConfig: BrokerJobExecutionConfig,
                challengePixelDataBroker: String? = nil,
                challengePixelBrokerVersion: String? = nil,
                shouldContinueActionHandler: @escaping () -> Bool,
                applicationNameForUserAgentProvider: () -> String?,
                contentBlocking: DBPWebViewContentBlocking? = nil,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil,
                actionLogContext: PIRActionLogContext? = nil,
                cloudflareChallengeEventHandler: ((String) -> Void)? = nil) throws {
        self.isFakeBroker = isFakeBroker
        self.executionConfig = executionConfig
        self.challengePixelDataBroker = challengePixelDataBroker
        self.challengePixelBrokerVersion = challengePixelBrokerVersion
        self.pixelHandler = pixelHandler
#if os(macOS)
        self.actionLogContext = actionLogContext
        self.cloudflareChallengeEventHandler = cloudflareChallengeEventHandler
#endif
        let configuration = WKWebViewConfiguration()
        try configuration.applyDataBrokerConfiguration(privacyConfig: privacyConfig,
                                                       prefs: prefs,
                                                       delegate: delegate,
                                                       executionConfig: executionConfig,
                                                       shouldContinueActionHandler: shouldContinueActionHandler,
                                                       contentBlocking: contentBlocking)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        if let applicationNameForUserAgent = applicationNameForUserAgentProvider() {
            configuration.applicationNameForUserAgent = applicationNameForUserAgent
        }

        self.webViewConfiguration = configuration

        let userContentController = configuration.userContentController as? DataBrokerUserContentController
        assert(userContentController != nil)
        self.userContentController = userContentController
    }

    public func initializeWebView(showWebView: Bool) async {
        guard let configuration = self.webViewConfiguration else {
            return
        }

        webView = WebView(frame: CGRect(origin: .zero, size: CGSize(width: 1024, height: 1024)), configuration: configuration)
        webView?.navigationDelegate = self

#if os(macOS)
        if showWebView {
            urlObservation = webView?.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
                let url = change.newValue ?? nil
                Task { @MainActor in
                    self?.updateAddressBar(with: url)
                }
            }

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window?.title = "Data Broker Protection"
            window?.toolbarStyle = .expanded
            let toolbar = makeToolbar()
            self.toolbar = toolbar
            window?.toolbar = toolbar

            window?.delegate = self
            window?.isReleasedWhenClosed = false
            window?.contentView = webView

            window?.makeKeyAndOrderFront(nil)
        } else if let webView {
            let panel = CloudflareOffscreenPanel(
                contentRect: NSRect(origin: .zero, size: webView.frame.size),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false)
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
            panel.backgroundColor = .white
            panel.acceptsMouseMovedEvents = true
            panel.ignoresMouseEvents = false
            panel.contentView = webView

            panel.setFrameOrigin(CloudflareOffscreenPanel.nextOrigin(for: webView.frame.size))
            panel.orderFrontRegardless()
            window = panel
        }
#elseif os(iOS)
        if showWebView {
            cleanupExistingPIRDebugWindow()

            if #available(iOS 16.4, *) {
                webView?.isInspectable = true
            }

            let viewController = UIViewController.init()
            viewController.view = webView
            let navigationController = UINavigationController(rootViewController: viewController)
            viewController.title = "PIR Debug Mode"

            if let currentWindowScene = UIApplication.shared.connectedScenes.first as?  UIWindowScene {
                window = UIWindow(windowScene: currentWindowScene)
                window?.rootViewController = navigationController
                window?.windowLevel = UIWindow.Level.alert
            } else {
                assertionFailure("Could not find window scene")
            }
        }
#endif

        installTimer()

        try? await load(url: URL(string: "\(WebViewSchemeHandler.dataBrokerProtectionScheme)://blank")!)
    }

    public func load(url: URL) async throws {
#if os(macOS)
        didDetectChallenge = false
        didReportChallengeClearance = false
        resetCloudflareChallengeState()
        expectedBrokerURL = url
#endif
        webView?.load(url)
        Logger.action.log("Loading URL: \(url.shortDescription)")
        try await waitForWebViewLoad()
    }

    public func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await webView?.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
    }

    public func finish() {
        Logger.action.log("WebViewHandler finished")
        webView?.stopLoading()
        userContentController?.cleanUpBeforeClosing()
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0)) {
            Logger.action.log("WKWebView data store deleted correctly")
        }

        stopTimer()

        webViewConfiguration = nil
        userContentController = nil
        webView?.navigationDelegate = nil
        webView = nil
#if os(macOS)
        cloudflareChallengeTask?.cancel()
        cloudflareChallengeTask = nil
        isCloudflareChallengeResponse = false
        isAwaitingCloudflareDestination = false
        urlObservation?.invalidate()
        urlObservation = nil
        window?.orderOut(nil)
        window = nil
#endif
    }

    deinit {
        Logger.action.log("WebViewHandler Deinit")
    }

    public func waitForWebViewLoad() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.activeContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
#if os(macOS)
                self.resetCloudflareChallengeState()
#endif
                self.resumeActiveContinuation(with: .failure(DataBrokerProtectionError.cancelled))
            }
        }
    }

    private func resumeActiveContinuation(with result: Result<Void, Error>) {
        let continuation = activeContinuation
        activeContinuation = nil
        continuation?.resume(with: result)
    }

    public func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) {
        Logger.action.log("Executing action: \(String(describing: action.actionType.rawValue), privacy: .public)")

        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.pushAction(
            method: .onActionReceived,
            webView: self.webView!,
            params: Params(state: ActionRequest(action: action, data: data))
        )
    }

    public func evaluateJavaScript(_ javaScript: String) async throws {
        try await webView?.evaluateJavaScript(javaScript) as Void?
    }

    public func takeSnaphost(path: String, fileName: String) async throws {
        guard let height: CGFloat = try await webView?.evaluateJavaScript("document.body.scrollHeight") else { return }

        webView?.frame = CGRect(origin: .zero, size: CGSize(width: 1024, height: height))
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: webView?.frame.size.width ?? 0.0, height: height)

#if os(macOS)
        if let image = try await webView?.takeSnapshot(configuration: configuration) {
            saveToDisk(image: image, path: path, fileName: fileName)
        }
#endif
    }

    public func saveHTML(path: String, fileName: String) async throws {
        guard let htmlString: String = try await webView?.evaluateJavaScript("document.documentElement.outerHTML") else { return }
        let fileManager = FileManager.default

        do {
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            }

            let fileURL = URL(fileURLWithPath: "\(path)/\(fileName)")
            try htmlString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("HTML content saved to file: \(fileURL)")
        } catch {
            Logger.action.error("Error writing HTML content to file: \(error)")
        }
    }

#if os(macOS)
    private func saveToDisk(image: NSImage, path: String, fileName: String) {
        guard let tiffData = image.tiffRepresentation else {
            // Handle the case where tiff representation is not available
            return
        }

        // Create a bitmap representation from the tiff data
        guard let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            // Handle the case where bitmap representation cannot be created
            return
        }

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: path) {
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating folder: \(error)")
            }
        }

        if let pngData = bitmapImageRep.representation(using: .png, properties: [:]) {
            // Save the PNG data to a file
            do {
                let fileURL = URL(fileURLWithPath: "\(path)/\(fileName)")
                try pngData.write(to: fileURL)
            } catch {
                print("Error writing PNG: \(error)")
            }
        } else {
            print("Error png data was not respresented")
        }
    }
#endif

    /// Workaround for stuck scans
    /// https://app.asana.com/0/0/1208502720748038/1208596554608118/f

    private func installTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task {
#if os(macOS)
                guard !self.isCloudflareChallengeResponse else { return }
#endif
                try await self.webView?.evaluateJavaScript("1+1") as Void?
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

#if os(iOS)
    private func cleanupExistingPIRDebugWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        for existingWindow in windowScene.windows {
            if let navController = existingWindow.rootViewController as? UINavigationController,
               let title = navController.topViewController?.title,
               title.hasPrefix("PIR Debug Mode") {
                existingWindow.isHidden = true
                existingWindow.rootViewController = nil
                break
            }
        }
    }
#endif

}

#if os(macOS)
private extension DataBrokerProtectionWebViewHandler {
    func updateCloudflareChallengeState(isChallenge: Bool, responseURL: URL?, statusCode: Int) {
        isCloudflareChallengeResponse = isChallenge
        if isChallenge {
            guard !isAwaitingCloudflareDestination else { return }
            isAwaitingCloudflareDestination = true
            reportCloudflareChallengeEvent("Detected: main response has cf-mitigated=challenge; HTTP \(statusCode)")
            startCloudflareChallengeSolver()
            return
        }

        guard isAwaitingCloudflareDestination else { return }
        guard isExpectedBrokerDestination(responseURL) else {
            Logger.action.log("Cloudflare challenge: non-challenge response did not reach the expected broker host")
            return
        }

        isAwaitingCloudflareDestination = false
        cloudflareChallengeTask?.cancel()
        cloudflareChallengeTask = nil
        reportCloudflareChallengeEvent("Solved challenge; expected broker destination reached")
        logCloudflareClearanceCookie()
    }

    func startCloudflareChallengeSolver() {
        cloudflareChallengeTask?.cancel()
        cloudflareChallengeTask = Task { [weak self] in
            await self?.solveCloudflareChallenge()
        }
    }

    func solveCloudflareChallenge() async {
        guard let webView else { return }
        let deadline = Date().addingTimeInterval(45)
        var nextSnapshotAttempt = Date.distantPast
        var didClick = false

        try? await Task.sleep(nanoseconds: 2_200_000_000)
        while isAwaitingCloudflareDestination, Date() < deadline, !Task.isCancelled {
            guard isCloudflareChallengeResponse else {
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }

            if !didClick, Date() >= nextSnapshotAttempt {
                nextSnapshotAttempt = Date().addingTimeInterval(2)
                if let point = await stableSnapshotCheckboxPoint(in: webView) {
                    _ = window?.makeFirstResponder(webView)
                    let result = await CloudflareChallengeClick.checkbox(at: point, in: webView)
                    reportCloudflareChallengeEvent("Sent snapshot checkbox click; \(result)")
                    didClick = true
                }
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard isAwaitingCloudflareDestination, !Task.isCancelled else { return }
        isCloudflareChallengeResponse = false
        isAwaitingCloudflareDestination = false
        reportCloudflareChallengeEvent(
            "Failed challenge; expected broker destination did not arrive before the 45-second deadline",
            isError: true)
        resumeActiveContinuation(with: .failure(DataBrokerProtectionError.unknown("Cloudflare challenge did not reach the broker destination")))
    }

    func stableSnapshotCheckboxPoint(in webView: WKWebView) async -> NSPoint? {
        guard let firstImage = await challengeSnapshot(of: webView), isCloudflareChallengeResponse else {
            Logger.action.log("Cloudflare challenge: first snapshot failed")
            return nil
        }
        let cssSize = webView.bounds.size
        let firstBox = CloudflareWidgetVision.find(in: firstImage, cssSize: cssSize)
        let firstHasChallengeText = CloudflareWidgetVision.containsChallengeText(in: firstImage)

        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let secondImage = await challengeSnapshot(of: webView), isCloudflareChallengeResponse else {
            Logger.action.log("Cloudflare challenge: second snapshot failed")
            return nil
        }
        let secondBox = CloudflareWidgetVision.find(in: secondImage, cssSize: cssSize)
        let secondHasChallengeText = CloudflareWidgetVision.containsChallengeText(in: secondImage)

        guard firstHasChallengeText || secondHasChallengeText else {
            Logger.action.log("Cloudflare challenge: snapshot rejected because challenge text was absent")
            return nil
        }
        guard let firstBox, let secondBox, firstBox.isStable(comparedTo: secondBox) else {
            Logger.action.log("Cloudflare challenge: snapshot rejected because the widget box was not stable")
            return nil
        }
        Logger.action.log("Cloudflare challenge: stable snapshot widget found")
        return secondBox.checkboxPoint
    }

    func challengeSnapshot(of webView: WKWebView) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let request = CloudflareSnapshotRequest(continuation: continuation)
            webView.takeSnapshot(with: nil) { image, _ in
                Task { @MainActor in
                    request.finish(with: image)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                request.finish(with: nil)
            }
        }
    }

    func isExpectedBrokerDestination(_ url: URL?) -> Bool {
        guard let expectedHost = normalizedHost(expectedBrokerURL?.host),
              let responseHost = normalizedHost(url?.host) else { return false }
        return responseHost == expectedHost || responseHost.hasSuffix(".\(expectedHost)") || expectedHost.hasSuffix(".\(responseHost)")
    }

    func normalizedHost(_ host: String?) -> String? {
        guard let host else { return nil }
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)).lowercased() : host.lowercased()
    }

    func logCloudflareClearanceCookie() {
        guard let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let hasClearance = cookies.contains { $0.name.caseInsensitiveCompare("cf_clearance") == .orderedSame }
            Task { @MainActor in
                self?.reportCloudflareChallengeEvent("Supporting evidence: cf_clearance=\(hasClearance)")
            }
        }
    }

    func reportCloudflareChallengeEvent(_ message: String, isError: Bool = false) {
        let logMessage = "Cloudflare challenge: \(message)"
        if let actionLogContext {
            if isError {
                Logger.action.error(actionLogContext, message: logMessage)
            } else {
                Logger.action.log(actionLogContext, message: logMessage)
            }
        } else if isError {
            Logger.action.error("\(logMessage, privacy: .public)")
        } else {
            Logger.action.log("\(logMessage, privacy: .public)")
        }
        cloudflareChallengeEventHandler?(message)
    }

    func resetCloudflareChallengeState() {
        cloudflareChallengeTask?.cancel()
        cloudflareChallengeTask = nil
        isCloudflareChallengeResponse = false
        isAwaitingCloudflareDestination = false
    }

    @objc func copyURLFromAddressBar() {
        let urlString = addressBarTextField?.stringValue ?? ""
        guard !urlString.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PIRDebugToolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    func makeAddressBarView() -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 22))
        let addressField = NSTextField(labelWithString: "")
        addressField.isEditable = false
        addressField.isSelectable = true
        addressField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.cell?.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressBarTextField = addressField
        updateAddressBar(with: webView?.url)

        let copyButton = NSButton(title: "Copy URL", target: self, action: #selector(copyURLFromAddressBar))
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let addressRow = NSStackView(views: [addressField, copyButton])
        addressRow.orientation = .horizontal
        addressRow.spacing = 8
        addressRow.alignment = .centerY
        addressRow.distribution = .fill
        addressRow.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(addressRow)
        NSLayoutConstraint.activate([
            addressRow.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            addressRow.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            addressRow.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 0),
            addressRow.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 0)
        ])

        return containerView
    }

    func updateAddressBar(with url: URL?) {
        addressBarTextField?.stringValue = url?.absoluteString ?? ""
    }
}

extension DataBrokerProtectionWebViewHandler: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

extension DataBrokerProtectionWebViewHandler: NSToolbarDelegate {
    private enum ToolbarItemIdentifier {
        static let addressBar = NSToolbarItem.Identifier("PIRDebugToolbar.AddressBar")
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItemIdentifier.addressBar, .flexibleSpace]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItemIdentifier.addressBar, .flexibleSpace]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier
                        itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarItemIdentifier.addressBar else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let view = makeAddressBarView()
        item.view = view
        item.minSize = view.fittingSize
        item.maxSize = NSSize(width: 2000, height: view.fittingSize.height)
        return item
    }
}
#endif

extension DataBrokerProtectionWebViewHandler: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.action.log("WebViewHandler didFinish")
#if os(macOS)
        updateAddressBar(with: webView.url)
        guard !isAwaitingCloudflareDestination else {
            Logger.action.log("Cloudflare challenge: holding the broker load continuation")
            return
        }
#endif

        resumeActiveContinuation(with: .success(()))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFail: \(error.localizedDescription, privacy: .public)")
#if os(macOS)
        resetCloudflareChallengeState()
#endif
        resumeActiveContinuation(with: .failure(error))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFailProvisionalNavigation: \(error.localizedDescription, privacy: .public)")
#if os(macOS)
        resetCloudflareChallengeState()
#endif
        resumeActiveContinuation(with: .failure(error))
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if os(macOS)
        updateAddressBar(with: webView.url)
#endif
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
#if os(macOS)
        recordChallengeDetectionIfPresent(in: navigationResponse.response, isForMainFrame: navigationResponse.isForMainFrame)
        if navigationResponse.isForMainFrame {
            observeChallengeClearance(in: webView)
        }
#endif

        guard let response = navigationResponse.response as? HTTPURLResponse else {
            // if there's no http status code to act on, exit and allow navigation
            return .allow
        }
        let statusCode = response.statusCode

#if os(macOS)
        if navigationResponse.isForMainFrame {
            let mitigatedHeader = response.value(forHTTPHeaderField: "cf-mitigated")
            let isChallenge = mitigatedHeader?.caseInsensitiveCompare("challenge") == .orderedSame
            updateCloudflareChallengeState(isChallenge: isChallenge, responseURL: response.url, statusCode: statusCode)
        }
#endif

        if statusCode == 403 {
            Logger.action.log("WebViewHandler failed with status code: \(String(describing: statusCode), privacy: .public)")
            Logger.action.log("WebViewHandler continuing despite error")
        } else if statusCode >= 400 {
            Logger.action.log("WebViewHandler failed with status code: \(String(describing: statusCode), privacy: .public)")
            resumeActiveContinuation(with: .failure(DataBrokerProtectionError.httpError(code: statusCode)))
        }

        return .allow
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.action.error("WebViewHandler web content process terminated")
#if os(macOS)
        resetCloudflareChallengeState()
#endif
        resumeActiveContinuation(with: .failure(DataBrokerProtectionError.webContentProcessTerminated))
    }

    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !isFakeBroker {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
                    challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {

            let fakeBrokerCredentials = HTTPUtils.fetchFakeBrokerCredentials()
            let credential = URLCredential(user: fakeBrokerCredentials.username, password: fakeBrokerCredentials.password, persistence: .none)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

#if os(macOS)
extension DataBrokerProtectionWebViewHandler {

    func recordChallengeDetectionIfPresent(in response: URLResponse, isForMainFrame: Bool) {
        guard isForMainFrame,
              let response = response as? HTTPURLResponse,
              response.value(forHTTPHeaderField: "cf-mitigated")?.caseInsensitiveCompare("challenge") == .orderedSame else {
            return
        }

        didDetectChallenge = true

        guard let challengePixelDataBroker, let challengePixelBrokerVersion else { return }
        pixelHandler?.fire(.mainFrameChallengeDetected(
            dataBroker: challengePixelDataBroker,
            brokerVersion: challengePixelBrokerVersion))
    }

    func recordChallengeClearanceIfPresent(in cookies: [HTTPCookie]) {
        guard didDetectChallenge,
              !didReportChallengeClearance,
              cookies.contains(where: { $0.name.caseInsensitiveCompare("cf_clearance") == .orderedSame }) else {
            return
        }

        guard let challengePixelDataBroker, let challengePixelBrokerVersion else { return }
        didReportChallengeClearance = true
        pixelHandler?.fire(.challengeClearanceObserved(
            dataBroker: challengePixelDataBroker,
            brokerVersion: challengePixelBrokerVersion))
    }

    private func observeChallengeClearance(in webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                self?.recordChallengeClearanceIfPresent(in: cookies)
            }
        }
    }
}
#endif

private class WebView: WKWebView {

    deinit {
        configuration.userContentController.removeAllUserScripts()
        Logger.action.log("DBP WebView Deinit")
    }
}
