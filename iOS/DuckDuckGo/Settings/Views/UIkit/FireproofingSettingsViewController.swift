//
//  FireproofingSettingsViewController.swift
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
import Core
import WebKit

class FireproofingSettingsViewController: UITableViewController {
    
    enum Section: Int, CaseIterable {
        case info
        case toggle
        case domainList
        case removeAll
    }

    private lazy var doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))
    private lazy var editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(startEditing))

    var model = [String]()
    private var shouldShowRemoveAll = false

    private let fireproofing: Fireproofing
    private let favicons: FaviconManaging
    private let websiteDataManager: WebsiteDataManaging

    init(fireproofing: Fireproofing,
         favicons: FaviconManaging,
         websiteDataManager: WebsiteDataManaging) {
        self.fireproofing = fireproofing
        self.favicons = favicons
        self.websiteDataManager = websiteDataManager
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = UserText.fireproofingListTitle
        tableView.register(FireproofingSwitchCell.self, forCellReuseIdentifier: "SettingCell")
        tableView.register(FireproofingDomainCell.self, forCellReuseIdentifier: "DomainCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NoDomainsCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ClearAllCell")
        tableView.allowsSelectionDuringEditing = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.sectionHeaderHeight = 18
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 18
        refreshModel()
        navigationItem.rightBarButtonItems = model.isEmpty ? [] : [ editButton ]
        decorate()
        tableView.contentInset = UIEdgeInsets(top: -20, left: 0, bottom: 0, right: 0)
    }
    
    @objc func startEditing() {
        navigationItem.setHidesBackButton(true, animated: true)
        navigationItem.setRightBarButton(doneButton, animated: true)

        // Fix glitch happening when there's cell that is already in the editing state (swiped to reveal delete button) and user presses 'Edit'.
        tableView.setEditing(false, animated: true)
        tableView.setEditing(true, animated: true)
        
        shouldShowRemoveAll = true
        tableView.insertSections([Section.removeAll.rawValue], with: .fade)
    }
    
    @objc func endEditing() {
        navigationItem.setHidesBackButton(false, animated: true)
        navigationItem.setRightBarButton(model.isEmpty ? nil : editButton, animated: true)
        
        tableView.setEditing(false, animated: true)
        
        if shouldShowRemoveAll {
            shouldShowRemoveAll = false
            tableView.deleteSections([Section.removeAll.rawValue], with: .fade)
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return shouldShowRemoveAll ? Section.allCases.count : Section.allCases.count - 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .domainList:
            return max(1, model.count)
            
        case .toggle:
            return 1
                    
        case .removeAll:
            return 1
            
        default:
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let theme = ThemeManager.shared.currentTheme
        let cell: UITableViewCell
        switch Section(rawValue: indexPath.section) {

        case .toggle:
            cell = createSwitchCell(forTableView: tableView, withTheme: theme)

        case .domainList:
            if model.isEmpty {
                cell = createNoDomainCell(forTableView: tableView, withTheme: theme)
            } else {
                cell = createDomainCell(forTableView: tableView, withTheme: theme, forIndex: indexPath.row)
            }
            
        default:
            cell = createClearAllCell(forTableView: tableView, withTheme: theme)

        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .some(.domainList):
            return UserText.fireproofingListTitle
        
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .some(.info):
            return UserText.fireproofingListFooter
        
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.isInSection(section: Section.domainList) && !model.isEmpty
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard !model.isEmpty, indexPath.isInSection(section: .domainList) else { return .none }
        return .delete
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        
        let domain = model.remove(at: indexPath.row)
        fireproofing.remove(domain: domain)
        favicons.removeFireproofFavicon(forDomain: domain)

        if self.model.isEmpty {
            self.endEditing()
            tableView.reloadData()
        } else {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }

        Task { @MainActor in
            await websiteDataManager.removeCookies(forDomains: [domain], fromDataStore: DDGWebsiteDataStoreProvider.current(fireMode: false))
        }
    }
    
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 0 && !model.isEmpty
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == Section.removeAll.rawValue {
            clearAll()
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    func createSwitchCell(forTableView tableView: UITableView, withTheme theme: Theme) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell") as? FireproofingSwitchCell else {
            fatalError("Cell should be dequeued")
        }
        cell.label.textColor = theme.tableCellTextColor
        cell.toggle.onTintColor = theme.buttonTintColor
        cell.toggle.isOn = fireproofing.loginDetectionEnabled
        cell.fireproofing = fireproofing
        cell.decorate(with: theme)
        return cell
    }
    
    func createDomainCell(forTableView tableView: UITableView, withTheme theme: Theme, forIndex index: Int) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "DomainCell") as? FireproofingDomainCell else {
            fatalError("Cell should be dequeued")
        }
        cell.label.textColor = theme.tableCellTextColor
        cell.faviconImage.loadFavicon(forDomain: model[index], usingCache: .fireproof)
        cell.label.text = model[index].droppingWwwPrefix()
        cell.decorate(with: theme)
        return cell
    }
    
    func createNoDomainCell(forTableView tableView: UITableView, withTheme theme: Theme) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NoDomainsCell")!
        cell.textLabel?.text = UserText.fireproofingEmptyState
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textAlignment = .center
        cell.selectionStyle = .none
        cell.decorate(with: theme)
        return cell
    }

    func createClearAllCell(forTableView tableView: UITableView, withTheme theme: Theme) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ClearAllCell")!
        cell.textLabel?.text = UserText.fireproofingRemoveAllSites
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textAlignment = .center
        cell.accessibilityTraits.insert(.button)
        cell.decorate(with: theme)
        cell.textLabel?.textColor = theme.destructiveColor
        return cell
    }

    func clearAll() {
        guard !model.isEmpty else { return }
        
        FireproofingAlert.showClearAllAlert(usingController: self, cancelled: { [weak self] in
            self?.refreshModel()
        }, confirmed: { [weak self] in
            Task { @MainActor in
                await self?.websiteDataManager.removeCookies(forDomains: self?.model ?? [], fromDataStore: DDGWebsiteDataStoreProvider.current(fireMode: false))
                self?.fireproofing.clearAll()
                self?.refreshModel()
                self?.endEditing()
            }
        })
    }
    
    func refreshModel() {
        model = fireproofing.allowedDomains.sorted(by: { (lhs, rhs) -> Bool in
            return lhs.droppingWwwPrefix() < rhs.droppingWwwPrefix()
        })
        tableView.reloadData()
    }
}

extension FireproofingSettingsViewController {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        decorateNavigationBar(with: theme)

        tableView.separatorColor = theme.tableCellSeparatorColor
        tableView.backgroundColor = theme.backgroundColor

        tableView.reloadData()
    }

}

class FireproofingSwitchCell: UITableViewCell {

    let toggle = UISwitch()
    let label = UILabel()

    var fireproofing: Fireproofing?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        label.text = UserText.fireproofingAskOnSignIn
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(onToggle), for: .valueChanged)
        contentView.addSubview(label)
        contentView.addSubview(toggle)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            toggle.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 20),
            toggle.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func onToggle() {
        fireproofing?.loginDetectionEnabled = toggle.isOn
    }

}

class FireproofingDomainCell: UITableViewCell {

    let faviconImage = UIImageView(image: UIImage(named: "GlobeSmall"))
    let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        label.font = .systemFont(ofSize: 16)
        let stack = UIStackView(arrangedSubviews: [faviconImage, label])
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            faviconImage.widthAnchor.constraint(equalToConstant: 16),
            faviconImage.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

private extension IndexPath {
    
    func isInSection(section: FireproofingSettingsViewController.Section) -> Bool {
        return self.section == section.rawValue
    }
    
}
