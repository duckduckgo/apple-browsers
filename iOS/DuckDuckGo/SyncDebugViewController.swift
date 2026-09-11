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

class SyncDebugViewController: UITableViewController {

    private let titles = [
        Sections.info: "Info",
        Sections.unifiedDevices: "Unified Devices",
        Sections.testActions: "Test Actions",
        Sections.models: "Models",
        Sections.environment: "Environment"
    ]

    enum Sections: Int, CaseIterable {

        case info
        case unifiedDevices
        case testActions
        case models
        case environment

    }

    enum InfoRows: Int, CaseIterable {

        case syncNow
        case logOut
        case toggleFavoritesDisplayMode
        case resetFaviconsFetcherOnboardingDialog
        case getRecoveryCode
        case resetSyncAnotherDevicePrompt

    }

    enum UnifiedDeviceRows: Int, CaseIterable {

        case accountInfoKey
        case migration
        case refreshDevices

    }

    enum TestActionRows: Int, CaseIterable {

        case ensureAccountInfoKey
        case runMigration
        case resetMigrationMarker

    }

    enum ModelRows: Int, CaseIterable {

        case bookmarks
        case bookmarksStubs
        case bookmarksStubsCreate

    }

    enum EnvironmentRows: Int, CaseIterable {

        case toggle

    }

    private let bookmarksDatabase: CoreDataDatabase
    private let sync: DDGSyncing
    private var debugDevices: [RegisteredDeviceDebugInfo] = []
    private var accountInfoKeyStatus = "Not checked"
    private var migrationStatus = "Not checked"
    private var isRefreshingDevices = false

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

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshMigrationStatus()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        return titles[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        cell.textLabel?.text = nil
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none
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

        case .unifiedDevices:
            if let row = UnifiedDeviceRows(rawValue: indexPath.row) {
                switch row {
                case .accountInfoKey:
                    cell.textLabel?.text = "Account info key"
                    cell.detailTextLabel?.text = accountInfoKeyStatus
                    cell.accessoryType = .disclosureIndicator
                case .migration:
                    cell.textLabel?.text = "Migration"
                    cell.detailTextLabel?.text = migrationStatus
                    cell.selectionStyle = .none
                case .refreshDevices:
                    cell.textLabel?.text = "Refresh devices"
                    cell.detailTextLabel?.text = isRefreshingDevices ? "Loading…" : nil
                    cell.selectionStyle = isRefreshingDevices ? .none : .default
                }
            } else {
                let debugDevice = debugDevices[indexPath.row - UnifiedDeviceRows.allCases.count]
                let device = debugDevice.device
                let isCurrentDevice = device.id == sync.account?.deviceId
                cell.textLabel?.text = isCurrentDevice ? "\(device.name) (this device)" : device.name
                cell.detailTextLabel?.text = [
                    device.type,
                    device.credentialId ?? SyncCredentialID.defaultCredential,
                    sourceDescription(for: debugDevice)
                ].joined(separator: " • ")
                cell.accessoryType = .disclosureIndicator
            }

        case .testActions:
            switch TestActionRows(rawValue: indexPath.row) {
            case .ensureAccountInfoKey:
                cell.textLabel?.text = "Ensure/repair account_info key"
            case .runMigration:
                cell.textLabel?.text = "Run device_info migration"
            case .resetMigrationMarker:
                cell.textLabel?.text = "Reset migration marker"
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

        default: break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .info: return InfoRows.allCases.count
        case .unifiedDevices: return UnifiedDeviceRows.allCases.count + debugDevices.count
        case .testActions: return TestActionRows.allCases.count
        case .models: return ModelRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
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
        case .unifiedDevices:
            if let row = UnifiedDeviceRows(rawValue: indexPath.row) {
                switch row {
                case .accountInfoKey:
                    validateAccountInfoKey()
                case .migration:
                    break
                case .refreshDevices:
                    refreshDevicesForDebug()
                }
            } else {
                let debugDevice = debugDevices[indexPath.row - UnifiedDeviceRows.allCases.count]
                showDeviceDetails(debugDevice)
            }
        case .testActions:
            switch TestActionRows(rawValue: indexPath.row) {
            case .ensureAccountInfoKey:
                ensureAccountInfoKey()
            case .runMigration:
                runDeviceInfoMigration()
            case .resetMigrationMarker:
                confirmResetMigrationMarker()
            case .none:
                break
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
        default: break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func ensureAccountInfoKey() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let wrapperCount = try await sync.ensureAccountInfoKeyForDebug()
                let message: String
                if wrapperCount == 0 {
                    message = "No wrappers were returned."
                } else if wrapperCount == 1 {
                    message = "Ensured 1 wrapper."
                } else {
                    message = "Ensured \(wrapperCount) wrappers."
                }
                accountInfoKeyStatus = message
                reloadUnifiedDevicesSection()
                showAlert(title: "Account Info Key Ensured", message: message)
            } catch {
                showAlert(title: "Unable to Ensure Account Info Key", message: String(reflecting: error))
            }
        }
    }

