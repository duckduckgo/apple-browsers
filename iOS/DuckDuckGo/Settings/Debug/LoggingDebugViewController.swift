//
//  LoggingDebugViewController.swift
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
import Core

class LoggingDebugViewController: UITableViewController {

    let defaults = AppUserDefaults()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Logging"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Autofill"
        case 1: return "Content Scope Scripts"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        switch indexPath.section {
        case 0: // Autofill
            cell.textLabel?.text = "Autofill Debug Script"
            cell.accessoryType = defaults.autofillDebugScriptEnabled ? .checkmark : .none
        case 1: // Content Scope Scripts
            cell.textLabel?.text = "Content Scope Scripts Debug"
            cell.accessoryType = defaults.contentScopeDebugStateEnabled ? .checkmark : .none
        default:
            break
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let cell = tableView.cellForRow(at: indexPath)
        
        switch indexPath.section {
        case 0: // Autofill
            defaults.autofillDebugScriptEnabled.toggle()
            cell?.accessoryType = defaults.autofillDebugScriptEnabled ? .checkmark : .none
            NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.autofillDebugScriptToggled))
            
        case 1: // Content Scope Scripts
            defaults.contentScopeDebugStateEnabled.toggle()
            cell?.accessoryType = defaults.contentScopeDebugStateEnabled ? .checkmark : .none
            NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.contentScopeDebugStateToggled))
            
        default:
            break
        }
    }
}
