//
//  UnprotectedSitesViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Core
import PrivacyConfig
import DesignResourcesKit
import DesignResourcesKitIcons

final class UnprotectedSitesViewController: UITableViewController {

    private enum Strings {
        static let info = NSLocalizedString(
            "zvh-2e-Wmz.text",
            tableName: "Settings",
            bundle: .main,
            value: "These sites will not be enhanced by Privacy Protection.",
            comment: "Description shown above the list of unprotected sites")
        static let allProtected = NSLocalizedString(
            "Hu1-5i-vjL.text",
            tableName: "Settings",
            bundle: .main,
            value: "Privacy Protection enabled for all sites",
            comment: "Message shown when there are no unprotected sites")
    }

    private lazy var infoText: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Strings.info
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "backButton"
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft, for: .normal)
        button.addTarget(self, action: #selector(onBackPressed), for: .touchUpInside)
        return button
    }()

    private let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    private lazy var doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(endEditing))
    private lazy var editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(startEditing))
    private lazy var addButton = UIBarButtonItem(
        image: DesignSystemImages.Glyphs.Size24.add,
        style: .plain,
        target: self,
        action: #selector(onAddPressed))

    private var hiddenNavBarItems: [UIBarButtonItem]?

    private let privacyConfig: PrivacyConfiguration = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
    private let rulesManager: ContentBlockerRulesManager = ContentBlocking.shared.contentBlockingManager

    var showBackButton = false

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureNavigationItems()
        decorate()

        navigationController?.setToolbarHidden(false, animated: false)
        refreshToolbarItems(animated: false)

        configureBackButton()

        let fontSize = FontSettings.fontSizeForHeaderView
        let text = NSAttributedString(string: infoText.text ?? "", attributes: [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: fontSize)
        ])
        infoText.attributedText = text
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)

        if parent == nil {
            navigationController?.setToolbarHidden(true, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: true)
    }

    private func refreshToolbarItems(animated: Bool) {
        if tableView.isEditing {
            setToolbarItems([flexibleSpace, doneButton], animated: animated)
        } else {
            setToolbarItems([flexibleSpace, editButton], animated: animated)
        }

        editButton.isEnabled = privacyConfig.userUnprotectedDomains.count > 0
    }

    private func configureBackButton() {
        backButton.isHidden = !showBackButton
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let headerView = tableView.tableHeaderView else {
            return
        }

        let fittingSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = headerView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        if headerView.frame.size.height != size.height {
            headerView.frame.size.height = size.height
            tableView.tableHeaderView = headerView
            tableView.layoutIfNeeded()
        }
    }
    
    // MARK: UITableView data source

    private var unprotectedDomains: [String] {
        privacyConfig.userUnprotectedDomains.sorted()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = unprotectedDomains.count
        return count == 0 ? 1 : count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        createCell(forRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        unprotectedDomains.count > 0
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        let domain = unprotectedDomains[indexPath.row]
        privacyConfig.userEnabledProtection(forDomain: domain)
        rulesManager.scheduleCompilation()

        if unprotectedDomains.count == 0 {
            if tableView.isEditing {
                // According to documentation it is inivalid to call it synchronously here.
                DispatchQueue.main.async {
                    self.endEditing()
                }
            } else {
                refreshToolbarItems(animated: true)
            }

            tableView.reloadData()
        } else {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    // MARK: actions
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    @objc private func onAddPressed() {
        let title = UserText.alertDisableProtection
        let placeholder = UserText.alertDisableProtectionPlaceholder
        let confirm = UserText.actionAdd
        let cancel = UserText.actionCancel

        let addSiteBox = UIAlertController(title: title, message: "", preferredStyle: .alert)
        addSiteBox.addTextField { (textField) in
            textField.placeholder = placeholder
            textField.keyboardAppearance = ThemeManager.shared.currentTheme.keyboardAppearance
        }
        addSiteBox.addAction(UIAlertAction.init(title: confirm, style: .default, handler: { _ in self.addSite(from: addSiteBox) }))
        addSiteBox.addAction(UIAlertAction.init(title: cancel, style: .cancel, handler: nil))
        present(addSiteBox, animated: true, completion: nil)
    }

    @objc private func onBackPressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func startEditing() {
        navigationItem.setHidesBackButton(true, animated: true)
        hiddenNavBarItems = navigationItem.rightBarButtonItems
        navigationItem.setRightBarButtonItems(nil, animated: true)

        // Fix glitch happening when there's cell that is already in the editing state (swiped to reveal delete button) and user presses 'Edit'.
        tableView.setEditing(false, animated: true)
        tableView.setEditing(true, animated: true)

        refreshToolbarItems(animated: true)
    }

    @objc private func endEditing() {
        navigationItem.setHidesBackButton(false, animated: true)
        if let hiddenNavBarItems = hiddenNavBarItems {
            navigationItem.setRightBarButtonItems(hiddenNavBarItems, animated: true)
        }

        tableView.setEditing(false, animated: true)

        refreshToolbarItems(animated: true)
    }

    // MARK: private

    private func configureTableView() {
        tableView.alwaysBounceVertical = true
        tableView.register(UnprotectedSitesItemCell.self, forCellReuseIdentifier: UnprotectedSitesItemCell.reuseIdentifier)
        tableView.register(AllProtectedCell.self, forCellReuseIdentifier: AllProtectedCell.reuseIdentifier)

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 0))
        headerView.addSubview(infoText)
        headerView.addSubview(backButton)
        NSLayoutConstraint.activate([
            infoText.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 32),
            infoText.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -32),
            infoText.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            infoText.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16),
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            backButton.centerYAnchor.constraint(equalTo: infoText.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 30)
        ])
        tableView.tableHeaderView = headerView
    }

    private func configureNavigationItems() {
        navigationItem.title = UserText.settingsUnprotectedSites
        navigationItem.rightBarButtonItem = addButton
    }

    private func addSite(from controller: UIAlertController) {
        guard let field = controller.textFields?[0] else { return }
        guard let domain = domain(from: field) else { return }
        privacyConfig.userDisabledProtection(forDomain: domain)
        rulesManager.scheduleCompilation()
        tableView.reloadData()
        refreshToolbarItems(animated: true)
    }

    private func domain(from field: UITextField) -> String? {
        guard let domain = field.text?.trimmingWhitespace() else { return nil }
        guard domain.isValidHostname || domain.isValidIpHost else { return nil }
        return domain
    }

    private func createCell(forRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if unprotectedDomains.count > 0 {
            cell = createUnprotectedSiteCell(forRowAt: indexPath)
        } else {
            cell = createAllProtectedCell(forRowAt: indexPath)
        }

        let theme = ThemeManager.shared.currentTheme
        cell.backgroundColor = theme.tableCellBackgroundColor

        return cell
    }

    private func createAllProtectedCell(forRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let allProtectedCell = tableView.dequeueReusableCell(
            withIdentifier: AllProtectedCell.reuseIdentifier,
            for: indexPath) as? AllProtectedCell else {
            fatalError("Failed to dequeue AllProtectedCell")
        }

        let theme = ThemeManager.shared.currentTheme
        allProtectedCell.label.text = Strings.allProtected
        allProtectedCell.label.textColor = theme.tableCellTextColor

        return allProtectedCell
    }

    private func createUnprotectedSiteCell(forRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let unprotectedItemCell = tableView.dequeueReusableCell(
            withIdentifier: UnprotectedSitesItemCell.reuseIdentifier,
            for: indexPath) as? UnprotectedSitesItemCell else {
            fatalError("Failed to dequeue UnprotectedSitesItemCell")
        }

        unprotectedItemCell.domain = unprotectedDomains[indexPath.row]

        let theme = ThemeManager.shared.currentTheme
        unprotectedItemCell.domainLabel.textColor = theme.tableCellTextColor

        return unprotectedItemCell
    }
}

private final class UnprotectedSitesItemCell: UITableViewCell {

    static let reuseIdentifier = "UnprotectedSitesItemCell"

    let domainLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxBodyRegular()
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    var domain: String? {
        get {
            domainLabel.text
        }
        set {
            domainLabel.text = newValue
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(domainLabel)
        NSLayoutConstraint.activate([
            domainLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 16),
            domainLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -16),
            domainLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            domainLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AllProtectedCell: UITableViewCell {

    static let reuseIdentifier = "AllProtectedCell"

    let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxBodyRegular()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isUserInteractionEnabled = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension UnprotectedSitesViewController {

    func decorate() {
        let theme = ThemeManager.shared.currentTheme
        tableView.separatorColor = theme.tableCellSeparatorColor
        tableView.backgroundColor = theme.backgroundColor

        infoText.textColor = theme.tableHeaderTextColor

        tableView.reloadData()

        navigationController?.toolbar.barTintColor = navigationController?.navigationBar.barTintColor
        navigationController?.toolbar.backgroundColor = navigationController?.navigationBar.backgroundColor
        navigationController?.toolbar.tintColor = navigationController?.navigationBar.tintColor
    }
}
