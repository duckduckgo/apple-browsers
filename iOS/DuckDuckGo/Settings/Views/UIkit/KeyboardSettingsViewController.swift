//
//  KeyboardSettingsViewController.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import SwiftUI
import DesignResourcesKit
import Core

class KeyboardSettingsViewController: UITableViewController {
    
    @IBOutlet var labels: [UILabel]!

    @IBOutlet weak var newTabToggle: UISwitch!
    @IBOutlet weak var appLaunchToggle: UISwitch!
    
    var settings = KeyboardSettings()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        newTabToggle.isOn = settings.onNewTab
        appLaunchToggle.isOn = settings.onAppLaunch
        
        decorate()
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let theme = ThemeManager.shared.currentTheme
        cell.decorate(with: theme)
    }
    
    @IBAction func onNewTabValueChanged(_ sender: Any) {
        settings.onNewTab = newTabToggle.isOn
    }
        
    @IBAction func onAppLaunchValueChanged(_ sender: Any) {
        settings.onAppLaunch = appLaunchToggle.isOn
    }
    
}

extension KeyboardSettingsViewController {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        
        for label in labels {
            label.textColor = theme.tableCellTextColor
        }

        newTabToggle.onTintColor = theme.buttonTintColor
        appLaunchToggle.onTintColor = theme.buttonTintColor

        tableView.backgroundColor = theme.backgroundColor
        tableView.separatorColor = theme.tableCellSeparatorColor
        
        tableView.reloadData()
    }
}

struct KeyboardSettingsView: View {
    @State private var settings = KeyboardSettings()

    var body: some View {
        List {
            Section(header: Text(Self.storyboardString("tGh-di-rfq.headerTitle", value: "Show keyboard on"))) {
                SettingsCellView(label: Self.storyboardString("Zpg-h0-rYv.text", value: "New Tab"),
                                 accessory: .toggle(isOn: $settings.onNewTab))
                SettingsCellView(label: Self.storyboardString("13n-KI-KLq.text", value: "App Launch"),
                                 accessory: .toggle(isOn: $settings.onAppLaunch))
            }
        }
        .applyInsetGroupedListStyle()
        .navigationBarTitle(UserText.settingsKeyboard, displayMode: .inline)
        .accentColor(Color(designSystemColor: .textPrimary))
    }

    /// Looks up the Keyboard storyboard's own translations, so this screen adds no strings to translate.
    private static func storyboardString(_ key: String, value: String) -> String {
        Bundle.main.localizedString(forKey: key, value: value, table: "Settings")
    }
}