    private func validateAccountInfoKey() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let result = try await sync.validateAccountInfoKeyForDebug()
                guard result.refreshedKeyID == result.reloadedKeyID else {
                    let message = """
                    Refreshed key ID: \(result.refreshedKeyID)
                    Reloaded key ID: \(result.reloadedKeyID)
                    """
                    accountInfoKeyStatus = "Reload mismatch"
                    reloadUnifiedDevicesSection()
                    showAlert(title: "Account Info Key Reload Mismatch", message: message)
                    return
                }

                accountInfoKeyStatus = "\(abbreviatedKeyID(result.reloadedKeyID)) • \(result.keySizeInBits)-bit"
                reloadUnifiedDevicesSection()
                let message = """
                Key ID: \(result.reloadedKeyID)
                Key size: \(result.keySizeInBits) bits
                Cache-first reload: succeeded
                """
                showAlert(title: "Account Info Key Validated", message: message)
            } catch {
                showAlert(title: "Unable to Validate Account Info Key", message: String(reflecting: error))
            }
        }
    }

    private func refreshDevicesForDebug() {
        guard !isRefreshingDevices else { return }

        isRefreshingDevices = true
        reloadUnifiedDevicesSection()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isRefreshingDevices = false
                reloadUnifiedDevicesSection()
            }

            do {
                debugDevices = try await sync.fetchDevicesForDebug()
            } catch {
                debugDevices = []
                showAlert(title: "Unable to Fetch Devices", message: String(reflecting: error))
            }
        }
    }

    private func refreshMigrationStatus() {
        do {
            migrationStatus = try sync.isDeviceInfoMigrationCompleteForDebug() ? "Complete" : "Not complete"
        } catch {
            migrationStatus = "Unavailable"
        }
        reloadUnifiedDevicesSection()
    }

    private func runDeviceInfoMigration() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await sync.runDeviceInfoMigrationForDebug()
                refreshMigrationStatus()
                let isComplete = try sync.isDeviceInfoMigrationCompleteForDebug()
                let message = isComplete ? "Migration is complete." : "Migration did not complete. Check the Sync logs for details."
                showAlert(title: "Device Info Migration", message: message)
                refreshDevicesForDebug()
            } catch {
                showAlert(title: "Unable to Run Migration", message: String(reflecting: error))
            }
        }
    }

    private func confirmResetMigrationMarker() {
        let alertController = UIAlertController(
            title: "Reset Migration Marker?",
            message: "The next migration run will attempt to write device_info again.",
            preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self else { return }
            sync.resetDeviceInfoMigrationForDebug()
            refreshMigrationStatus()
        })
        present(alertController, animated: true)
    }

    private func showDeviceDetails(_ debugDevice: RegisteredDeviceDebugInfo) {
        let device = debugDevice.device
        let issue = debugDevice.deviceInfoIssue ?? "None"
        let message = """
        ID: \(device.id)
        Type: \(device.type)
        Credential: \(device.credentialId ?? SyncCredentialID.defaultCredential)
        Source: \(sourceDescription(for: debugDevice))
        Device info issue: \(issue)
        """
        let alertController = UIAlertController(title: device.name, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Copy ID", style: .default) { _ in
            UIPasteboard.general.string = device.id
        })
        alertController.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alertController, animated: true)
    }

    private func sourceDescription(for debugDevice: RegisteredDeviceDebugInfo) -> String {
        switch debugDevice.source {
        case .deviceInfo:
            return debugDevice.source.rawValue
        case .legacy:
            return debugDevice.deviceInfoIssue == nil ? "legacy" : "legacy fallback"
        case .placeholder:
            return "placeholder"
        }
    }

    private func abbreviatedKeyID(_ keyID: String) -> String {
        guard keyID.count > 12 else { return keyID }
        return "…\(keyID.suffix(12))"
    }

    private func reloadUnifiedDevicesSection() {
        guard isViewLoaded else { return }
        tableView.reloadSections(IndexSet(integer: Sections.unifiedDevices.rawValue), with: .automatic)
    }

    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func showCopyPasteCodeAlert() {
        let alertController = UIAlertController(title: "Paste and Copy Recovery Code", message: nil, preferredStyle: .alert)

        alertController.addTextField { textField in
            textField.placeholder = "Enter recovery code here"
        }

        let copyAction = UIAlertAction(title: "Copy", style: .default) { _ in
            if let text = alertController.textFields?.first?.text {
                // Use the text as needed, e.g., copy to the clipboard
                UIPasteboard.general.string = text
            }
        }
        alertController.addAction(copyAction)

        // Add a "Cancel" action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        // Present the alert
        present(alertController, animated: true, completion: nil)
    }

}
