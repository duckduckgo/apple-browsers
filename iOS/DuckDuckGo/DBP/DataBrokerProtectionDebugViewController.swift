//
//  DataBrokerProtectionDebugViewController.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common
import BackgroundTasks
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import Core
import Subscription

final class DataBrokerProtectionDebugViewController: UITableViewController {

    enum CellType: String {
        case rightDetail
        case subtitle
    }
    enum Sections: Int, CaseIterable {
        case healthOverview
        case database
        case debugActions
        case environment

        var title: String {
            switch self {
            case .healthOverview:
                return "Health Overview"
            case .database:
                return "Database"
            case .debugActions:
                return "Debug Actions"
            case .environment:
                return "Environment"
            }
        }

        func cellType(for row: Int) -> CellType {
            switch self {
            case .healthOverview:
                return .rightDetail
            case .database:
                if row == DatabaseRows.deviceIdentifier.rawValue {
                    return .subtitle
                } else {
                    return .rightDetail
                }
            case .debugActions:
                return .rightDetail
            case .environment:
                return .subtitle
            }
        }
    }

    enum DatabaseRows: Int, CaseIterable {
        case databaseBrowser
        case saveProfile
        case deviceIdentifier
        case deleteAllData

        var title: String {
            switch self {
            case .databaseBrowser:
                return "Database Browser"
            case .saveProfile:
                return "Save Profile"
            case .deviceIdentifier:
#if DEBUG || ALPHA
                return "UUID"
#else
                return "No UUID due to wrong build type"
#endif
            case .deleteAllData:
                return "Delete All Data"
            }
        }
    }

    enum HealthOverviewRows {
        case loading
        case runPrerequisitesNotMet(hasAccount: Bool, hasEntitlement: Bool, hasProfile: Bool)
        case runPrerequisitesMet(jobScheduled: Bool)

        var rowCount: Int {
            switch self {
            case .loading:
                return 1
            case .runPrerequisitesNotMet:
                return 3
            case .runPrerequisitesMet:
                return 1
            }
        }
    }

    enum DebugActionRows: Int, CaseIterable {
        case forceBrokerJSONRefresh
        case runPIRDebugMode

        var title: String {
            switch self {
            case .forceBrokerJSONRefresh:
                return "Force Broker JSON Refresh"
            case .runPIRDebugMode:
                return "Run PIR Debug Mode"
            }
        }
    }

    enum EnvironmentRows: Int, CaseIterable {
        case subscriptionEnvironment
        case dbpAPI
        case webURL

        var title: String {
            switch self {
            case .subscriptionEnvironment:
                return "Environment"
            case .dbpAPI:
                return "DBP API Endpoint"
            case .webURL:
                return "Custom Web URL"
            }
        }
    }

    private var manager: DataBrokerProtectionIOSManager
    private let settings = DataBrokerProtectionSettings(defaults: .dbp)
    private let webUISettings = DataBrokerProtectionWebUIURLSettings(.dbp)

