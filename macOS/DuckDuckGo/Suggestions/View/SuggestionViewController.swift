//
//  SuggestionViewController.swift
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

import Cocoa
import Combine
import History
import Suggestions

protocol SuggestionViewControllerDelegate: AnyObject {

    func suggestionViewControllerDidConfirmSelection(_ suggestionViewController: SuggestionViewController)

}

final class SuggestionViewController: NSViewController {

    weak var delegate: SuggestionViewControllerDelegate?

    @IBOutlet weak var backgroundView: ColorView!
    @IBOutlet weak var innerBorderView: ColorView!
    @IBOutlet weak var innerBorderViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var innerBorderViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var innerBorderViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var innerBorderViewTrailingConstraint: NSLayoutConstraint!

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pixelPerfectConstraint: NSLayoutConstraint!
    @IBOutlet weak var backgroundViewTopConstraint: NSLayoutConstraint!

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let suggestionContainerViewModel: SuggestionContainerViewModel
    private let isBurner: Bool

    required init?(coder: NSCoder) {
        fatalError("SuggestionViewController: Bad initializer")
    }

    required init?(coder: NSCoder,
                   suggestionContainerViewModel: SuggestionContainerViewModel,
                   isBurner: Bool,
                   themeManager: ThemeManaging) {
        self.suggestionContainerViewModel = suggestionContainerViewModel
        self.isBurner = isBurner
        self.themeManager = themeManager

        super.init(coder: coder)
    }

    private var suggestionResultCancellable: AnyCancellable?
    private var selectionIndexCancellable: AnyCancellable?

    private var eventMonitorCancellables = Set<AnyCancellable>()
    private var appObserver: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self

        setupTableView()
        addTrackingArea()
        subscribeToSuggestionResult()
        subscribeToSelectionIndex()
        subscribeToThemeChanges()

        applyThemeStyle()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        self.view.window!.isOpaque = false
        self.view.window!.backgroundColor = .clear

        addEventMonitors()

        let barStyleProvider = themeManager.theme.addressBarStyleProvider
        tableView.rowHeight = barStyleProvider.sizeForSuggestionRow(isHomePage: suggestionContainerViewModel.isHomePage)
    }

    override func viewDidDisappear() {
        eventMonitorCancellables.removeAll()
        clearSelection()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        // Make sure the table view width equals the encapsulating scroll view
        tableView.sizeToFit()
        let column = tableView.tableColumns.first
        column?.width = tableView.frame.width
    }

    private func setupTableView() {
        tableView.style = .plain
        tableView.setAccessibilityIdentifier("SuggestionViewController.tableView")
    }

    private func addTrackingArea() {
        let trackingOptions: NSTrackingArea.Options = [ .activeInActiveApp,
                                                        .mouseEnteredAndExited,
                                                        .enabledDuringMouseDrag,
                                                        .mouseMoved,
                                                        .inVisibleRect ]
        let trackingArea = NSTrackingArea(rect: tableView.frame, options: trackingOptions, owner: self, userInfo: nil)
        tableView.addTrackingArea(trackingArea)
    }

    @IBAction func confirmButtonAction(_ sender: NSButton) {
        delegate?.suggestionViewControllerDidConfirmSelection(self)
        closeWindow()
    }

    @IBAction func removeButtonAction(_ sender: NSButton) {
        guard let cell = sender.superview as? SuggestionTableCellView,
        let suggestion = cell.suggestion else {
            assertionFailure("Correct cell or url are not available")
            return
        }

        removeHistory(for: suggestion)
    }

    private func addEventMonitors() {
        eventMonitorCancellables.removeAll()

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in
            self?.closeWindow()
        }.store(in: &eventMonitorCancellables)
    }

    private func subscribeToSuggestionResult() {
        suggestionResultCancellable = suggestionContainerViewModel.suggestionContainer.$result
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
            self?.displayNewSuggestions()
        }
    }

    private func subscribeToSelectionIndex() {
        selectionIndexCancellable = suggestionContainerViewModel.$selectionIndex.receive(on: DispatchQueue.main).sink { [weak self] _ in
            if let weakSelf = self {
                weakSelf.selectRow(at: weakSelf.suggestionContainerViewModel.selectionIndex)
            }
        }
    }

    private func displayNewSuggestions() {
        defer {
            selectedRowCache = nil
        }

        guard suggestionContainerViewModel.numberOfRows > 0 else {
            closeWindow()
            tableView.reloadData()
            return
        }

        // Remove the second reload that causes visual glitch in the beginning of typing
        if suggestionContainerViewModel.suggestionContainer.result != nil || suggestionContainerViewModel.shouldShowSearchCell {
            updateHeight()
            tableView.reloadData()

            // Select at the same position where the suggestion was removed
            if let selectedRowCache = selectedRowCache {
                suggestionContainerViewModel.select(at: selectedRowCache)
            }

            self.selectRow(at: self.suggestionContainerViewModel.selectionIndex)
        }
    }

    private func selectRow(at index: Int?) {
        // Convert viewModel selection index to tableView row
        let tableRow = suggestionContainerViewModel.tableRow(forSelectionIndex: index)

        if tableView.selectedRow == tableRow {
            if let tableRow, let cell = tableView.view(atColumn: 0, row: tableRow, makeIfNecessary: false) as? SuggestionTableCellView {
                // Show the delete button if necessary
                cell.updateDeleteImageViewVisibility()
            }
            return
        }

        guard let tableRow,
              tableRow >= 0,
              suggestionContainerViewModel.numberOfSuggestions != 0,
              tableRow < suggestionContainerViewModel.numberOfRows else {
            if let defaultRow = suggestionContainerViewModel.defaultSelectedRow {
                tableView.selectRowIndexes(IndexSet(integer: defaultRow), byExtendingSelection: false)
            } else {
                self.clearSelection()
            }
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: tableRow), byExtendingSelection: false)
    }

    private func selectRow(at point: NSPoint) {
        let flippedPoint = view.convert(point, to: tableView)
        let tableRow = tableView.row(at: flippedPoint)

        guard tableRow >= 0 else {
            selectRow(at: nil)
            return
        }

        // Check if this is a prefix row (like search cell) - select it directly without updating viewModel
        if suggestionContainerViewModel.isPrefixRow(tableRow) {
            tableView.selectRowIndexes(IndexSet(integer: tableRow), byExtendingSelection: false)
            return
        }

        // Convert tableView row to viewModel selection index
        let viewModelIndex = suggestionContainerViewModel.selectionIndex(forRow: tableRow)
        selectRow(at: viewModelIndex)
    }

    private func clearSelection() {
        tableView.deselectAll(self)
    }

    override func mouseMoved(with event: NSEvent) {
        selectRow(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        clearSelection()
    }

    private func updateHeight() {
        let totalRows = suggestionContainerViewModel.numberOfRows
        guard totalRows > 0 else {
            tableViewHeightConstraint.constant = 0
            return
        }

        let rowHeight = tableView.rowHeight
        let barStyleProvider = themeManager.theme.addressBarStyleProvider

        if barStyleProvider.shouldLeaveBottomPaddingInSuggestions {
            tableViewHeightConstraint.constant = CGFloat(totalRows) * rowHeight
                + (tableView.enclosingScrollView?.contentInsets.top ?? 0)
                + (tableView.enclosingScrollView?.contentInsets.bottom ?? 0)
        } else {
            tableViewHeightConstraint.constant = CGFloat(totalRows) * rowHeight
                + (tableView.enclosingScrollView?.contentInsets.top ?? 0)
        }
    }

    private func closeWindow() {
        guard let window = view.window else {
            return
        }

        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    var selectedRowCache: Int?

    private func removeHistory(for suggestion: Suggestion) {
        assert(suggestion.isHistoryEntry)

        guard let url = suggestion.url else {
            assertionFailure("URL not available")
            return
        }

        // Cache the viewModel selection index (not the tableView row)
        selectedRowCache = suggestionContainerViewModel.selectionIndex(forRow: tableView.selectedRow)

        NSApp.delegateTyped.historyCoordinator.removeUrlEntry(url) { [weak self] error in
            guard let self = self, error == nil else {
                return
            }

            if let userStringValue = suggestionContainerViewModel.userStringValue {
                suggestionContainerViewModel.isTopSuggestionSelectionExpected = false
                self.suggestionContainerViewModel.suggestionContainer.getSuggestions(for: userStringValue, useCachedData: true)
            } else {
                self.suggestionContainerViewModel.removeSuggestionFromResult(suggestion: suggestion)
            }
        }
    }

}

extension SuggestionViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        let barStyleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider

        backgroundViewTopConstraint.constant = barStyleProvider.topSpaceForSuggestionWindow
        backgroundView.setCornerRadius(barStyleProvider.addressBarActiveBackgroundViewRadius)
        innerBorderView.setCornerRadius(barStyleProvider.addressBarActiveBackgroundViewRadius)
        backgroundView.backgroundColor = colorsProvider.suggestionsBackgroundColor

        tableView.reloadData()
    }
}

