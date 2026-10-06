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
#if DEBUG
    private let livePreviewOperationID = UUID()
    let manualControl = PIRManualControl()
    private var manualDeadline: Task<Void, Never>?
    private var manualGuidance: NSTextField?
    private var manualResumeButton: NSButton?
    private var manualNavigationURL: URL?
    private var isAwaitingManagedChallengeDestination = false
    private var isManagedChallengeResponse = false
    private var didReachManagedChallengeDestination = false
    private var expectedManagedChallengeURL: URL?
    private var resumeAfterManagedNavigation = false
    private var automaticPreviewActivity = "Opening the broker website"
    private let previewBrokerName: String?
#endif
    private var urlObservation: NSKeyValueObservation?
    private var window: NSWindow?
    private var addressBarTextField: NSTextField?
    private var toolbar: NSToolbar?
    private var didDetectChallenge = false
    private var didReportChallengeClearance = false
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
                previewBrokerName: String? = nil,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil) throws {
#if os(macOS) && DEBUG
        self.previewBrokerName = previewBrokerName ?? challengePixelDataBroker
#endif
        self.isFakeBroker = isFakeBroker
        self.executionConfig = executionConfig
        self.challengePixelDataBroker = challengePixelDataBroker
        self.challengePixelBrokerVersion = challengePixelBrokerVersion
        self.pixelHandler = pixelHandler
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
#if os(macOS) && DEBUG
        if let webView, let previewBrokerName {
            PIRLivePreview.shared.register(webView: webView, operationID: livePreviewOperationID, brokerName: previewBrokerName)
            PIRLivePreview.shared.attach(handler: self, operationID: livePreviewOperationID)
        }
#endif

        if showWebView {
#if os(macOS)
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
#elseif os(iOS)
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
#endif

        }

        installTimer()

        try? await load(url: URL(string: "\(WebViewSchemeHandler.dataBrokerProtectionScheme)://blank")!)
    }

    public func load(url: URL) async throws {
#if os(macOS)
        didDetectChallenge = false
        didReportChallengeClearance = false
#if DEBUG
        PIRLivePreview.shared.updateActivity("Opening the broker website", operationID: livePreviewOperationID)
#endif
#endif
        #if os(macOS) && DEBUG
        guard await manualControl.waitForAutomation(manualControl.epoch) else { return }
        manualNavigationURL = url
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
#if os(macOS) && DEBUG
        manualDeadline?.cancel()
        manualDeadline = nil
        manualControl.invalidateAutomation()
        if manualControl.isPaused {
            manualControl.endPause()
            PIRLivePreview.shared.manualControlChanged?(livePreviewOperationID, false)
        }
        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(true)
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        manualControl.resume = nil
        manualControl.cancel = nil
        PIRLivePreview.shared.unregister(operationID: livePreviewOperationID)
#endif
        resumeActiveContinuation(with: .failure(DataBrokerProtectionError.cancelled))
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
        urlObservation?.invalidate()
        urlObservation = nil
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
                self.resumeActiveContinuation(with: .failure(DataBrokerProtectionError.cancelled))
            }
        }
    }

    private func resumeActiveContinuation(with result: Result<Void, Error>) {
        let continuation = activeContinuation
        activeContinuation = nil
        continuation?.resume(with: result)
    }

