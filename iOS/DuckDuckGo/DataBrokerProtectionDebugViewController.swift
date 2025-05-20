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
import DataBrokerProtectionCore
import DataBrokerProtection_iOS

final class DataBrokerProtectionDebugViewController: UITableViewController {

    enum Sections: Int, CaseIterable {
        case database

        var title: String {
            switch self {
            case .database:
                return "Database"
            }
        }
    }

    enum DatabaseRows: Int, CaseIterable {
        case databaseBrowser
        case saveProfile

        var title: String {
            switch self {
            case .databaseBrowser:
                return "Database Browser"
            case .saveProfile:
                return "Save Profile"
            }
        }
    }

    // MARK: Properties

    // MARK: Lifecycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)
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
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none

        switch Sections(rawValue: indexPath.section) {

        case .database:
            let row = DatabaseRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .database: return DatabaseRows.allCases.count
        case .none: return 0

        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Sections(rawValue: indexPath.section) {
        case .database:
            didSelectDatabase(at: indexPath)
        case .none:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func didSelectDatabase(at indexPath: IndexPath) {
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


        case .none:
            return
        }
    }
}
