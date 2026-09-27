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
    private var challengeTask: Task<Void, Never>?
    private var challengePanel: ChallengeOffscreenPanel?
    private var expectedBrokerURL: URL?
    private var isChallengeResponse = false
    private var isAwaitingChallengeDestination = false
    private var didClickChallenge = false
    private let actionLogContext: PIRActionLogContext?
    private let challengeEventHandler: ((String) -> Void)?
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
                challengeEventHandler: ((String) -> Void)? = nil) throws {
        self.isFakeBroker = isFakeBroker
        self.executionConfig = executionConfig
        self.challengePixelDataBroker = challengePixelDataBroker
        self.challengePixelBrokerVersion = challengePixelBrokerVersion
        self.pixelHandler = pixelHandler
#if os(macOS)
        self.actionLogContext = actionLogContext
        self.challengeEventHandler = challengeEventHandler
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
        webView?.appearance = NSAppearance(named: .aqua)
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
        resetChallengeState()
        expectedBrokerURL = url
        webView?.load(url, additionalHTTPHeaders: ["Accept-Language": "en-US,en;q=0.9"])
#else
        webView?.load(url)
#endif
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
        challengeTask?.cancel()
        challengeTask = nil
        closeChallengePanel()
        isChallengeResponse = false
        isAwaitingChallengeDestination = false
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
                self.resetChallengeState()
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
    var challengeResolution: DataBrokerProtectionSharedPixels.ChallengeResolution {
        if didClickChallenge { return .assisted }
        return isAwaitingChallengeDestination ? .unknown : .unassisted
    }

    func updateChallengeState(isChallenge: Bool, responseURL: URL?, statusCode: Int) {
        isChallengeResponse = isChallenge
        if isChallenge {
            guard !isAwaitingChallengeDestination else { return }
            isAwaitingChallengeDestination = true
            reportChallengeEvent("Detected: main response has cf-mitigated=challenge; HTTP \(statusCode)")
            startChallengeSolver()
            return
        }

        guard isAwaitingChallengeDestination else { return }
        guard isExpectedBrokerDestination(responseURL) else {
            Logger.action.log("Challenge: non-challenge response did not reach the expected broker host")
            return
        }

        isAwaitingChallengeDestination = false
        challengeTask?.cancel()
        challengeTask = nil
        closeChallengePanel()
        reportChallengeEvent("Solved challenge \(challengeResolution.rawValue); expected broker destination reached")
        logChallengeClearanceCookie()
    }

    func startChallengeSolver() {
        challengeTask?.cancel()
        closeChallengePanel()
        challengeTask = Task { [weak self] in
            await self?.solveChallenge()
        }
    }

    func solveChallenge() async {
        guard let webView else { return }
        defer { closeChallengePanel() }
        let deadline = Date().addingTimeInterval(45)
        var nextSnapshotAttempt = Date.distantPast
        didClickChallenge = false

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        while isAwaitingChallengeDestination, Date() < deadline, !Task.isCancelled {
            guard isChallengeResponse else {
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }

            if !didClickChallenge, Date() >= nextSnapshotAttempt {
                nextSnapshotAttempt = Date().addingTimeInterval(2)
                if let point = await stableSnapshotCheckboxPoint(in: webView) {
                    attachChallengePanelIfNeeded(to: webView)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    let result = await ChallengeClick.checkbox(at: point, in: webView)
                    closeChallengePanel()
                    reportChallengeEvent("Sent snapshot checkbox click; \(result)")
                    didClickChallenge = true
                }
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard isAwaitingChallengeDestination, !Task.isCancelled else { return }
        isChallengeResponse = false
        isAwaitingChallengeDestination = false
        let failureStage = didClickChallenge ? "after click" : "with no click delivered"
        reportChallengeEvent(
            "Failed challenge \(failureStage); expected broker destination did not arrive before the 45-second deadline",
            isError: true)
        resumeActiveContinuation(with: .failure(DataBrokerProtectionError.unknown("Challenge did not reach the broker destination")))
    }

    func stableSnapshotCheckboxPoint(in webView: WKWebView) async -> NSPoint? {
        let snapshotRect = webView.bounds
        guard let firstImage = await challengeSnapshot(of: webView, rect: snapshotRect),
              let firstLabel = await ChallengeVision.findChallengeLabel(in: firstImage),
              isChallengeResponse else {
            Logger.action.log("Challenge: first snapshot did not contain the verification label")
            return nil
        }
        guard isChallengeResponse, !Task.isCancelled else { return nil }

        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let secondImage = await challengeSnapshot(of: webView, rect: snapshotRect), isChallengeResponse else {
            Logger.action.log("Challenge: second snapshot failed")
            return nil
        }
        guard let secondLabel = await ChallengeVision.findChallengeLabel(in: secondImage) else {
            Logger.action.log("Challenge: second snapshot did not contain the verification label")
            return nil
        }
        guard isChallengeResponse, !Task.isCancelled else { return nil }
        guard firstLabel.isStable(comparedTo: secondLabel, in: snapshotRect.size) else {
            Logger.action.log("Challenge: snapshot rejected because the verification label was not stable")
            return nil
        }
        Logger.action.log("Challenge: stable verification label found")
        let pointInSnapshot = secondLabel.checkboxPoint(in: snapshotRect.size)
        return NSPoint(x: snapshotRect.minX + pointInSnapshot.x, y: snapshotRect.minY + pointInSnapshot.y)
    }

    func challengeSnapshot(of webView: WKWebView, rect: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let request = ChallengeSnapshotRequest(continuation: continuation)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            webView.takeSnapshot(with: configuration) { image, _ in
                Task { @MainActor in
                    request.finish(with: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
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

    func logChallengeClearanceCookie() {
        guard let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let hasClearance = cookies.contains { $0.name.caseInsensitiveCompare("cf_clearance") == .orderedSame }
            Task { @MainActor in
                self?.reportChallengeEvent("Supporting evidence: cf_clearance=\(hasClearance)")
            }
        }
    }

    func reportChallengeEvent(_ message: String, isError: Bool = false) {
        let logMessage = "Challenge: \(message)"
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
        challengeEventHandler?(message)
    }

    func resetChallengeState() {
        didClickChallenge = false
        challengeTask?.cancel()
        challengeTask = nil
        closeChallengePanel()
        isChallengeResponse = false
        isAwaitingChallengeDestination = false
    }

    func attachChallengePanelIfNeeded(to webView: WKWebView) {
        guard webView.window == nil else { return }
        let panel = ChallengeOffscreenPanel(
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
        challengePanel = panel
        panel.presentOffscreen()
    }

    func closeChallengePanel() {
        challengePanel?.dismissOffscreen()
        challengePanel = nil
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
        guard !isAwaitingChallengeDestination else {
            Logger.action.log("Challenge: holding the broker load continuation")
            return
        }
#endif

        resumeActiveContinuation(with: .success(()))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFail: \(error.localizedDescription, privacy: .public)")
#if os(macOS)
        resetChallengeState()
#endif
        resumeActiveContinuation(with: .failure(error))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFailProvisionalNavigation: \(error.localizedDescription, privacy: .public)")
#if os(macOS)
        resetChallengeState()
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
            updateChallengeState(isChallenge: isChallenge, responseURL: response.url, statusCode: statusCode)
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
        resetChallengeState()
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
        Logger.action.log("Challenge: pixel detected fired for \(challengePixelDataBroker, privacy: .public)")
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
        let resolution = challengeResolution
        Logger.action.log("Challenge: pixel clearance fired for \(challengePixelDataBroker, privacy: .public) resolution=\(resolution.rawValue, privacy: .public)")
        pixelHandler?.fire(.challengeClearanceObserved(
            dataBroker: challengePixelDataBroker,
            brokerVersion: challengePixelBrokerVersion,
            resolution: resolution))
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