#if os(macOS) && DEBUG
    func takeManualControl() async throws -> Bool {
        guard manualControl.canTakeControl, let webView else { return false }
        let preservingAutomation = !manualControl.isManagedChallenge
        manualControl.pause(preservingAutomation: preservingAutomation)
        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(true, preservingAutomation: preservingAutomation)
        stopTimer()
        do {
            let script = "globalThis.__pirControl.paused = true" + (preservingAutomation ? "" : "; globalThis.__pirControl.epoch++")
            let _: Any = try await webView.evaluateJavaScript(script, in: nil, in: .defaultClient)
        } catch {
            manualControl.invalidateAutomation()
            manualControl.endPause()
            await manualControl.cancel?()
            throw error
        }
        guard manualControl.isPaused, self.webView === webView else { return false }
        PIRLivePreview.shared.manualControlChanged?(livePreviewOperationID, true)
        PIRLivePreview.shared.updateActivity("Paused for your assistance", operationID: livePreviewOperationID)
        let content = NSView()
        let guidance = NSTextField(labelWithString: manualControl.instruction)
        guidance.font = .systemFont(ofSize: 14, weight: .medium)
        guidance.translatesAutoresizingMaskIntoConstraints = false
        let resume = NSButton(title: "Resume automatically", target: self, action: #selector(resumeManualControl))
        resume.bezelStyle = .rounded
        resume.translatesAutoresizingMaskIntoConstraints = false
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(guidance)
        content.addSubview(resume)
        content.addSubview(webView)
        NSLayoutConstraint.activate([
            guidance.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            guidance.centerYAnchor.constraint(equalTo: resume.centerYAnchor),
            guidance.trailingAnchor.constraint(lessThanOrEqualTo: resume.leadingAnchor, constant: -12),
            resume.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            resume.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            webView.topAnchor.constraint(equalTo: resume.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        manualGuidance = guidance
        manualResumeButton = resume
        window?.orderOut(nil)
        let manualWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 850),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        manualWindow.title = previewBrokerName ?? "Personal Information Removal"
        manualWindow.isReleasedWhenClosed = false
        manualWindow.delegate = self
        manualWindow.contentView = content
        manualWindow.standardWindowButton(.closeButton)?.isEnabled = false
        window = manualWindow
        manualWindow.center()
        PIRLivePreview.shared.manualControlStarted?()
        manualWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        manualDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
            guard let self, self.manualControl.isPaused else { return }
            await self.manualControl.cancel?()
        }
        return true
    }

    @objc private func resumeManualControl() {
        guard manualControl.isPaused, manualResumeButton?.isEnabled == true else { return }
        manualResumeButton?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completed = self.verifyManualStep()
            guard self.manualControl.isPaused else { return }
            guard completed else {
                self.manualGuidance?.stringValue = "Step incomplete. " + self.manualControl.instruction
                self.manualResumeButton?.isEnabled = true
                return
            }
            guard let webView = self.webView else { return }
            let resumeInterruptedAutomation = self.manualControl.preservesAutomation && !self.manualControl.isManagedChallenge
            // Only a challenge handoff discards interrupted work. A normal pause preserves its result.
            do {
                let script = (resumeInterruptedAutomation ? "" : "globalThis.__pirControl.epoch++; ") + "globalThis.__pirControl.paused = false"
                let _: Any = try await webView.evaluateJavaScript(script, in: nil, in: .defaultClient)
            } catch {
                self.manualGuidance?.stringValue = "Page check failed. Please try Resume automatically again."
                self.manualResumeButton?.isEnabled = true
                return
            }
            guard self.manualControl.isPaused, self.webView === webView else { return }
            guard self.verifyManualStep(),
                  resumeInterruptedAutomation == (self.manualControl.preservesAutomation && !self.manualControl.isManagedChallenge) else {
                let _: Any? = try? await webView.evaluateJavaScript("globalThis.__pirControl.paused = true", in: nil, in: .defaultClient)
                self.manualGuidance?.stringValue = "Page changed. " + self.manualControl.instruction
                self.manualResumeButton?.isEnabled = true
                return
            }
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
            self.window?.orderOut(nil)
            self.window?.contentView = nil
            self.window = nil
            self.manualDeadline?.cancel()
            self.manualDeadline = nil
            self.resumeAfterManagedNavigation = false
            self.manualControl.isManagedChallenge = false
            self.manualControl.endPause()
            self.resumeActiveContinuation(with: .success(()))
            self.userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(false)
            PIRLivePreview.shared.updateActivity(self.automaticPreviewActivity, operationID: self.livePreviewOperationID)
            PIRLivePreview.shared.manualControlChanged?(self.livePreviewOperationID, false)
            self.installTimer()
            PIRLivePreview.shared.automationResumed?()
            if !resumeInterruptedAutomation { await self.manualControl.resume?() }
        }
    }

    private func verifyManualStep() -> Bool {
        guard let webView, !webView.isLoading else { return false }
        if !manualControl.isManagedChallenge { return webView.url != nil }
        return !isManagedChallengeResponse && didReachManagedChallengeDestination
            && isExpectedManagedChallengeDestination(webView.url)
    }

    private func isExpectedManagedChallengeDestination(_ url: URL?) -> Bool {
        func normalizedHost(_ host: String?) -> String? {
            guard let host else { return nil }
            return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)).lowercased() : host.lowercased()
        }
        guard let expectedHost = normalizedHost(expectedManagedChallengeURL?.host),
              let responseHost = normalizedHost(url?.host) else { return false }
        return responseHost == expectedHost || responseHost.hasSuffix(".\(expectedHost)") || expectedHost.hasSuffix(".\(responseHost)")
    }

    func updateManagedChallengeState(response: HTTPURLResponse) {
        // Same main-frame detector and destination proof as apple-browsers-haki.
        isManagedChallengeResponse = response.value(forHTTPHeaderField: "cf-mitigated")?.caseInsensitiveCompare("challenge") == .orderedSame
        if isManagedChallengeResponse {
            if !isAwaitingManagedChallengeDestination {
                expectedManagedChallengeURL = manualNavigationURL ?? response.url
            }
            isAwaitingManagedChallengeDestination = true
            didReachManagedChallengeDestination = false
            manualControl.isManagedChallenge = true
            userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(true)
            if manualControl.isPaused { manualGuidance?.stringValue = manualControl.instruction }
            PIRLivePreview.shared.updateActivity("Cloudflare security check needs your help", operationID: livePreviewOperationID)
            return
        }
        guard isAwaitingManagedChallengeDestination, (200..<400).contains(response.statusCode),
              isExpectedManagedChallengeDestination(response.url) else { return }
        isAwaitingManagedChallengeDestination = false
        didReachManagedChallengeDestination = true
        if !manualControl.isPaused {
            manualControl.isManagedChallenge = false
            resumeAfterManagedNavigation = true
        }
    }

    public func updateLivePreviewActivity(for actionType: ActionType, stepType: StepType?) {
        automaticPreviewActivity = actionType.livePreviewActivity(for: stepType)
        PIRLivePreview.shared.updateActivity(automaticPreviewActivity, operationID: livePreviewOperationID)
    }
