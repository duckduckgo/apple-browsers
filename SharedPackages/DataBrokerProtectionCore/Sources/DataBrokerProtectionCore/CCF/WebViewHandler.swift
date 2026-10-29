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
    private let customUserAgent: String?
    private(set) var webViewConfiguration: WKWebViewConfiguration?
    private var userContentController: DataBrokerUserContentController?

    private var webView: WebView?
    var webViewForTesting: WKWebView? { webView }

#if os(macOS)
#if DEBUG
    let manualControl = PIRManualControl()
    private let assistItemID: PIRAssistItemID?
    private let assistBrokerName: String?
    private var assistSession: PIRAssistSession?
    private var manualDeadline: Task<Void, Never>?
    private var manualNavigationURL: URL?
    private var isAwaitingManagedChallengeDestination = false
    private var isManagedChallengeResponse = false
    private var didReachManagedChallengeDestination = false
    private var expectedManagedChallengeURL: URL?
    private var resumeAfterManagedNavigation = false
    private var embeddedChallengeTask: Task<Void, Never>?
    private var userNavigatedDuringTurn = false
    private var turnEndedByUserNavigation = false
    private var lastUserTurnKind: PIRAssistUserTurnKind?
    private var userTurnEndedSinceLastClickOrFill = false
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
                customUserAgent: String? = nil,
                contentBlocking: DBPWebViewContentBlocking? = nil,
                assistItemID: PIRAssistItemID? = nil,
                assistBrokerName: String? = nil,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil) throws {
#if os(macOS) && DEBUG
        self.assistItemID = assistItemID
        self.assistBrokerName = assistBrokerName
#endif
        self.isFakeBroker = isFakeBroker
        self.executionConfig = executionConfig
        self.challengePixelDataBroker = challengePixelDataBroker
        self.challengePixelBrokerVersion = challengePixelBrokerVersion
        self.pixelHandler = pixelHandler
        self.customUserAgent = customUserAgent
        let configuration = WKWebViewConfiguration()
        try configuration.applyDataBrokerConfiguration(privacyConfig: privacyConfig,
                                                       prefs: prefs,
                                                       delegate: delegate,
                                                       executionConfig: executionConfig,
                                                       shouldContinueActionHandler: shouldContinueActionHandler,
                                                       contentBlocking: contentBlocking)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

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
        if let customUserAgent {
            webView?.customUserAgent = customUserAgent
        }
#if os(macOS) && DEBUG
        registerAssistSession()
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
        embeddedChallengeTask?.cancel()
        embeddedChallengeTask = nil
        manualDeadline?.cancel()
        manualDeadline = nil
        manualControl.invalidateAutomation()
        if manualControl.isPaused {
            manualControl.endPause()
        }
        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.setManualControl(true)
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        manualControl.resume = nil
        manualControl.cancel = nil
        if assistSession != nil, let webView {
            // The page can stay on screen in the done state, so its cursor and labels have to go.
            dataBrokerFeature?.pushAssistMessage(.setAssistMode, params: PIRAssistModeParams(enabled: false), webView: webView)
        }
        unregisterAssistSession()
        resumeActiveContinuation(with: .failure(DataBrokerProtectionError.cancelled))
#endif
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
    private var dataBrokerFeature: DataBrokerProtectionFeature? {
        userContentController?.dataBrokerUserScripts?.dataBrokerFeature
    }

    private func registerAssistSession() {
        guard let assistItemID, let webView else { return }
        let session = PIRAssistSession(id: assistItemID, brokerName: assistBrokerName ?? "the broker",
                                       brokerURL: challengePixelDataBroker ?? "", webView: webView)
        session.onUserConfirmedDone = { [weak self] in self?.resumeFromUserTurn(reason: .userConfirmed) }
        session.onStop = { [weak self] in self?.stopAssistedJob() }
        dataBrokerFeature?.onUserTurnCompleted = { [weak self] in self?.resumeFromUserTurn(reason: .completed) }
        assistSession = session
        PIRAssistCenter.shared.register(session)
    }

    private func unregisterAssistSession() {
        guard let assistSession else { return }
        self.assistSession = nil
        PIRAssistCenter.shared.unregister(assistSession)
    }

    private func pushAssistMode() {
        guard assistSession != nil, let webView else { return }
        dataBrokerFeature?.pushAssistMessage(.setAssistMode, params: PIRAssistModeParams(enabled: true), webView: webView)
        if let kind = assistSession?.userTurn {
            dataBrokerFeature?.pushAssistMessage(.userTurnStarted,
                                                 params: PIRUserTurnStartedParams(kind: kind, tokenSelector: kind.tokenSelector),
                                                 webView: webView)
        }
    }

    /// Pauses automation and asks the user to solve the challenge. Embedded widgets keep the in-flight action, which
    /// the page holds until the turn ends; a managed challenge replaces the page, so its interrupted work is dropped.
    private func beginUserTurn(_ kind: PIRAssistUserTurnKind) {
        guard let webView, !manualControl.isPaused else { return }
        userNavigatedDuringTurn = false
        turnEndedByUserNavigation = false
        lastUserTurnKind = kind
        let preservingAutomation = kind != .managedChallenge
        manualControl.isEmbeddedChallenge = preservingAutomation
        manualControl.pause(preservingAutomation: preservingAutomation)
        dataBrokerFeature?.setManualControl(true, preservingAutomation: preservingAutomation)
        stopTimer()
        assistSession?.setUserTurn(kind)
        dataBrokerFeature?.pushAssistMessage(.userTurnStarted,
                                             params: PIRUserTurnStartedParams(kind: kind, tokenSelector: kind.tokenSelector),
                                             webView: webView)
        if let assistSession {
            PIRAssistCenter.shared.presenter?.present(assistSession)
        }
        manualDeadline?.cancel()
        manualDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(PIRManualControl.userTurnLimit) * 1_000_000_000) } catch { return }
            guard let self, self.manualControl.isPaused else { return }
            self.stopAssistedJob()
        }
    }

    private func resumeFromUserTurn(reason: PIRUserTurnEndedParams.Reason) {
        guard manualControl.isPaused, let webView else { return }
        if manualControl.isManagedChallenge {
            guard didReachManagedChallengeDestination, !isManagedChallengeResponse,
                  isExpectedManagedChallengeDestination(webView.url) else { return }
        }
        let resumeInterruptedAutomation = manualControl.preservesAutomation && !manualControl.isManagedChallenge
            && !turnEndedByUserNavigation
        if turnEndedByUserNavigation {
            manualControl.invalidateAutomation()
            dataBrokerFeature?.abandonSuspendedAction()
        }
        manualDeadline?.cancel()
        manualDeadline = nil
        resumeAfterManagedNavigation = false
        manualControl.isManagedChallenge = false
        manualControl.endPause()
        assistSession?.setUserTurn(nil)
        userTurnEndedSinceLastClickOrFill = !turnEndedByUserNavigation
        dataBrokerFeature?.pushAssistMessage(.userTurnEnded, params: PIRUserTurnEndedParams(reason: reason), webView: webView)
        dataBrokerFeature?.setManualControl(false)
        installTimer()
        resumeActiveContinuation(with: .success(()))
        if turnEndedByUserNavigation {
            Task { @MainActor [weak self] in await self?.manualControl.resumeAfterUserNavigation?() }
        } else if !resumeInterruptedAutomation {
            Task { @MainActor [weak self] in await self?.manualControl.resume?() }
        }
    }

    func markAssistedOptOutSubmitted(awaitsEmailConfirmation: Bool) {
        assistSession?.didSubmit(PIRAssistSubmission(awaitsEmailConfirmation: awaitsEmailConfirmation))
    }

    /// True once after a user's turn ended, when they may have submitted the form themselves.
    func consumeUserTurnEnded() -> Bool {
        defer { userTurnEndedSinceLastClickOrFill = false }
        return userTurnEndedSinceLastClickOrFill
    }

    /// The user moved the page on during an embedded challenge, most likely by submitting the form themselves,
    /// so the interrupted actions no longer apply to this page.
    private func endTurnAfterUserNavigation() {
        userNavigatedDuringTurn = false
        guard manualControl.isPaused, manualControl.isEmbeddedChallenge else { return }
        Logger.action.log("Assist: the page moved on during the user's turn")
        turnEndedByUserNavigation = true
        resumeFromUserTurn(reason: .userConfirmed)
    }

    private func stopAssistedJob() {
        if let webView, manualControl.isPaused {
            dataBrokerFeature?.pushAssistMessage(.userTurnEnded, params: PIRUserTurnEndedParams(reason: .stopped), webView: webView)
        }
        Task { @MainActor [weak self] in await self?.manualControl.cancel?() }
    }

    private func isExpectedManagedChallengeDestination(_ url: URL?) -> Bool {
        guard let expectedHost = expectedManagedChallengeURL.flatMap({ BrokerJobExecutionConfig.domain(of: $0.absoluteString) }),
              let responseHost = url.flatMap({ BrokerJobExecutionConfig.domain(of: $0.absoluteString) }) else { return false }
        return responseHost == expectedHost || responseHost.hasSuffix(".\(expectedHost)") || expectedHost.hasSuffix(".\(responseHost)")
    }

    func updateManagedChallengeState(response: HTTPURLResponse) {
        guard assistSession != nil || window != nil else { return }
        isManagedChallengeResponse = response.value(forHTTPHeaderField: "cf-mitigated")?.caseInsensitiveCompare("challenge") == .orderedSame
        if isManagedChallengeResponse {
            if !isAwaitingManagedChallengeDestination {
                expectedManagedChallengeURL = manualNavigationURL ?? response.url
            }
            isAwaitingManagedChallengeDestination = true
            didReachManagedChallengeDestination = false
            manualControl.isManagedChallenge = true
            dataBrokerFeature?.setManualControl(true)
            if assistSession != nil {
                beginUserTurn(.managedChallenge)
            }
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

    /// Brokers such as PeopleFinders wait for a Turnstile token in their own form. Turnstile often clears by
    /// itself; when it does not, hand the widget to the user before the wait times out.
    func watchForEmbeddedChallenge(during action: Action?) {
        embeddedChallengeTask?.cancel()
        embeddedChallengeTask = nil
        guard assistSession != nil, let action, action.actionType == .expectation, let json = action.json,
              String(bytes: json, encoding: .utf8)?.contains(PIRAssistUserTurnKind.turnstileTokenField) == true else { return }
        embeddedChallengeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            guard let self, !(await self.hasToken(for: .turnstile)), !self.manualControl.isPaused else { return }
            _ = await self.askUserToSolve(.turnstile)
        }
    }

    /// The user ticks this broker's reCAPTCHA in place of the backend solver.
    func askUserToSolveCaptcha() async -> Bool {
        await askUserToSolve(.recaptcha)
    }

    /// Returns once the user's turn is over: true to carry on, false if the job ended or the user moved the page on.
    private func askUserToSolve(_ kind: PIRAssistUserTurnKind) async -> Bool {
        beginUserTurn(kind)
        guard manualControl.isPaused else { return false }
        while !Task.isCancelled, manualControl.isPaused {
            // Also polled here, so resuming doesn't depend on the page reporting it.
            if manualControl.isEmbeddedChallenge, await hasToken(for: kind) {
                resumeFromUserTurn(reason: .completed)
                break
            }
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return false }
        }
        return !Task.isCancelled && webView != nil && !turnEndedByUserNavigation
    }

    /// Whether the page the user moved to still has the challenge from their last turn, for example after a
    /// broker rejected an unsolved form and reloaded it with a fresh widget.
    func hasChallengeFromLastUserTurn() async -> Bool {
        guard let selector = lastUserTurnKind?.tokenSelector else { return false }
        let script = "return document.querySelector(selector) !== null"
        let found = try? await webView?.callAsyncJavaScript(script, arguments: ["selector": selector], contentWorld: .defaultClient) as? Bool
        return found == true
    }

    private func hasToken(for kind: PIRAssistUserTurnKind) async -> Bool {
        guard let selector = kind.tokenSelector else { return false }
        let script = "return Array.from(document.querySelectorAll(selector)).some(field => field.value !== '')"
        let solved = try? await webView?.callAsyncJavaScript(script, arguments: ["selector": selector], contentWorld: .defaultClient) as? Bool
        return solved == true
    }

    func updateAssistChecklist(_ actionsHandler: ActionsHandler, profileQuery: ProfileQuery) {
        guard let assistSession else { return }
        let checklist = PIRAssistChecklist(stepType: actionsHandler.stepType, actions: actionsHandler.assistActions,
                                           currentIndex: actionsHandler.assistCurrentIndex,
                                           brokerName: assistSession.brokerName, profileQuery: profileQuery,
                                           isConfirmation: actionsHandler.isEmailConfirmationContinuation)
        assistSession.update(checklist: checklist)
    }
#endif

    public func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) async {
        #if os(macOS) && DEBUG
        guard await manualControl.waitForAutomation(manualControl.epoch) else { return }
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
#if os(macOS) && DEBUG
        if manualControl.isPaused, manualControl.isEmbeddedChallenge {
            userNavigatedDuringTurn = true
        }
#endif
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.action.log("WebViewHandler didFinish")
#if os(macOS)
        updateAddressBar(with: webView.url)
        #if DEBUG
        if userNavigatedDuringTurn {
            endTurnAfterUserNavigation()
        }
        pushAssistMode()
        if manualControl.isPaused, manualControl.isManagedChallenge, didReachManagedChallengeDestination {
            // The cleared challenge landed on the broker page, so hand back without waiting for the user.
            resumeFromUserTurn(reason: .completed)
            return
        }
        guard !isAwaitingManagedChallengeDestination, !manualControl.isPaused else { return }
        if resumeAfterManagedNavigation {
            resumeAfterManagedNavigation = false
            dataBrokerFeature?.setManualControl(false)
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