extension SuggestionViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return suggestionContainerViewModel.numberOfRows
    }

}

extension SuggestionViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: SuggestionTableCellView.identifier, owner: self) as? SuggestionTableCellView ?? SuggestionTableCellView()
        cell.theme = themeManager.theme

        guard let rowContent = suggestionContainerViewModel.rowContent(at: row) else {
            assertionFailure("SuggestionViewController: Invalid row index")
            return nil
        }

        switch rowContent {
        case .searchCell:
            let userText = suggestionContainerViewModel.userStringValue ?? ""
            let searchIcon = themeManager.theme.iconsProvider.suggestionsIconsProvider.phraseEntryIcon
            cell.display(userText: userText, style: .search, icon: searchIcon, isBurner: self.isBurner)

        case .suggestion(let suggestionIndex):
            guard let suggestionViewModel = suggestionContainerViewModel.suggestionViewModel(at: suggestionIndex) else {
                assertionFailure("SuggestionViewController: Failed to get suggestion")
                return nil
            }
            cell.display(suggestionViewModel, isBurner: self.isBurner)
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let suggestionTableRowView = tableView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier(rawValue: SuggestionTableRowView.identifier), owner: self)
                as? SuggestionTableRowView else {
            assertionFailure("SuggestionViewController: Making of table row view failed")
            return nil
        }

        suggestionTableRowView.theme = themeManager.theme

        return suggestionTableRowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.selectedRow == -1 {
            suggestionContainerViewModel.clearSelection()
            return
        }

        // If a prefix row is selected (like search cell), don't update viewModel selection
        if suggestionContainerViewModel.isPrefixRow(tableView.selectedRow) {
            return
        }

        // Convert tableView row to viewModel selection index
        guard let suggestionIndex = suggestionContainerViewModel.selectionIndex(forRow: tableView.selectedRow) else {
            return
        }

        if suggestionContainerViewModel.selectionIndex != suggestionIndex {
            suggestionContainerViewModel.select(at: suggestionIndex)
        }
    }

}
