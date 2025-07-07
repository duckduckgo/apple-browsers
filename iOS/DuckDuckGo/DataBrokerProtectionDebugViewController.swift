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

final class DataBrokerProtectionDebugViewController: UITableViewController {

    enum Sections: Int, CaseIterable {
        case healthOverview
        case database

        var title: String {
            switch self {
            case .healthOverview:
                return "Health Overview"
            case .database:
                return "Database"
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
        case runPrerequesitesMet(jobScheduled: Bool)

        var rowCount: Int {
            switch self {
            case .loading:
                return 1
            case .runPrerequisitesNotMet:
                return 3
            case .runPrerequesitesMet:
                return 1
            }
        }
    }

    private var manager: DataBrokerProtectionIOSManager
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
    }

    private func loadHealthOverview() {
        Task {
            if await manager.validateRunPrerequisites() {
                let allScheduledTasks = await BGTaskScheduler.shared.pendingTaskRequests()
                let dbpScheduledTasks = allScheduledTasks.filter {
                    $0.identifier == DataBrokerProtectionIOSManager.backgroundJobIdentifier
                }

                self.healthOverview = .runPrerequesitesMet(jobScheduled: !dbpScheduledTasks.isEmpty)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        cell.textLabel?.font = .daxBodyRegular()
        cell.textLabel?.textColor = nil
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.font = nil
        cell.accessoryType = .none

        switch Sections(rawValue: indexPath.section) {

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
            case .runPrerequesitesMet(let jobScheduled):
                if jobScheduled {
                    cell.textLabel?.text = "✅ PIR will run some time after device is locked and connected to power"
                } else {
                    if UIApplication.shared.backgroundRefreshStatus == .available {
                        cell.textLabel?.text = "❌ Restart the app to schedule PIR"
                    } else {
                        cell.textLabel?.text = "❌ Enable \"Background App Refresh\" in the app's privacy settings"
                    }
                }
            }

        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .healthOverview: return self.healthOverview.rowCount
        case .database: return DatabaseRows.allCases.count
        case .none: return 0

        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Sections(rawValue: indexPath.section) {
        case .database:
            didSelectDatabaseRow(at: indexPath)
        case .healthOverview:
            break
        case .none:
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

    // MARK: - Database Rows

    private func didSelectDatabaseRow(at indexPath: IndexPath) {
        guard let dbpManager = DataBrokerProtectionIOSManager.shared else {
            assertionFailure("DataBrokerProtectionIOSManager not initialized")
            return
        }

        switch DatabaseRows(rawValue: indexPath.row) {
        case .databaseBrowser:
            let dbBrowser = DebugDatabaseBrowserViewController(database: dbpManager.database)
            self.navigationController?.pushViewController(dbBrowser, animated: true)

        case .saveProfile:
            let saveProfileViewController = DebugSaveProfileViewController(database: dbpManager.database)
            self.navigationController?.pushViewController(saveProfileViewController, animated: true)

        case .deviceIdentifier:
            break

        case .deleteAllData:
            presentDeleteAllDataAlertController()

        case .none:
            return
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

    // MARK: - Database Rows

}
