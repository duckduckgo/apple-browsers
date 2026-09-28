//
//  ExcludedDomainsViewController.swift
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
import Combine

final class ExcludedDomainsViewController: NSViewController {
    typealias Model = ExcludedDomainsViewModel

    enum Constants {
        static let preferredContentSize = CGSize(width: 475, height: 307)
        static let horizontalInset: CGFloat = 20
        static let searchFieldWidth: CGFloat = 155
        static let scrollViewMinSize = CGSize(width: 435, height: 195)
        static let rowHeight: CGFloat = 24
        static let faviconSize: CGFloat = 16
        static let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "ExcludedDomainCell")
    }

    static func create(model: Model = DefaultExcludedDomainsViewModel()) -> ExcludedDomainsViewController {
        ExcludedDomainsViewController(model: model)
    }

    private(set) var tableView: NSTableView!
    private(set) var addDomainButton: NSButton!
    private(set) var removeDomainButton: NSButton!
    private(set) var doneButton: NSButton!
    private(set) var excludedDomainsLabel: NSTextField!
    private(set) var searchField: NSSearchField!
    private(set) var scrollView: NSScrollView!

    private let faviconManagement: FaviconManagement = NSApp.delegateTyped.faviconManager

    private var allDomains = [String]()
    private var filteredDomains: [String]?

    private var visibleDomains: [String] {
        return filteredDomains ?? allDomains
    }

    private let model: Model

    private var cancellables = Set<AnyCancellable>()

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

        excludedDomainsLabel = NSTextField(labelWithString: UserText.vpnExcludedDomainsTitle)
        excludedDomainsLabel.translatesAutoresizingMaskIntoConstraints = false
        excludedDomainsLabel.font = .systemFont(ofSize: 13, weight: .medium)
        excludedDomainsLabel.lineBreakMode = .byClipping
        excludedDomainsLabel.setContentHuggingPriority(.init(251), for: .horizontal)

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

        addDomainButton = makeToolbarButton(title: UserText.vpnExcludedDomainsAddDomain, action: #selector(addDomain(_:) as (NSButton) -> Void))
        removeDomainButton = makeToolbarButton(title: UserText.remove, action: #selector(removeSelectedDomain(_:)))
        removeDomainButton.isEnabled = false
        doneButton = makeToolbarButton(title: UserText.done, action: #selector(doneButtonClicked(_:)))
        doneButton.keyEquivalent = "\r"

        view.addSubview(excludedDomainsLabel)
        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(addDomainButton)
        view.addSubview(removeDomainButton)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            excludedDomainsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            excludedDomainsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Constants.horizontalInset),

            searchField.widthAnchor.constraint(equalToConstant: Constants.searchFieldWidth),
            searchField.centerYAnchor.constraint(equalTo: excludedDomainsLabel.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: Constants.horizontalInset),

            scrollView.topAnchor.constraint(equalTo: excludedDomainsLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: Constants.horizontalInset),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.scrollViewMinSize.width),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.scrollViewMinSize.height),

            addDomainButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Constants.horizontalInset),
            addDomainButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.bottomAnchor.constraint(equalTo: addDomainButton.bottomAnchor, constant: Constants.horizontalInset),

            removeDomainButton.leadingAnchor.constraint(equalTo: addDomainButton.trailingAnchor, constant: 12),
            removeDomainButton.centerYAnchor.constraint(equalTo: addDomainButton.centerYAnchor),

            doneButton.centerYAnchor.constraint(equalTo: removeDomainButton.centerYAnchor),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: removeDomainButton.trailingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: Constants.horizontalInset),
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        applyModalWindowStyleIfNeeded()
        subscribeToFaviconUpdates()

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
        addDomainButton.title = UserText.vpnExcludedDomainsAddDomain
        removeDomainButton.title = UserText.remove
        doneButton.title = UserText.done
        excludedDomainsLabel.stringValue = UserText.vpnExcludedDomainsTitle
    }

    private func updateRemoveButtonState() {
        removeDomainButton.isEnabled = tableView.selectedRow > -1
    }

    private func subscribeToFaviconUpdates() {
        NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.refreshFavicons(for: notification.faviconsCacheUpdate)
            }
            .store(in: &cancellables)
    }

    private func refreshFavicons(for update: FaviconsCacheUpdate?) {
        // No payload: refresh defensively. Otherwise only reload when an updated
        // host matches a displayed domain or any of its subdomains (mirroring the
        // `forDomainOrAnySubdomain:` lookup used to populate the cells).
        if let update, !update.hosts.contains(where: { host in
            visibleDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }
        }) {
            return
        }
        tableView.reloadData()
    }

    /// Builds a reusable `ExcludedDomainCell` row: favicon plus domain.
    /// Laid out like `FireproofDomainCellView`, but keeps this screen's own favicon lookup:
    /// `FaviconView` resolves by exact URL at `.medium` and drops anything under 16pt, which falls
    /// back to a letter placeholder for hosts this screen used to show an icon for.
    private func makeDomainCellView() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Constants.cellIdentifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignLeft
        imageView.refusesFirstResponder = true
        imageView.image = .web
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Constants.faviconSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.faviconSize),
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -20),
        ])

        return cell
    }

    fileprivate func reloadData() {
        allDomains = model.domains.sorted { (lhs, rhs) -> Bool in
            return lhs < rhs
        }

        tableView.reloadData()
        updateRemoveButtonState()
    }

    @objc func doneButtonClicked(_ sender: NSButton) {
        dismiss()
    }

    @objc func addDomain(_ sender: NSButton) {
        addDomain()
    }

    func addDomain(domain: String = "") {
        AddExcludedDomainView(title: UserText.vpnAddExcludedDomainTitle, domain: domain, buttonsState: .compressed, cancelActionTitle: UserText.vpnAddExcludedDomainCancelButtonTitle, cancelAction: { dismiss in

            dismiss()
        }, defaultActionTitle: UserText.vpnAddExcludedDomainActionButtonTitle) { [weak self] domain, dismiss in
            guard let self else { return }

            addDomain(domain)
            dismiss()
        }.show(in: view.window)
    }

    private func addDomain(_ domain: String) {
        Task {
            model.add(domain: domain)
            reloadData()

            if let newRowIndex = allDomains.firstIndex(of: domain) {
                tableView.scrollRowToVisible(newRowIndex)
            }

            await model.askUserToReportIssues(withDomain: domain, in: view.window)
        }
    }

    @objc func removeSelectedDomain(_ sender: NSButton) {
        guard tableView.selectedRow > -1 else {
            updateRemoveButtonState()
            return
        }

        let selectedDomain = visibleDomains[tableView.selectedRow]
        model.remove(domain: selectedDomain)
        reloadData()
    }
}

extension ExcludedDomainsViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleDomains.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return visibleDomains[row]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Constants.cellIdentifier, owner: nil) as? NSTableCellView
            ?? makeDomainCellView()

        let domain = visibleDomains[row]

        cell.textField?.stringValue = domain
        cell.toolTip = domain
        cell.imageView?.image = faviconManagement.getCachedFavicon(forDomainOrAnySubdomain: domain, sizeCategory: .small)?.image

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtonState()
    }
}

extension ExcludedDomainsViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }

        if field.stringValue.isEmpty {
            filteredDomains = nil
        } else {
            filteredDomains = allDomains.filter { $0.contains(field.stringValue) }
        }

        reloadData()
    }

}
