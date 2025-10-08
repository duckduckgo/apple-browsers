//
//  FireproofDomainsViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import AppKitExtensions
import Carbon
import Common
import SwiftUI
import CoreAudioTypes
final class FireproofDomainsViewController: NSViewController {

    enum Constants {
        static let preferredContentSize = CGSize(width: 475, height: 307)
    }

    // Factory used by callers (e.g., preferences) to present this controller
    static func create(fireproofDomains: FireproofDomains, faviconManager: FaviconManagement) -> FireproofDomainsViewController {
        FireproofDomainsViewController(fireproofDomains: fireproofDomains, faviconManager: faviconManager)
    }

    // MARK: - Dependencies
    private let fireproofDomains: FireproofDomains
    private let faviconManager: FaviconManagement

    // MARK: - UI
    private let buttonsStackView = NSStackView()
    private lazy var removeDomainButton = NSButton(title: UserText.remove, target: self, action: #selector(removeSelectedDomain(_:)))
    private lazy var removeAllDomainsButton = NSButton(title: UserText.fireproofRemoveAllButton, target: self, action: #selector(removeAllDomains(_:)))
    private lazy var doneButton = NSButton(title: UserText.done, target: self, action: #selector(doneButtonClicked(_:)))
    private lazy var fireproofSitesLabel = NSTextField(labelWithString: UserText.fireproofSites)
    private let searchBar = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    // MARK: - State
    private var allFireproofDomains = [String]()
    private var filteredFireproofDomains: [String]?
    private var visibleFireproofDomains: [String] { filteredFireproofDomains ?? allFireproofDomains }

    // MARK: - Init
    init(fireproofDomains: FireproofDomains, faviconManager: FaviconManagement) {
        self.fireproofDomains = fireproofDomains
        self.faviconManager = faviconManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    // MARK: - View lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Constants.preferredContentSize))
        view.translatesAutoresizingMaskIntoConstraints = false

        // Label
        fireproofSitesLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fireproofSitesLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fireproofSitesLabel)

        // Search
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholderString = UserText.searchBarSearch
        view.addSubview(searchBar)
        searchBar.setAccessibilityIdentifier("FireproofDomainsViewController.searchBar")

        // Table inside scroll view
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = tableView
        clipView.autoresizingMask = [.width, .height]
        clipView.backgroundColor = .clear
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        view.addSubview(scrollView)
        tableView.setAccessibilityIdentifier("FireproofDomainsViewController.tableView")

        // Table configuration
        let column = NSTableColumn()
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 17, height: 0)
        tableView.backgroundColor = .controlBackgroundColor
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.selectionHighlightStyle = .regular
        tableView.allowsColumnSelection = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.usesAutomaticRowHeights = true
        tableView.delegate = self
        tableView.dataSource = self

        // Buttons
        removeDomainButton.setAccessibilityIdentifier("FireproofDomainsViewController.removeButton")
        removeAllDomainsButton.setAccessibilityIdentifier("FireproofDomainsViewController.removeAllButton")
        doneButton.setAccessibilityIdentifier("FireproofDomainsViewController.doneButton")

        configureToolbarButton(removeDomainButton)
        configureToolbarButton(removeAllDomainsButton)
        configureToolbarButton(doneButton)

        buttonsStackView.orientation = .horizontal
        buttonsStackView.spacing = 12
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.addArrangedSubview(removeDomainButton)
        buttonsStackView.addArrangedSubview(removeAllDomainsButton)
        view.addSubview(buttonsStackView)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        // Layout
        fireproofSitesLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        fireproofSitesLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        NSLayoutConstraint.activate([
            fireproofSitesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            fireproofSitesLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),

            searchBar.centerYAnchor.constraint(equalTo: fireproofSitesLabel.centerYAnchor),
            searchBar.leadingAnchor.constraint(greaterThanOrEqualTo: fireproofSitesLabel.trailingAnchor, constant: 8),
            view.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: 16),
            searchBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            searchBar.widthAnchor.constraint(equalToConstant: 256).priority(.defaultLow),

            scrollView.topAnchor.constraint(equalTo: fireproofSitesLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 16),
            buttonsStackView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 20),
            buttonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 20),

            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: buttonsStackView.trailingAnchor, constant: 16),
            doneButton.centerYAnchor.constraint(equalTo: buttonsStackView.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: 20)
        ])
    }

    override func viewDidLoad() {
        applyModalWindowStyleIfNeeded()
        preferredContentSize = Constants.preferredContentSize

        // Key equivalents: ⌘F focuses search
        addKeyEquivalent("f", modifierFlags: .command) { [weak self] _ in
            self?.handleCmdF() ?? false
        }
        // ⌘⌫ deletes selected items
        addKeyEquivalent(.backspace, modifierFlags: .command) { [weak self] _ in
            self?.deleteSelectedItems() ?? false
        }
        // ⌘A selects all rows
        addKeyEquivalent("a", modifierFlags: .command) { [weak self] _ in
            self?.selectAllRows() ?? false
        }
        doneButton.keyEquivalent = "\r"
    }

    override func viewWillAppear() {
        reloadData()
    }

    // MARK: - UI setup
    private func configureToolbarButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }

    private func updateRemoveButtonState() {
        removeDomainButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }

    private func reloadData() {
        allFireproofDomains = fireproofDomains.fireproofDomains.sorted(by: <)
        updateFilteredFireproofDomains()

        let scrollPosition = tableView.visibleRect.origin
        tableView.reloadData()
        tableView.scroll(scrollPosition)
        updateRemoveButtonState()

        let hasAnyDomains = !allFireproofDomains.isEmpty
        removeAllDomainsButton.isEnabled = hasAnyDomains
        searchBar.isEnabled = hasAnyDomains
    }

    private func updateFilteredFireproofDomains() {
        let searchBarString = searchBar.stringValue
        guard !searchBarString.isEmpty else {
            filteredFireproofDomains = nil
            return
        }

        filteredFireproofDomains = allFireproofDomains.filter { $0.localizedCaseInsensitiveContains(searchBarString) }
    }

    // MARK: - Actions
    @objc private func doneButtonClicked(_ sender: NSButton) {
        dismiss()
    }

    @objc private func removeSelectedDomain(_ sender: NSButton) {
        deleteSelectedItems()
    }

    @objc private func removeAllDomains(_ sender: NSButton) {
        let domainsBeforeClear = allFireproofDomains

        undoManager?.beginUndoGrouping()
        undoManager?.registerUndo(withTarget: self) { vc in
            domainsBeforeClear.forEach { vc.fireproofDomains.add(domain: $0) }
            vc.reloadData()
        }
        undoManager?.setActionName(UserText.fireproofRemoveAllButton)
        undoManager?.endUndoGrouping()

        fireproofDomains.clearAll()
        searchBar.stringValue = ""
        filteredFireproofDomains = nil
        reloadData()
    }

    private func handleCmdF() -> Bool {
        guard !visibleFireproofDomains.isEmpty else { return false }
        searchBar.makeMeFirstResponder()
        return true
    }

    @discardableResult
    private func deleteSelectedItems() -> Bool {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return false }

        let domains = indexes.map { visibleFireproofDomains[$0] }

        undoManager?.beginUndoGrouping()
        for domain in domains {
            undoManager?.registerUndo(withTarget: self) { vc in
                vc.fireproofDomains.add(domain: domain)
                vc.reloadData()
            }
        }
        undoManager?.setActionName(UserText.remove)
        undoManager?.endUndoGrouping()

        domains.forEach { fireproofDomains.remove(domain: $0) }

        reloadData()
        return true
    }

    @discardableResult
    private func selectAllRows() -> Bool {
        guard tableView.numberOfRows > 0 else { return false }
        let all = IndexSet(integersIn: 0..<tableView.numberOfRows)
        tableView.selectRowIndexes(all, byExtendingSelection: false)
        updateRemoveButtonState()
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            if deleteSelectedItems() { return }
            // fallthrough (Beep)
        default: break
        }
        super.keyDown(with: event)
    }

    // handle Esc key
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}
// MARK: - NSTableViewDataSource
extension FireproofDomainsViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleFireproofDomains.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return visibleFireproofDomains[row]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: FireproofDomainCellView.identifier, owner: nil) as? FireproofDomainCellView ?? FireproofDomainCellView()

        let domain = visibleFireproofDomains[row]
        cell.update(host: domain)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtonState()
    }

}
// MARK: - NSSearchFieldDelegate
extension FireproofDomainsViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        updateFilteredFireproofDomains()
        tableView.reloadData()
        updateRemoveButtonState()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchBar else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if tableView.numberOfRows > 0 {
                tableView.makeMeFirstResponder()
                if tableView.selectedRow == -1 {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)),
             #selector(NSResponder.insertNewline(_:)):
            // If search field is active, first press just deactivates it
            tableView.makeMeFirstResponder()
            return true
        default:
            return false
        }
    }

}

// MARK: - #Preview
#if DEBUG
private class MockFireproofDomains: FireproofDomains {
    init(domains: [String]) {
        super.init(store: FireproofDomainsStore(context: nil), tld: TLD())
        for domain in domains {
            super.add(domain: domain)
        }
    }
}
@available(macOS 14.0, *)
#Preview(traits: FireproofDomainsViewController.Constants.preferredContentSize.fixedLayout) {
    customAssertionFailure = { _, _, _ in }
    let mockDomains = MockFireproofDomains(domains: [
        "duckduckgo.com",
        "github.com",
        "figma.com",
        "y-the-very-long-domain-name-for-preview-testing-is-in-the-end.com"
    ])

    // Provide simple preview icons from bundled assets (replace names if needed)
    let faviconMock = FaviconManagerMock()
    faviconMock.setImage(NSImage(named: NSImage.applicationIconName)!, forHost: "duckduckgo.com")
    faviconMock.setImage(NSImage(named: NSImage.networkName)!, forHost: "github.com")

    let controller = FireproofDomainsViewController(
        fireproofDomains: mockDomains,
        faviconManager: faviconMock
    )._preview_hidingWindowControlsOnAppear()
    return controller
}
#endif
