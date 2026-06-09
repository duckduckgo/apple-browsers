//
//  SyncDebugViewController.swift
//  DuckDuckGo
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

import UIKit
import Core
import Persistence
import Bookmarks
import DDGSync
import Combine
import CoreImage
import os.log

private enum SyncDebugClipboard {
    static func copy(_ content: String, source: String) {
        UIPasteboard.general.string = content
        Logger.sync.debug("Copied clipboard content from \(source, privacy: .public): \(content)")
    }
}

class SyncDebugViewController: UITableViewController {

    private let titles = [
        Sections.info: "Info",
        Sections.models: "Models",
        Sections.environment: "Environment",
        Sections.pairingV2: "V2 Pairing",
        Sections.scopedAccessCredentials: "Scoped Access Credentials"
    ]

    enum Sections: Int, CaseIterable {

        case info
        case models
        case environment
        case pairingV2
        case scopedAccessCredentials

    }

    enum InfoRows: Int, CaseIterable {

        case syncNow
        case logOut
        case toggleFavoritesDisplayMode
        case resetFaviconsFetcherOnboardingDialog
        case getRecoveryCode
        case resetSyncAnotherDevicePrompt

    }

    enum ModelRows: Int, CaseIterable {

        case bookmarks
        case bookmarksStubs
        case bookmarksStubsCreate

    }

    enum EnvironmentRows: Int, CaseIterable {

        case toggle

    }

    enum ScopedAccessCredentialsRows: Int, CaseIterable {
        case showThirdPartyRecoveryCode
        case fetchProtectedKeys
        case fetchAccessCredentials
    }

    enum PairingV2Rows: Int, CaseIterable {
        case pairingV2Exchange
        case fetchDevices
    }

    private let bookmarksDatabase: CoreDataDatabase
    private let sync: DDGSyncing
    private let scopedAccessCredentialPurpose = "ai_chats"

    private var isScopedAccessCredentialsEnabled: Bool {
        AppDependencyProvider.shared.featureFlagger.isFeatureOn(.syncScopedAccessCredentials)
    }

    var syncCancellable: Cancellable?

