//
//  SyncDebugMenu.swift
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

import AppKit
import DDGSync
import Bookmarks
import CoreImage.CIFilterBuiltins
import SystemConfiguration

final class SyncDebugMenu: NSMenu {

    private let environmentMenu = NSMenu()
    private let scopedAccessCredentialPurpose = "ai_chats"
    private var thirdPartyRecoveryWindowController: NSWindowController?
    private var pairingV2DebugWindowController: NSWindowController?
    private var debugResponseWindowControllers: [NSWindowController] = []

    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Environment")
                .submenu(environmentMenu)
                .withAccessibilityIdentifier("SyncDebugMenu.environment")

            NSMenuItem(title: "Turn off Sync", action: #selector(turnOffSync), target: self)
                .withAccessibilityIdentifier("SyncDebugMenu.turnOffSync")
            NSMenuItem(title: "Reset Favicons Fetcher Onboarding Dialog", action: #selector(resetFaviconsFetcherOnboardingDialog), target: self)
            NSMenuItem(title: "Populate Stub objects", action: #selector(createStubsForDebug), target: self)
            NSMenuItem(title: "Show Sync With Another Device (Chat Sync)", action: #selector(showSyncWithAnotherDevicePromo), target: self)
            NSMenuItem(title: "Show 3P Recovery Code", action: #selector(showThirdPartyRecoveryCode), target: self)
            NSMenuItem.separator()
            NSMenuItem(title: "Run V2 Pairing Debug", action: #selector(showPairingV2Debug), target: self)
            NSMenuItem(title: "Fetch Devices (GET /devices)", action: #selector(fetchDevicesRawResponse), target: self)
            NSMenuItem(title: "Fetch Keys (GET /keys)", action: #selector(fetchProtectedKeysRawResponse), target: self)
            NSMenuItem(title: "Fetch Access Credentials (GET /access-credentials)",
                       action: #selector(fetchAccessCredentialsRawResponse),
                       target: self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        populateEnvironmentMenu()
        let isSyncAvailable = NSApp.delegateTyped.syncService != nil
        let isScopedAccessCredentialsEnabled = NSApp.delegateTyped.featureFlagger.isFeatureOn(.syncScopedAccessCredentials)

        item(with: #selector(showThirdPartyRecoveryCode))?.isEnabled = isSyncAvailable && isScopedAccessCredentialsEnabled
        item(with: #selector(showPairingV2Debug))?.isEnabled = isSyncAvailable
        item(with: #selector(fetchDevicesRawResponse))?.isEnabled = isSyncAvailable
        item(with: #selector(fetchProtectedKeysRawResponse))?.isEnabled = isSyncAvailable && isScopedAccessCredentialsEnabled
        item(with: #selector(fetchAccessCredentialsRawResponse))?.isEnabled = isSyncAvailable && isScopedAccessCredentialsEnabled
    }

    private func populateEnvironmentMenu() {
        environmentMenu.removeAllItems()

        guard let syncService = NSApp.delegateTyped.syncService else {
            return
        }

        let currentEnvironment = syncService.serverEnvironment
        let anotherEnvironment: ServerEnvironment = syncService.serverEnvironment == .development ? .production : .development

        let statusMenuItem = NSMenuItem(title: "Current: \(currentEnvironment.description)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        environmentMenu.addItem(statusMenuItem.withAccessibilityIdentifier("SyncDebugMenu.currentEnvironment"))

        let toggleMenuItem = NSMenuItem(
            title: "Switch to \(anotherEnvironment.description)",
            action: #selector(switchSyncEnvironment),
            target: self,
            representedObject: anotherEnvironment)
        environmentMenu.addItem(toggleMenuItem.withAccessibilityIdentifier("SyncDebugMenu.switchEnvironment"))
    }

    @objc func switchSyncEnvironment(_ sender: NSMenuItem) {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild,
              let syncService = NSApp.delegateTyped.syncService,
              let environment = sender.representedObject as? ServerEnvironment
        else {
            return
        }

        syncService.updateServerEnvironment(environment)
        UserDefaults.standard.set(environment.description, forKey: UserDefaultsWrapper<String>.Key.syncEnvironment.rawValue)
    }

    @objc func createStubsForDebug() {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild else { return }
        let db = NSApp.delegateTyped.bookmarkDatabase

        let context = db.db.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let root = BookmarkUtils.fetchRootFolder(context)!
            let favorites = BookmarkUtils.fetchFavoritesFolders(for: .displayNative(.desktop), in: context)

            let nonStub1 = BookmarkEntity.makeBookmark(title: "Non stub", url: "url", parent: root, context: context)
            nonStub1.addToFavorites(folders: favorites)

            let stub1 = BookmarkEntity.makeBookmark(title: "Stub", url: "", parent: root, context: context)
            stub1.isStub = true
            stub1.addToFavorites(folders: favorites)

            let emptyStub = BookmarkEntity.makeBookmark(title: "", url: "", parent: root, context: context)
            emptyStub.isStub = true
            emptyStub.title = nil
            emptyStub.url = nil
            emptyStub.addToFavorites(folders: favorites)

            let nonStub2 = BookmarkEntity.makeBookmark(title: "Non stub 2", url: "url", parent: root, context: context)
            nonStub2.addToFavorites(folders: favorites)

            let stub2 = BookmarkEntity.makeBookmark(title: "Stub", url: "", parent: root, context: context)
            stub2.isStub = true
            stub2.addToFavorites(folders: favorites)

            let stub3 = BookmarkEntity.makeBookmark(title: "Stub", url: "", parent: root, context: context)
            stub3.isStub = true
            stub3.addToFavorites(folders: favorites)

            let nonStub3 = BookmarkEntity.makeBookmark(title: "Non stub 3", url: "url", parent: root, context: context)
            nonStub3.addToFavorites(folders: favorites)

            try? context.save()
        }
    }

    @MainActor
    @objc func turnOffSync(_ sender: NSMenuItem) {
        if let syncService = NSApp.delegateTyped.syncService, let syncDataProviders = NSApp.delegateTyped.syncDataProviders {
            let syncPreferences = SyncDialogController(
                syncService: syncService,
                syncPausedStateManager: syncDataProviders.syncErrorHandler
            )
            syncPreferences.turnOffSync()
        }
    }

    @MainActor
    @objc func showSyncWithAnotherDevicePromo(_ sender: NSMenuItem) {
        DeviceSyncCoordinator()?.startDeviceSyncFlow(source: .aiChat, completion: nil)
    }

    @MainActor
    @objc func showThirdPartyRecoveryCode(_ sender: NSMenuItem) {
        guard let syncService = NSApp.delegateTyped.syncService else {
            showErrorAlert(message: "Sync is not available")
            return
        }

        Task { @MainActor in
            do {
                let code = try await syncService.prepareThirdPartyRecoveryCode(purpose: scopedAccessCredentialPurpose)
                showThirdPartyRecoveryCodeWindow(recoveryCode: code)
            } catch {
                showErrorAlert(message: error.localizedDescription)
            }
        }
    }

    @MainActor
    @objc func showPairingV2Debug(_ sender: NSMenuItem) {
        guard let syncService = NSApp.delegateTyped.syncService else {
            showErrorAlert(message: "Sync is not available")
            return
        }

        let deviceInfo = Self.deviceInfo()
        let viewController = PairingV2DebugViewController(sync: syncService, deviceName: deviceInfo.name, deviceType: deviceInfo.type)
        let window = NSWindow(contentViewController: viewController)
        window.title = "V2 Pairing Debug"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 520, height: 460)
        window.setContentSize(NSSize(width: 680, height: 560))
        window.center()

        let windowController = NSWindowController(window: window)
        pairingV2DebugWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    @objc func fetchDevicesRawResponse(_ sender: NSMenuItem) {
        fetchRawResponse(title: "GET /devices") { syncService in
            try await syncService.fetchDevicesRawResponse()
        }
    }

    @MainActor
    @objc func fetchProtectedKeysRawResponse(_ sender: NSMenuItem) {
        fetchRawResponse(title: "GET /keys") { syncService in
            try await syncService.fetchProtectedKeysRawResponse()
        }
    }

    @MainActor
    @objc func fetchAccessCredentialsRawResponse(_ sender: NSMenuItem) {
        fetchRawResponse(title: "GET /access-credentials") { syncService in
            try await syncService.fetchAccessCredentialsRawResponse()
        }
    }

    @MainActor
    private func fetchRawResponse(title: String, fetch: @escaping (DDGSyncing) async throws -> String) {
        guard let syncService = NSApp.delegateTyped.syncService else {
            showErrorAlert(message: "Sync is not available")
            return
        }

        Task { @MainActor in
            do {
                let response = try await fetch(syncService)
                showDebugResponseWindow(title: title, responseText: response)
            } catch {
                showErrorAlert(title: "Sync Debug", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func showThirdPartyRecoveryCodeWindow(recoveryCode: String) {
        let viewController = ThirdPartyRecoveryCodeViewController(recoveryCode: recoveryCode)
        let window = NSWindow(contentViewController: viewController)
        window.title = "3P Recovery Code"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 440, height: 340)
        window.setContentSize(NSSize(width: 480, height: 340))
        window.center()

        let windowController = NSWindowController(window: window)
        thirdPartyRecoveryWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func showDebugResponseWindow(title: String, responseText: String) {
        let viewController = SyncDebugTextViewController(text: responseText)
        let window = NSWindow(contentViewController: viewController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 520, height: 360)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()

        let windowController = NSWindowController(window: window)
        debugResponseWindowControllers.append(windowController)
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func showErrorAlert(title: String = "Scoped Access Credentials", message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func deviceInfo() -> (name: String, type: String) {
        let hostname = SCDynamicStoreCopyComputerName(nil, nil) as? String ?? ProcessInfo.processInfo.hostName
        return (name: hostname, type: "desktop")
    }

    @objc func resetFaviconsFetcherOnboardingDialog(_ sender: NSMenuItem) {
        UserDefaultsWrapper<Bool?>(key: .syncDidPresentFaviconsFetcherOnboarding).clear()
    }

}

@MainActor
private final class PairingV2DebugViewController: NSViewController {

    private let sync: DDGSyncing
    private let deviceName: String
    private let deviceType: String
    private var connectionController: SyncConnectionControlling?
    private var scanTask: Task<Void, Never>?
    private var presenterCodeURL: URL?
    private var logEntries: [PairingV2DebugLogEntry] = []

    private let codeTextField = NSTextField()
    private let logModeControl = NSSegmentedControl(labels: ["Summary", "Raw"], trackingMode: .selectOne, target: nil, action: nil)
    private let logTextView = NSTextView()

    init(sync: DDGSyncing, deviceName: String, deviceType: String) {
        self.sync = sync
        self.deviceName = deviceName
        self.deviceType = deviceType
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scanTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupLayout()
        appendSummary("Ready. Paste a V2 code2 URL to start an exchange or create a V2 linking code.")
    }

    private func setupLayout() {
        codeTextField.placeholderString = "Paste V2 code2 URL"
        codeTextField.lineBreakMode = .byTruncatingMiddle

        logModeControl.selectedSegment = PairingV2DebugLogMode.summary.rawValue
        logModeControl.target = self
        logModeControl.action = #selector(logModeDidChange)

        let clearLogButton = NSButton(title: "Clear Log", target: self, action: #selector(clearLog))
        let runButton = NSButton(title: "Start Exchange", target: self, action: #selector(runScan))
        let cancelButton = NSButton(title: "Cancel Exchange", target: self, action: #selector(cancelScan))
        let copyLogButton = NSButton(title: "Copy Log", target: self, action: #selector(copyLog))
        let createPresenterCodeButton = NSButton(title: "Create V2 Linking Code", target: self, action: #selector(createPresenterCode))
        let copyPresenterCodeButton = NSButton(title: "Copy Linking Code", target: self, action: #selector(copyPresenterCode))

        let buttonStackView = NSStackView(views: [clearLogButton, runButton, cancelButton, copyLogButton])
        buttonStackView.orientation = .horizontal
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 12

        let linkingCodeButtonStackView = NSStackView(views: [createPresenterCodeButton, copyPresenterCodeButton])
        linkingCodeButtonStackView.orientation = .horizontal
        linkingCodeButtonStackView.distribution = .fillEqually
        linkingCodeButtonStackView.spacing = 12

        let scrollView = makeLogScrollView()
        let stackView = NSStackView(views: [codeTextField, buttonStackView, linkingCodeButtonStackView, logModeControl, scrollView])
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 340)
        ])
    }

    private func makeLogScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.isHorizontallyResizable = false
        logTextView.isVerticallyResizable = true
        logTextView.autoresizingMask = [.width]
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.textContainerInset = NSSize(width: 12, height: 12)
        logTextView.textContainer?.widthTracksTextView = true
        logTextView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = logTextView
        return scrollView
    }

    @objc private func clearLog() {
        logEntries = []
        renderLog()
    }

    @objc private func logModeDidChange() {
        renderLog()
    }

    @objc private func createPresenterCode() {
        guard scanTask == nil else {
            appendSummary("Pairing already in progress.")
            return
        }

        appendSummary("Creating V2 linking code.")
        let controller = sync.createDebugConnectionController(
            deviceName: deviceName,
            deviceType: deviceType,
            delegate: self,
            pairingV2DebugLogHandler: { [weak self] entry in
                Task { @MainActor in
                    self?.appendLog(entry)
                }
            }
        )
        connectionController = controller

        scanTask = Task { [weak self, controller] in
            do {
                let pairingInfo = try await controller.startExchangeMode()
                let url = pairingInfo.toURL(baseURL: URL(string: "https://duckduckgo.com")!)
                await MainActor.run {
                    self?.presenterCodeURL = url
                    self?.codeTextField.stringValue = url.absoluteString
                    self?.appendSummary("V2 linking code created. Paste it into the scanner.")
                }
            } catch {
                await MainActor.run {
                    self?.appendSummary("Failed to create V2 linking code: \(error)")
                    self?.scanTask = nil
                    self?.connectionController = nil
                }
            }
        }
    }

    @objc private func copyPresenterCode() {
        guard let presenterCodeURL else {
            appendSummary("No V2 linking code to copy.")
            return
        }

        NSPasteboard.general.copy(presenterCodeURL.absoluteString)
        appendSummary("Copied V2 linking code.")
    }

    @objc private func runScan() {
        guard scanTask == nil else {
            appendSummary("Exchange already in progress.")
            return
        }
        let code = codeTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            appendSummary("No V2 code provided.")
            return
        }

        appendSummary("Starting exchange.")
        let controller = sync.createDebugConnectionController(
            deviceName: deviceName,
            deviceType: deviceType,
            delegate: self,
            pairingV2DebugLogHandler: { [weak self] entry in
                Task { @MainActor in
                    self?.appendLog(entry)
                }
            }
        )
        connectionController = controller

        scanTask = Task { [weak self, controller] in
            let result = await controller.syncCodeEntered(code: code, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)
            await MainActor.run {
                self?.appendSummary("Exchange finished: \(result ? "success" : "failure")")
                self?.scanTask = nil
                self?.connectionController = nil
            }
        }
    }

    @objc private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil

        guard let connectionController else {
            appendSummary("No active exchange to cancel.")
            return
        }

        Task { [weak self, connectionController] in
            await connectionController.cancel()
            await MainActor.run {
                self?.appendSummary("Cancelled exchange.")
                self?.connectionController = nil
            }
        }
    }

    @objc private func copyLog() {
        NSPasteboard.general.copy(logTextView.string)
    }

    private func appendSummary(_ message: String) {
        appendLog(.init(kind: .summary, message: "* \(message)"))
    }

    private func appendLog(_ entry: PairingV2DebugLogEntry) {
        logEntries.append(entry)
        renderLog()
    }

    private func renderLog() {
        let selectedMode = PairingV2DebugLogMode(rawValue: logModeControl.selectedSegment) ?? .summary
        let selectedKind: PairingV2DebugLogEntry.Kind = selectedMode == .summary ? .summary : .raw
        logTextView.string = logEntries
            .filter { $0.kind == selectedKind }
            .map(\.message)
            .joined(separator: "\n")
        let range = NSRange(location: max(logTextView.string.count - 1, 0), length: 1)
        logTextView.scrollRangeToVisible(range)
    }

    private enum PairingV2DebugLogMode: Int {
        case summary
        case raw
    }
}

extension PairingV2DebugViewController: SyncConnectionControllerDelegate {

    func controllerWillBeginTransmittingRecoveryKey() async {
        appendSummary("Delegate: will begin transmitting recovery key.")
    }

    func controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: Bool) {
        appendSummary("Delegate: did finish transmitting recovery key (shouldWaitForDevicesToChange: \(shouldWaitForDevicesToChange)).")
    }

    func controllerDidReceiveRecoveryKey() {
        appendSummary("Delegate: did receive recovery key.")
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        appendSummary("Delegate: recognized \(setupSource.rawValue) code from \(codeSource.rawValue).")
    }

    func controllerWillPerformServerSyncOperation(setupRole: SyncSetupRole) async -> Bool {
        appendSummary("Delegate: will perform server operation for \(setupRole).")
        return true
    }

    func controllerShouldAllowPairingV2PeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        let peerName = peerName ?? "the other device"
        let isConfirmed = await showPairingV2Confirmation(message: "Allow \"\(peerName)\" to sync with this device?")
        appendSummary("Delegate: host confirmation \(isConfirmed ? "accepted" : "denied") for \(peerKind.rawValue) peer.")
        return isConfirmed
    }

    func controllerShouldJoinPairingV2Peer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        let peerName = peerName ?? "the other device"
        let isConfirmed = await showPairingV2Confirmation(message: "Sync your data with \"\(peerName)\"?")
        appendSummary("Delegate: joiner confirmation \(isConfirmed ? "accepted" : "denied") for \(peerKind.rawValue) peer.")
        return isConfirmed
    }

    func controllerDidCreateSyncAccount(shouldShowSyncEnabled: Bool) {
        appendSummary("Delegate: did create sync account. shouldShowSyncEnabled=\(shouldShowSyncEnabled)")
    }

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        appendSummary("Delegate: did complete account connection. shouldShowSyncEnabled=\(shouldShowSyncEnabled)")
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        appendSummary("Delegate: did complete login. devices=\(registeredDevices.count) isRecovery=\(isRecovery)")
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole, shouldPromptBeforeSwitchingAccounts: Bool) async {
        appendSummary("Delegate: found two accounts during recovery (shouldPromptBeforeSwitchingAccounts: \(shouldPromptBeforeSwitchingAccounts)).")
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: Error?, setupRole: SyncSetupRole) async {
        let underlyingError = underlyingError.map { " underlying=\($0)" } ?? ""
        appendSummary("Delegate: error \(error).\(underlyingError)")
    }

    private func showPairingV2Confirmation(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Sync your data?"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Sync")

            guard let window = view.window else {
                continuation.resume(returning: alert.runModal() == .alertSecondButtonReturn)
                return
            }

            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }
}

private final class SyncDebugTextViewController: NSViewController {

    private let text: String
    private let textView = NSTextView()

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupLayout()
    }

    private func setupLayout() {
        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyText))
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeScrollView()
        let stackView = NSStackView(views: [copyButton, scrollView])
        stackView.orientation = .vertical
        stackView.alignment = .trailing
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .controlBackgroundColor
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    @objc private func copyText() {
        NSPasteboard.general.copy(text)
    }
}

private final class ThirdPartyRecoveryCodeViewController: NSViewController {

    private let recoveryCode: String
    private let qrImageView = NSImageView()

    init(recoveryCode: String) {
        self.recoveryCode = recoveryCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupLayout()
        configureContent()
    }

    private func setupLayout() {
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        let codeCard = makeCodeCard()

        let stackView = NSStackView(views: [qrImageView, codeCard])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            qrImageView.widthAnchor.constraint(equalToConstant: 192),
            qrImageView.heightAnchor.constraint(equalToConstant: 192),
            codeCard.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func makeCodeCard() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 10
        container.translatesAutoresizingMaskIntoConstraints = false

        let codeLabel = NSTextField(wrappingLabelWithString: recoveryCode)
        codeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        codeLabel.alignment = .center
        codeLabel.isSelectable = true
        codeLabel.lineBreakMode = .byCharWrapping
        codeLabel.maximumNumberOfLines = 0
        codeLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyRecoveryCode))

        let cardStack = NSStackView(views: [codeLabel, copyButton])
        cardStack.orientation = .vertical
        cardStack.alignment = .centerX
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            cardStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cardStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            codeLabel.widthAnchor.constraint(equalTo: cardStack.widthAnchor)
        ])

        return container
    }

    private func configureContent() {
        qrImageView.image = makeQRCodeImage(from: recoveryCode)
    }

    @objc private func copyRecoveryCode() {
        NSPasteboard.general.copy(recoveryCode)
    }

    private func makeQRCodeImage(from value: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let renderSize: CGFloat = 560
        let scaleFactor = floor(renderSize / outputImage.extent.width)
        let transformed = outputImage.transformed(by: .init(scaleX: scaleFactor, y: scaleFactor))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: renderSize, height: renderSize))
    }
}
