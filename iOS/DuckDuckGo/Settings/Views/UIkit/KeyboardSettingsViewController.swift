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

final class KeyboardSettingsViewController: UITableViewController {

    private let newTabToggle = UISwitch()
    private let appLaunchToggle = UISwitch()
    private var settings = KeyboardSettings()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = UserText.settingsKeyboard
        tableView.rowHeight = UITableView.automaticDimension
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = 18

        newTabToggle.isOn = settings.onNewTab
        newTabToggle.accessibilityLabel = UserText.settingsKeyboardNewTab
        newTabToggle.addTarget(self, action: #selector(onNewTabValueChanged), for: .valueChanged)

        appLaunchToggle.isOn = settings.onAppLaunch
        appLaunchToggle.accessibilityLabel = UserText.settingsKeyboardAppLaunch
        appLaunchToggle.addTarget(self, action: #selector(onAppLaunchValueChanged), for: .valueChanged)

        let theme = ThemeManager.shared.currentTheme
        newTabToggle.onTintColor = theme.buttonTintColor
        appLaunchToggle.onTintColor = theme.buttonTintColor
        tableView.backgroundColor = theme.backgroundColor
        tableView.separatorColor = theme.tableCellSeparatorColor
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        UserText.settingsKeyboardShowOn
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isNewTab = indexPath.row == 0
        let toggle = isNewTab ? newTabToggle : appLaunchToggle
        let label = UILabel()
        label.text = isNewTab ? UserText.settingsKeyboardNewTab : UserText.settingsKeyboardAppLaunch
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.textColor = ThemeManager.shared.currentTheme.tableCellTextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(toggle)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            toggle.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 20),
            toggle.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.decorate(with: ThemeManager.shared.currentTheme)
    }

    @objc private func onNewTabValueChanged() {
        settings.onNewTab = newTabToggle.isOn
    }

    @objc private func onAppLaunchValueChanged() {
        settings.onAppLaunch = appLaunchToggle.isOn
    }
}

struct KeyboardSettingsView: View {
    @State private var settings = KeyboardSettings()

    var body: some View {
        List {
            Section(header: Text(UserText.settingsKeyboardShowOn)) {
                SettingsCellView(label: UserText.settingsKeyboardNewTab,
                                 accessory: .toggle(isOn: $settings.onNewTab))
                SettingsCellView(label: UserText.settingsKeyboardAppLaunch,
                                 accessory: .toggle(isOn: $settings.onAppLaunch))
            }
        }
        .applyInsetGroupedListStyle()
        .navigationBarTitle(UserText.settingsKeyboard, displayMode: .inline)
        .accentColor(Color(designSystemColor: .textPrimary))
    }
}