#endif

    public func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) async {
        #if os(macOS) && DEBUG
        guard await manualControl.waitForAutomation(manualControl.epoch) else { return }
        #endif
#if os(macOS) && DEBUG
        updateLivePreviewActivity(for: action.actionType, stepType: stepType)
#endif
        Logger.action.log("Executing action: \(String(describing: action.actionType.rawValue), privacy: .public)")

        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.pushAction(
            method: .onActionReceived,
            webView: self.webView!,
            params: Params(state: ActionRequest(action: action, data: data))
        )
    }

    public func evaluateJavaScript(_ javaScript: String) async throws {
        #if os(macOS) && DEBUG
        guard await manualControl.waitForAutomation(manualControl.epoch) else { return }
        #endif
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
        #if DEBUG
        if manualControl.isPaused { return false }
        #endif
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
        #if DEBUG
        guard !isAwaitingManagedChallengeDestination, !manualControl.isPaused else { return }
        if resumeAfterManagedNavigation {
            resumeAfterManagedNavigation = false
            userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(false)
            if activeContinuation == nil {
                Task { @MainActor [weak self] in await self?.manualControl.resume?() }
                return
            }
        }
        #endif
#endif

        resumeActiveContinuation(with: .success(()))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFail: \(error.localizedDescription, privacy: .public)")
        resumeActiveContinuation(with: .failure(error))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFailProvisionalNavigation: \(error.localizedDescription, privacy: .public)")
        resumeActiveContinuation(with: .failure(error))
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if os(macOS)
        updateAddressBar(with: webView.url)
        #if DEBUG
        if manualControl.isPaused && manualControl.preservesAutomation {
            // A manual navigation replaces the interrupted document. Resume from the resulting page.
            manualControl.invalidateAutomation()
            userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(true)
        }
        #endif
#endif
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let response = navigationResponse.response
        #if os(macOS) && DEBUG
        if navigationResponse.isForMainFrame, let response = response as? HTTPURLResponse {
            updateManagedChallengeState(response: response)
        }
        #endif
#if os(macOS)
        recordChallengeDetectionIfPresent(in: response, isForMainFrame: navigationResponse.isForMainFrame)
        if navigationResponse.isForMainFrame {
            observeChallengeClearance(in: webView)
        }
#endif

        guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
            // if there's no http status code to act on, exit and allow navigation
            return .allow
        }

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

#if os(macOS) && DEBUG
private extension ActionType {
    func livePreviewActivity(for stepType: StepType?) -> String {
        switch self {
        case .navigate: return "Opening the broker website"
        case .extract: return "Searching for your information"
        case .fillForm:
            return stepType == .scan ? "Entering your search details" : "Filling out the removal form"
        case .click:
            return stepType == .scan ? "Continuing your search" : "Continuing your removal request"
        case .expectation: return "Waiting for the page to be ready"
        case .condition: return "Checking the next step"
        case .executeScript: return "Working through the next step"
        case .generateEmail: return "Preparing a private email address"
        case .getEmailData: return "Waiting for the broker's email"
        case .emailConfirmation: return "Confirming your removal request"
        case .getCaptchaInfo: return "Checking the site's security challenge"
        case .solveCaptcha: return "Working through the security challenge"
        }
    }
}
#endif