    private lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: DatabaseConstants.directoryName,
            fileName: DatabaseConstants.fileName,
            appGroupIdentifier: nil
        )

        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)
        guard let vault = try? vaultFactory.makeVault(reporter: nil) else {
            return nil
        }

        let appDependencies = AppDependencyProvider.shared
        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: appDependencies.subscriptionAuthV1toV2Bridge,
            runTypeProvider: appDependencies.dbpSettings,
            isAuthV2Enabled: appDependencies.isUsingAuthV2
        )

        let authenticationManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        let featureFlagger = DBPFeatureFlagger(appDependencies: appDependencies)

        return RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                       settings: self.settings,
                                       vault: vault,
                                       authenticationManager: authenticationManager,
                                       localBrokerProvider: nil)
    }()

    @MainActor private var healthOverview: HealthOverviewRows = .loading {
        didSet {
            tableView.reloadData()
        }
    }

    // MARK: Lifecycle

    required init?(coder: NSCoder) {
        self.manager = DataBrokerProtectionIOSManager.shared!

        super.init(coder: coder)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadHealthOverview()
        tableView.reloadData()
    }

    private func loadHealthOverview() {
        Task {
            if await manager.validateRunPrerequisites() {
                let allScheduledTasks = await BGTaskScheduler.shared.pendingTaskRequests()
                let dbpScheduledTasks = allScheduledTasks.filter {
                    $0.identifier == DataBrokerProtectionIOSManager.backgroundJobIdentifier
                }

                self.healthOverview = .runPrerequisitesMet(jobScheduled: !dbpScheduledTasks.isEmpty)
            } else {
                let hasAccount = manager.meetsAuthenticationRunPrequisite
                let hasEntitlement = (try? await manager.meetsEntitlementRunPrequisite) ?? false
                let hasProfile = (try? manager.meetsProfileRunPrequisite) ?? false

                self.healthOverview = .runPrerequisitesNotMet(
                    hasAccount: hasAccount,
                    hasEntitlement: hasEntitlement,
                    hasProfile: hasProfile
                )
            }
        }
    }

    // MARK: Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        return section.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Sections(rawValue: indexPath.section) else {
            fatalError("Failed to create a Section from index '\(indexPath.section)'")
        }

        let identifier = section.cellType(for: indexPath.row)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier.rawValue, for: indexPath)

        cell.textLabel?.font = .daxBodyRegular()
        cell.textLabel?.textColor = nil
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.font = nil
        cell.accessoryType = .none

        switch section {
        case .database:
            let row = DatabaseRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

            switch row {
            case .databaseBrowser, .saveProfile, nil: break
            case .deviceIdentifier:
                cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
                cell.detailTextLabel?.text = DataBrokerProtectionSettings.deviceIdentifier
            case .deleteAllData:
                cell.textLabel?.textColor = .systemRed
            }

        case .healthOverview:
            switch self.healthOverview {
            case .loading: cell.textLabel?.text = "Loading..."
            case .runPrerequisitesNotMet(let hasAccount, let hasEntitlement, let hasProfile):
                if indexPath.row == 0 {
                    cell.textLabel?.text = "Privacy Pro Account"
                    cell.detailTextLabel?.text = hasAccount ? "✅" :"❌"
                } else if indexPath.row == 1 {
                    cell.textLabel?.text = "PIR Entitlement"
                    cell.detailTextLabel?.text = hasEntitlement ? "✅" :"❌"
                } else if indexPath.row == 2 {
                    cell.textLabel?.text = "Profile Saved In DB"
                    cell.detailTextLabel?.text = hasProfile ? "✅" :"❌"
                } else {
                    fatalError("Expected 3 rows for the health overview")
                }
            case .runPrerequisitesMet(let jobScheduled):
                if jobScheduled {
                    cell.textLabel?.text = "✅ PIR will run some time after device is locked and connected to power"
                } else {
#if targetEnvironment(simulator)
                    cell.textLabel?.text = "❌ Background jobs won't run in the simulator automatically"
#else
                    if UIApplication.shared.backgroundRefreshStatus == .available {
                        cell.textLabel?.text = "❌ Restart the app to schedule PIR"
                    } else {
                        cell.textLabel?.text = "❌ Enable \"Background App Refresh\" in the app's privacy settings"
                    }
#endif
                }
            }

        case .debugActions:
            let row = DebugActionRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

        case .environment:
            let row = EnvironmentRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

            switch row {
            case .subscriptionEnvironment:
                cell.detailTextLabel?.text = settings.selectedEnvironment.rawValue.localizedCapitalized
            case .dbpAPI:
                cell.detailTextLabel?.text = settings.endpointURL.absoluteString
            case .webURL:
                let urlType = webUISettings.selectedURLType
                let customURL = webUISettings.customURL
                var detailText = ""

                if urlType == .production {
                    detailText = "Production: \(webUISettings.productionURL)"
                } else if urlType == .custom, let customURL {
                    detailText = "Custom: \(customURL)"
                } else {
                    detailText = "Unsupported URL type: \(urlType)"
                }

                cell.detailTextLabel?.text = detailText
            default: break
            }
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .healthOverview: return self.healthOverview.rowCount
        case .database: return DatabaseRows.allCases.count
        case .debugActions: return DebugActionRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Sections(rawValue: indexPath.section) else { return }

        switch section {
        case .database:
            guard let row = DatabaseRows(rawValue: indexPath.row) else { return }
            handleDatabaseAction(for: row)
        case .debugActions:
            guard let row = DebugActionRows(rawValue: indexPath.row) else { return }
            handleDebugAction(for: row)
        case .environment:
            guard let row = EnvironmentRows(rawValue: indexPath.row) else { return }
            handleEnvironmentAction(for: row)
        case .healthOverview:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let section = Sections(rawValue: indexPath.section), section == .database,
              let row = DatabaseRows(rawValue: indexPath.row), row == .deviceIdentifier else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = DataBrokerProtectionSettings.deviceIdentifier
            }

            return UIMenu(title: "", children: [copyAction])
        }
    }

    // MARK: - Debug Action Rows

    private func handleDebugAction(for row: DebugActionRows) {
        switch row {
        case .runPIRDebugMode:
            let debugModeViewController = RunDBPDebugModeViewController()
            self.navigationController?.pushViewController(debugModeViewController, animated: true)
        case .forceBrokerJSONRefresh:
            Task { @MainActor in
                if let brokerUpdater {
                    try await brokerUpdater.checkForUpdates(skipsLimiter: true)

                    tableView.reloadData()
                } else {
                    assertionFailure("Failed to create broker updater")
                }
            }
        }
    }

    // MARK: - Database Rows

    private func handleDatabaseAction(for row: DatabaseRows) {
        switch row {
        case .databaseBrowser:
            let dbBrowser = DebugDatabaseBrowserViewController(database: manager.database)
            self.navigationController?.pushViewController(dbBrowser, animated: true)
        case .saveProfile:
            let saveProfileViewController = DebugSaveProfileViewController(database: manager.database)
            self.navigationController?.pushViewController(saveProfileViewController, animated: true)
        case .deleteAllData:
            presentDeleteAllDataAlertController()
        case .deviceIdentifier:
            break
        }
    }

    private func presentDeleteAllDataAlertController() {
        let alert = UIAlertController(title: "Delete All PIR Data?", message: "This will remove all data and statistics from the PIR database, and give you a new tester ID.", preferredStyle: .alert)
        alert.addAction(title: "Delete All Data", style: .destructive) { [weak self] in
            try? self?.manager.deleteAllData()
            DataBrokerProtectionSettings.incrementDeviceIdentifier()
            self?.tableView.reloadData()
        }

        alert.addAction(title: "Cancel", style: .cancel)

        present(alert, animated: true)
    }

    // MARK: - Environment Rows

    private func handleEnvironmentAction(for row: EnvironmentRows) {
        switch row {
        case .subscriptionEnvironment:
            let alert = UIAlertController(title: "PIR Environment", message: "The PIR environment can be changed by changing the Subscription environment.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
        case .dbpAPI:
            setCustomServiceRoot()
        case .webURL:
            presentWebURLActionSheet()
        }
    }

    private func presentWebURLActionSheet() {
        let actionSheet = UIAlertController(title: "Web URL Options", message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: "Use Production URL", style: .default, handler: { [weak self] _ in
            self?.useWebUIProductionURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Use Custom URL", style: .default, handler: { [weak self] _ in
            self?.useWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Set Custom URL", style: .default, handler: { [weak self] _ in
            self?.setWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Reset Custom URL to Production", style: .destructive, handler: { [weak self] _ in
            self?.resetWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popoverController = actionSheet.popoverPresentationController {
            if let cell = tableView.cellForRow(at: IndexPath(row: EnvironmentRows.webURL.rawValue, section: Sections.environment.rawValue)) {
                popoverController.sourceView = cell
                popoverController.sourceRect = cell.bounds
            }
        }

        present(actionSheet, animated: true)
    }

    // MARK: - Web UI URL Actions

    private func setWebUICustomURL() {
        let alert = UIAlertController(title: "Set Custom Web URL",
                                      message: "Enter the full URL",
                                      preferredStyle: .alert)

        alert.addTextField { [weak self] textField in
            // When setting a custom URL, show the existing one if found, otherwise leave it blank
            textField.text = self?.webUISettings.customURL
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let value = textField.text,
                  let url = URL(string: value), url.isValid else {
                return
            }
            self?.webUISettings.setCustomURL(value)
            self?.webUISettings.setURLType(.custom)
            self?.tableView.reloadData()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    private func resetWebUICustomURL() {
        webUISettings.setURLType(.production)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    private func useWebUIProductionURL() {
        webUISettings.setURLType(.production)
    }

    private func useWebUICustomURL() {
        webUISettings.setURLType(.custom)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    // MARK: - DBP API Actions

    private func setCustomServiceRoot() {
        let alert = UIAlertController(title: "Set Custom DBP API Service Root",
                                      message: "Enter the base URL for the DBP API. This value is only applied when using the staging environment. Leave empty to reset to default.\n\n⚠️ Please reopen PIR and trigger a new scan for the changes to show up.",
                                      preferredStyle: .alert)

        alert.addTextField { textField in
            textField.text = self.settings.serviceRoot
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let value = textField.text else {
                return
            }

            self?.settings.serviceRoot = value
            try? self?.manager.deleteAllData()
            try? self?.forceBrokerJSONFilesUpdate()
            self?.tableView.reloadData()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    private func removeAllBrokerData() {
        do {
            try manager.deleteAllData()
            Logger.dataBrokerProtection.log("Successfully removed all broker data.")
        } catch {
            Logger.dataBrokerProtection.error("Failed to remove all broker data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Remote Broker JSON Service Usage
    
    private func checkForBrokerUpdates() {
        guard let brokerUpdater = brokerUpdater else {
            Logger.dataBrokerProtection.error("Failed to initialize RemoteBrokerJSONService")
            return
        }
        
        Task {
            do {
                try forceBrokerJSONFilesUpdate()
                Logger.dataBrokerProtection.log("Successfully checked for broker updates")
            } catch {
                Logger.dataBrokerProtection.error("Failed to check for broker updates: \(error.localizedDescription)")
            }
        }
    }

    private func forceBrokerJSONFilesUpdate() throws {
        Task {
            settings.resetBrokerDeliveryData()
            try await brokerUpdater?.checkForUpdates(skipsLimiter: true)
        }
    }
}

extension URL {
    var isValid: Bool {
        return scheme != nil && host != nil
    }
}