    init?(coder: NSCoder,
          sync: DDGSyncing,
          bookmarksDatabase: CoreDataDatabase) {

        self.sync = sync
        self.bookmarksDatabase = bookmarksDatabase

        super.init(coder: coder)

        syncCancellable = sync.isSyncInProgressPublisher.receive(on: DispatchQueue.main).sink { [weak self] progress in
            if progress == false {
                self?.tableView.reloadData()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        guard self.tableView(tableView, numberOfRowsInSection: section.rawValue) > 0 else { return nil }
        return titles[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.selectionStyle = .default
        
        switch Sections(rawValue: indexPath.section) {

        case .info:
            switch InfoRows(rawValue: indexPath.row) {
            case .syncNow:
                cell.textLabel?.text = "Sync now"
            case .logOut:
                cell.textLabel?.text = "Log out of sync in 10 seconds"
            case .toggleFavoritesDisplayMode:
                cell.textLabel?.text = "Toggle favorites display mode in 10 seconds"
            case .resetFaviconsFetcherOnboardingDialog:
                cell.textLabel?.text = "Reset Favicons Fetcher onboarding dialog"
            case .some(.getRecoveryCode):
                cell.textLabel?.text = "Paste and Copy Recovery Code"
            case .resetSyncAnotherDevicePrompt:
                cell.textLabel?.text = "Reset Sync Another Device prompt"
            case .none:
                break
            }

        case .models:
            switch ModelRows(rawValue: indexPath.row) {
            case .bookmarks:
                cell.textLabel?.text = "Bookmarks to sync"

                let context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
                let fr = BookmarkEntity.fetchRequest()
                fr.predicate = NSPredicate(format: "%K != nil", #keyPath(BookmarkEntity.modifiedAt))

                let result = try? context.count(for: fr)
                if let result {
                    cell.detailTextLabel?.text = "\(result)"
                } else {
                    cell.detailTextLabel?.text = "Error"
                }
            case .bookmarksStubs:
                cell.textLabel?.text = "Bookmark stubs"

                let context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
                let fr = BookmarkEntity.fetchRequest()
                fr.predicate = NSPredicate(format: "%K = TRUE", #keyPath(BookmarkEntity.isStub))

                let result = try? context.count(for: fr)
                if let result {
                    cell.detailTextLabel?.text = "\(result)"
                } else {
                    cell.detailTextLabel?.text = "Error"
                }
            case .bookmarksStubsCreate:
                cell.textLabel?.text = "Tap to create stubs"

            case .none:
                break
            }

        case .environment:
            switch EnvironmentRows(rawValue: indexPath.row) {
            case .toggle:
                let targetEnvironment: ServerEnvironment = sync.serverEnvironment == .production ? .development : .production
                cell.textLabel?.text = sync.serverEnvironment.description
                cell.detailTextLabel?.text = "Click to switch to \(targetEnvironment)"

            case .none:
                break
            }

        case .pairingV2:
            switch PairingV2Rows(rawValue: indexPath.row) {
            case .pairingV2Exchange:
                cell.textLabel?.text = "V2 pairing exchange"
                cell.detailTextLabel?.text = "Create, paste, or exchange with a code2 URL and watch live messages"
            case .fetchDevices:
                cell.textLabel?.text = "Fetch Devices (GET /devices)"
                cell.detailTextLabel?.text = "Display decoded devices response"
            case .none:
                break
            }

        case .scopedAccessCredentials:
            switch ScopedAccessCredentialsRows(rawValue: indexPath.row) {
            case .showThirdPartyRecoveryCode:
                cell.textLabel?.text = "3P Recovery Code"
            case .fetchProtectedKeys:
                cell.textLabel?.text = "Fetch Keys (GET /keys)"
            case .fetchAccessCredentials:
                cell.textLabel?.text = "Fetch Access Credentials (GET /access-credentials)"
            case .none:
                break
            }

        default: break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .info: return InfoRows.allCases.count
        case .models: return ModelRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
        case .pairingV2: return PairingV2Rows.allCases.count
        case .scopedAccessCredentials: return isScopedAccessCredentialsEnabled ? ScopedAccessCredentialsRows.allCases.count : 0
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Sections(rawValue: indexPath.section) {
        case .info:
            switch InfoRows(rawValue: indexPath.row) {
            case .syncNow:
                sync.scheduler.requestSyncImmediately()
            case .logOut:
                Task {
                    try await Task.sleep(nanoseconds: UInt64(10e9))
                    try await sync.disconnect()
                }
            case .toggleFavoritesDisplayMode:
                Task { @MainActor in
                    try await Task.sleep(nanoseconds: UInt64(10e9))
                    var displayMode = AppDependencyProvider.shared.appSettings.favoritesDisplayMode
                    if displayMode.isDisplayUnified {
                        displayMode = .displayNative(.mobile)
                    } else {
                        displayMode = .displayUnified(native: .mobile)
                    }
                    AppDependencyProvider.shared.appSettings.favoritesDisplayMode = displayMode
                    NotificationCenter.default.post(name: AppUserDefaults.Notifications.favoritesDisplayModeChange, object: nil)
                }
            case .resetFaviconsFetcherOnboardingDialog:
                var udWrapper = UserDefaultsWrapper(key: .syncDidPresentFaviconsFetcherOnboarding, defaultValue: false)
                udWrapper.wrappedValue = false
            case .getRecoveryCode:
                showCopyPasteCodeAlert()
            case .resetSyncAnotherDevicePrompt:
                UserDefaults.standard.removeObject(forKey: "sync.simplified.sync-another-device-prompt.shown")
            default: break
            }
        case .models:
            switch ModelRows(rawValue: indexPath.row) {
            case .bookmarksStubsCreate:
                let context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
                
                let root = BookmarkUtils.fetchRootFolder(context)!

                _ = BookmarkEntity.makeBookmark(title: "Non stub", url: "url", parent: root, context: context)
                let stub = BookmarkEntity.makeBookmark(title: "Stub", url: "", parent: root, context: context)
                stub.isStub = true
                let emptyStub = BookmarkEntity.makeBookmark(title: "", url: "", parent: root, context: context)
                emptyStub.isStub = true
                emptyStub.title = nil
                emptyStub.url = nil

                do {
                    try context.save()
                } catch {
                    assertionFailure("Could not create stubs")
                }

                tableView.reloadData()

            default: break
            }
        case .environment:
            switch EnvironmentRows(rawValue: indexPath.row) {
            case .toggle:
                let targetEnvironment: ServerEnvironment = sync.serverEnvironment == .production ? .development : .production
                sync.updateServerEnvironment(targetEnvironment)
                UserDefaults.standard.set(targetEnvironment.description, forKey: UserDefaultsWrapper<String>.Key.syncEnvironment.rawValue)
                tableView.reloadSections(.init(integer: indexPath.section), with: .automatic)
            default: break
            }
        case .pairingV2:
            switch PairingV2Rows(rawValue: indexPath.row) {
            case .pairingV2Exchange:
                let controller = PairingV2DebugViewController(sync: sync,
                                                              deviceName: UIDevice.current.name,
                                                              deviceType: UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone")
                navigationController?.pushViewController(controller, animated: true)
            case .fetchDevices:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let devices = try await self.sync.fetchDevicesRawResponse()
                        await MainActor.run {
                            self.showDebugJSONResponse(title: "GET /devices", responseText: devices)
                        }
                    } catch {
                        await MainActor.run {
                            self.showDebugActionError(error)
                        }
                    }
                }
            case .none:
                break
            }
        case .scopedAccessCredentials:
            switch ScopedAccessCredentialsRows(rawValue: indexPath.row) {
            case .showThirdPartyRecoveryCode:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let code = try await self.sync.prepareThirdPartyRecoveryCode(purpose: self.scopedAccessCredentialPurpose)
                        await MainActor.run {
                            let controller = ScopedAccessRecoveryCodeViewController(recoveryCode: code)
                            self.navigationController?.pushViewController(controller, animated: true)
                        }
                    } catch {
                        await MainActor.run {
                            self.showDebugActionError(error)
                        }
                    }
                }
            case .fetchProtectedKeys:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let keys = try await self.sync.fetchProtectedKeys()
                        await MainActor.run {
                            self.showDebugJSONResponse(title: "GET /keys", response: keys)
                        }
                    } catch {
                        await MainActor.run {
                            self.showDebugActionError(error)
                        }
                    }
                }
            case .fetchAccessCredentials:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let credentials = try await self.sync.fetchAccessCredentials()
                        await MainActor.run {
                            self.showDebugJSONResponse(title: "GET /access-credentials", response: credentials)
                        }
                    } catch {
                        await MainActor.run {
                            self.showDebugActionError(error)
                        }
                    }
                }
            case .none:
                break
            }
        default:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func showCopyPasteCodeAlert() {
        let alertController = UIAlertController(title: "Paste and Copy Recovery Code", message: nil, preferredStyle: .alert)

        alertController.addTextField { textField in
            textField.placeholder = "Enter recovery code here"
        }

        let copyAction = UIAlertAction(title: "Copy", style: .default) { _ in
            if let text = alertController.textFields?.first?.text {
                // Use the text as needed, e.g., copy to the clipboard
                SyncDebugClipboard.copy(text, source: "Paste and Copy Recovery Code alert")
            }
        }
        alertController.addAction(copyAction)

        // Add a "Cancel" action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        // Present the alert
        present(alertController, animated: true, completion: nil)
    }

    private func showDebugActionError(_ error: Error) {
        showDebugActionErrorMessage(error.localizedDescription)
    }

    private func showDebugActionSuccessMessage(_ message: String) {
        let alertController = UIAlertController(title: "Scoped Access Credentials", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func showDebugJSONResponse<T: Encodable>(title: String, response: T) {
        let controller = SyncDebugJSONResponseViewController(title: title, response: response)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showDebugJSONResponse(title: String, responseText: String) {
        let controller = SyncDebugJSONResponseViewController(title: title, responseText: responseText)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showDebugActionErrorMessage(_ message: String) {
        let alertController = UIAlertController(title: "Scoped Access Credentials", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

}

private final class PairingV2DebugViewController: UIViewController {

    private let sync: DDGSyncing
    private let deviceName: String
    private let deviceType: String
    private let startsAsPresenter: Bool
    private var connectionController: SyncConnectionControlling?
    private var scanTask: Task<Void, Never>?
    private var presenterCodeURL: URL?
    private var logEntries: [PairingV2DebugLogEntry] = []

    private let codeTextField = UITextField()
    private let logModeControl = UISegmentedControl(items: ["Summary", "Raw"])
    private let logTextView = UITextView()
    private let runButton = UIButton(type: .system)
    private let createPresenterCodeButton = UIButton(type: .system)
    private let copyPresenterCodeButton = UIButton(type: .system)
    private let clearLogButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    init(sync: DDGSyncing, deviceName: String, deviceType: String, startsAsPresenter: Bool = false) {
        self.sync = sync
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.startsAsPresenter = startsAsPresenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "V2 Pairing Debug"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy Log", style: .plain, target: self, action: #selector(copyLog))

        configureLayout()
        appendSummary("Ready. Paste a V2 code2 URL to start an exchange or create a V2 linking code.")
        if startsAsPresenter {
            createPresenterCode()
        }
    }

    deinit {
        scanTask?.cancel()
    }

    private func configureLayout() {
        codeTextField.borderStyle = .roundedRect
        codeTextField.placeholder = "Paste V2 code2 URL"
        codeTextField.autocapitalizationType = .none
        codeTextField.autocorrectionType = .no
        codeTextField.clearButtonMode = .whileEditing

        logModeControl.selectedSegmentIndex = PairingV2DebugLogMode.summary.rawValue
        logModeControl.addTarget(self, action: #selector(logModeDidChange), for: .valueChanged)

        runButton.setTitle("Start Exchange", for: .normal)
        runButton.addTarget(self, action: #selector(runScan), for: .touchUpInside)

        createPresenterCodeButton.setTitle("Create V2 Linking Code", for: .normal)
        createPresenterCodeButton.addTarget(self, action: #selector(createPresenterCode), for: .touchUpInside)

        copyPresenterCodeButton.setTitle("Copy Linking Code", for: .normal)
        copyPresenterCodeButton.addTarget(self, action: #selector(copyPresenterCode), for: .touchUpInside)

        clearLogButton.setTitle("Clear Log", for: .normal)
        clearLogButton.addTarget(self, action: #selector(clearLog), for: .touchUpInside)

        cancelButton.setTitle("Cancel Exchange", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)

        logTextView.isEditable = false
        logTextView.isScrollEnabled = true
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.textContainerInset = .init(top: 12, left: 12, bottom: 12, right: 12)
        logTextView.layer.cornerRadius = 8
        logTextView.layer.borderWidth = 1
        logTextView.layer.borderColor = UIColor.separator.cgColor
        logTextView.backgroundColor = .secondarySystemBackground

        let scanButtonStackView = UIStackView(arrangedSubviews: [clearLogButton, runButton, cancelButton])
        scanButtonStackView.axis = .horizontal
        scanButtonStackView.distribution = .fillEqually
        scanButtonStackView.spacing = 12

        let linkingCodeButtonStackView = UIStackView(arrangedSubviews: [createPresenterCodeButton, copyPresenterCodeButton])
        linkingCodeButtonStackView.axis = .horizontal
        linkingCodeButtonStackView.distribution = .fillEqually
        linkingCodeButtonStackView.spacing = 12

        let stackView = UIStackView(arrangedSubviews: [codeTextField, scanButtonStackView, linkingCodeButtonStackView, logModeControl, logTextView])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            logTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
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
                    self?.codeTextField.text = url.absoluteString
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

        SyncDebugClipboard.copy(presenterCodeURL.absoluteString, source: "V2 Pairing Debug linking code")
        appendSummary("Copied V2 linking code.")
    }

    @objc private func runScan() {
        guard scanTask == nil else {
            appendSummary("Exchange already in progress.")
            return
        }
        guard let code = codeTextField.text?.trimmingWhitespace(), !code.isEmpty else {
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
        SyncDebugClipboard.copy(logTextView.text, source: "V2 Pairing Debug log")
    }

    @MainActor
    private func appendSummary(_ message: String) {
        appendLog(.init(kind: .summary, message: "* \(message)"))
    }

    @MainActor
    private func appendLog(_ entry: PairingV2DebugLogEntry) {
        logEntries.append(entry)
        renderLog()
    }

    @MainActor
    private func renderLog() {
        let selectedMode = PairingV2DebugLogMode(rawValue: logModeControl.selectedSegmentIndex) ?? .summary
        let selectedKind: PairingV2DebugLogEntry.Kind = selectedMode == .summary ? .summary : .raw
        logTextView.text = logEntries
            .filter { $0.kind == selectedKind }
            .map(\.message)
            .joined(separator: "\n")
        let range = NSRange(location: max(logTextView.text.count - 1, 0), length: 1)
        logTextView.scrollRangeToVisible(range)
    }

    private enum PairingV2DebugLogMode: Int {
        case summary
        case raw
    }
}

private final class SyncDebugJSONResponseViewController: UIViewController {

    private let screenTitle: String
    private let responseText: String
    private let textView = UITextView()

    init<T: Encodable>(title: String, response: T) {
        self.screenTitle = title
        self.responseText = Self.prettyJSON(response)
        super.init(nibName: nil, bundle: nil)
    }

    init(title: String, responseText: String) {
        self.screenTitle = title
        self.responseText = responseText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = screenTitle
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyResponse))

        configureLayout()
    }

    private func configureLayout() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = .init(top: 12, left: 12, bottom: 12, right: 12)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.backgroundColor = .secondarySystemBackground
        textView.text = responseText

        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    @objc private func copyResponse() {
        SyncDebugClipboard.copy(responseText, source: "\(screenTitle) response")
    }

    private static func prettyJSON<T: Encodable>(_ response: T) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(response),
              let string = String(data: data, encoding: .utf8) else {
            return "<unable to encode response>"
        }
        return string
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
            let alertController = UIAlertController(title: "Sync your data?", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alertController.addAction(UIAlertAction(title: "Sync", style: .default) { _ in
                continuation.resume(returning: true)
            })
            present(alertController, animated: true)
        }
    }
}

private final class ScopedAccessRecoveryCodeViewController: UIViewController {

    private let recoveryCode: String
    private let qrImageView = UIImageView()
    private let recoveryCodeTextView = UITextView()

    init(recoveryCode: String) {
        self.recoveryCode = recoveryCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "3P Recovery Code"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyRecoveryCode))

        configureLayout()
        configureContent()
    }

    private func configureLayout() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.layer.borderColor = UIColor.separator.cgColor
        qrImageView.layer.borderWidth = 1

        recoveryCodeTextView.translatesAutoresizingMaskIntoConstraints = false
        recoveryCodeTextView.isEditable = false
        recoveryCodeTextView.isScrollEnabled = true
        recoveryCodeTextView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        recoveryCodeTextView.textContainerInset = .init(top: 12, left: 12, bottom: 12, right: 12)
        recoveryCodeTextView.layer.cornerRadius = 8
        recoveryCodeTextView.layer.borderWidth = 1
        recoveryCodeTextView.layer.borderColor = UIColor.separator.cgColor
        recoveryCodeTextView.backgroundColor = .secondarySystemBackground

        stackView.addArrangedSubview(qrImageView)
        stackView.addArrangedSubview(recoveryCodeTextView)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            qrImageView.widthAnchor.constraint(equalToConstant: 280),
            qrImageView.heightAnchor.constraint(equalToConstant: 280),
            recoveryCodeTextView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            recoveryCodeTextView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func configureContent() {
        recoveryCodeTextView.text = recoveryCode
        qrImageView.image = makeQRCodeImage(from: recoveryCode)
    }

    @objc private func copyRecoveryCode() {
        SyncDebugClipboard.copy(recoveryCode, source: "3P Recovery Code view")
    }

    private func makeQRCodeImage(from value: String) -> UIImage? {
        let context = CIContext()
        let payload = Data(value.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        let renderSize = 560.0

        for correctionLevel in ["M", "L"] {
            filter.setValue(payload, forKey: "inputMessage")
            filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
            guard let outputImage = filter.outputImage else {
                continue
            }

            let baseSize = outputImage.extent.size.width
            let scaleFactor = floor(renderSize / baseSize)
            guard scaleFactor >= 1 else {
                continue
            }

            let transformed = outputImage.transformed(by: .init(scaleX: scaleFactor, y: scaleFactor))
            let colored = transformed.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor(color: .black),
                "inputColor1": CIColor(color: .white)
            ])

            if let cgImage = context.createCGImage(colored, from: colored.extent) {
                return UIImage(cgImage: cgImage)
            }
        }

        return nil
    }
}
