//
//  ExcludedAppsViewController.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import AppInfoRetriever

final class ExcludedAppsViewController: NSViewController {
    typealias Model = ExcludedAppsModel

    enum Constants {
        static let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "ExcludedAppCell")
        static let preferredContentSize = CGSize(width: 475, height: 355)
        static let horizontalInset: CGFloat = 20
        static let searchFieldWidth: CGFloat = 155
        static let descriptionWidth: CGFloat = 435
        static let scrollViewMinSize = CGSize(width: 435, height: 195)
        static let rowHeight: CGFloat = 24
        static let appIconSize: CGFloat = 16
    }

    static func create(model: Model = DefaultExcludedAppsModel()) -> ExcludedAppsViewController {
        ExcludedAppsViewController(model: model)
    }

    private(set) var tableView: NSTableView!
    private(set) var addAppButton: NSButton!
    private(set) var removeAppButton: NSButton!
    private(set) var doneButton: NSButton!
    private(set) var titleLabel: NSTextField!
    private(set) var descriptionLabel: NSTextField!
    private(set) var searchField: NSSearchField!
    private(set) var scrollView: NSScrollView!

    private let faviconManagement: FaviconManagement = NSApp.delegateTyped.faviconManager

    private var allApps = [AppInfo]()
    private var filteredApps: [AppInfo]?

    private var visibleApps: [AppInfo] {
        return filteredApps ?? allApps
    }

    private let model: Model

    init(model: Model) {
        self.model = model

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    private func makeToolbarButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.init(750), for: .vertical)
        return button
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Constants.preferredContentSize))

        titleLabel = NSTextField(labelWithString: UserText.vpnExcludedAppsTitle)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setContentHuggingPriority(.init(251), for: .horizontal)

        descriptionLabel = NSTextField(wrappingLabelWithString: UserText.vpnExcludedAppsDescription)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        descriptionLabel.isSelectable = false
        descriptionLabel.setContentHuggingPriority(.init(251), for: .horizontal)

        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        (searchField.cell as? NSSearchFieldCell)?.usesSingleLineMode = true
        (searchField.cell as? NSSearchFieldCell)?.isScrollable = true

        tableView = NSTableView()
        let column = NSTableColumn()
        column.resizingMask = [.autoresizingMask, .userResizingMask]
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 17, height: 0)
        tableView.backgroundColor = .controlBackgroundColor
        tableView.gridColor = .gridColor
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = Constants.rowHeight
        tableView.usesAutomaticRowHeights = true
        tableView.allowsColumnSelection = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsExpansionToolTips = true
        tableView.delegate = self
        tableView.dataSource = self

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.usesPredominantAxisScrolling = false
        scrollView.horizontalLineScroll = Constants.rowHeight
        scrollView.verticalLineScroll = Constants.rowHeight

        let clipView = NSClipView()
        clipView.documentView = tableView
        clipView.autoresizingMask = [.width, .height]
        scrollView.contentView = clipView

        addAppButton = makeToolbarButton(title: UserText.vpnExcludedAppsAddApp, action: #selector(addApp(_:)))
        removeAppButton = makeToolbarButton(title: UserText.remove, action: #selector(removeSelected(_:)))
        removeAppButton.isEnabled = false
        doneButton = makeToolbarButton(title: UserText.done, action: #selector(doneButtonClicked(_:)))
        doneButton.keyEquivalent = "\r"

        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(addAppButton)
        view.addSubview(removeAppButton)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Constants.horizontalInset),

            searchField.widthAnchor.constraint(equalToConstant: Constants.searchFieldWidth),
            searchField.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: Constants.horizontalInset),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.widthAnchor.constraint(equalToConstant: Constants.descriptionWidth),

            scrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: Constants.horizontalInset),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.scrollViewMinSize.width),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.scrollViewMinSize.height),

            addAppButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Constants.horizontalInset),
            addAppButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.bottomAnchor.constraint(equalTo: addAppButton.bottomAnchor, constant: Constants.horizontalInset),

            removeAppButton.leadingAnchor.constraint(equalTo: addAppButton.trailingAnchor, constant: 12),
            removeAppButton.centerYAnchor.constraint(equalTo: addAppButton.centerYAnchor),

            doneButton.centerYAnchor.constraint(equalTo: removeAppButton.centerYAnchor),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: removeAppButton.trailingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: Constants.horizontalInset),
        ])

        self.view = view
    }

    /// Builds a reusable `ExcludedAppCell` row: app icon plus name.
    private func makeAppCellView() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Constants.cellIdentifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignLeft
        imageView.refusesFirstResponder = true

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentHuggingPriority(.init(251), for: .horizontal)
        textField.setContentCompressionResistancePriority(.init(250), for: .horizontal)

        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Constants.appIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.appIconSize),
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -20),
        ])

        return cell
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        applyModalWindowStyleIfNeeded()

        // Esc closes the sheet. Handled as a key equivalent rather than a button
        // `keyEquivalent` so it also works while the search field has focus.
        addKeyEquivalent(.escape, modifierFlags: []) { [weak self] _ in
            guard let self else { return false }
            dismiss()
            return true
        }
        reloadData()
        setUpStrings()
    }

    private func setUpStrings() {
        addAppButton.title = UserText.vpnExcludedAppsAddApp
        removeAppButton.title = UserText.remove
        doneButton.title = UserText.done
        titleLabel.stringValue = UserText.vpnExcludedAppsTitle
        descriptionLabel.stringValue = UserText.vpnExcludedAppsDescription
    }

    private func updateRemoveButtonState() {
        removeAppButton.isEnabled = tableView.selectedRow > -1
    }

    fileprivate func reloadData() {
        allApps = model.excludedApps.sorted { (lhs, rhs) -> Bool in
            return lhs < rhs
        }.map { bundleID in
            model.getAppInfo(bundleID: bundleID)
        }

        tableView.reloadData()
        updateRemoveButtonState()
    }

    @objc func doneButtonClicked(_ sender: NSButton) {
        dismiss()
    }

    @objc func addApp(_ sender: NSButton) {
        addApp()
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK,
              let appURL = panel.url else {
            return
        }

        add(appURL: appURL)
    }

    private func add(appURL: URL) {
        Task {
            guard let appInfo = model.add(appURL: appURL) else {
                return
            }
            reloadData()

            if let newRowIndex = allApps.firstIndex(of: appInfo) {
                tableView.scrollRowToVisible(newRowIndex)
            }
        }
    }

    @objc func removeSelected(_ sender: NSButton) {
        guard tableView.selectedRow > -1 else {
            updateRemoveButtonState()
            return
        }

        let appInfo = visibleApps[tableView.selectedRow]
        model.remove(bundleID: appInfo.bundleID)
        reloadData()
    }
}

extension ExcludedAppsViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleApps.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return visibleApps[row]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Constants.cellIdentifier, owner: nil) as? NSTableCellView
            ?? makeAppCellView()

        let appInfo = visibleApps[row]

        cell.textField?.stringValue = appInfo.name
        cell.imageView?.image = appInfo.icon

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtonState()
    }
}

extension ExcludedAppsViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }

        if field.stringValue.isEmpty {
            filteredApps = nil
        } else {
            filteredApps = allApps.filter {
                $0.name.contains(field.stringValue) || $0.bundleID.contains(field.stringValue)
            }
        }

        reloadData()
    }
}
