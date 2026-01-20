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
import AIChat

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
    @IBOutlet weak var topSeparatorView: NSView!

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
                   themeManager: ThemeManaging,
                   aiChatPreferencesStorage: AIChatPreferencesStorage) {
        self.suggestionContainerViewModel = suggestionContainerViewModel
        self.isBurner = isBurner
        self.themeManager = themeManager
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        super.init(coder: coder)
    }

    private var suggestionResultCancellable: AnyCancellable?
    private var selectionSyncCancellable: AnyCancellable?

    private var eventMonitorCancellables = Set<AnyCancellable>()
    private var appObserver: Any?

    /// Flag to prevent re-entrancy when programmatically updating table selection
    private var isUpdatingTableSelection = false
    private var isAIChatToggleBeingDisplayed: Bool = false
    private let aiChatPreferencesStorage: AIChatPreferencesStorage

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        setupTableView()
        addTrackingArea()
        subscribeToSuggestionResult()
        subscribeToSelectionSync()
        subscribeToThemeChanges()
        applyThemeStyle()

        if Application.appDelegate.featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            topSeparatorView?.isHidden = true
        }
    }

    private func updateAIChatToggleFlag() {
        let isToggleFeatureEnabled = Application.appDelegate.featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && aiChatPreferencesStorage.isAIFeaturesEnabled
        isAIChatToggleBeingDisplayed = isToggleFeatureEnabled && aiChatPreferencesStorage.showSearchAndDuckAIToggle
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateAIChatToggleFlag()

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

    /// Subscribes to view model selection changes (e.g., from keyboard navigation)
    private func subscribeToSelectionSync() {
        selectionSyncCancellable = suggestionContainerViewModel.$selectedRowIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isUpdatingTableSelection else { return }
                self.syncTableSelectionWithViewModel()
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
                suggestionContainerViewModel.selectRow(at: selectedRowCache)
            }

            syncTableSelectionWithViewModel()
        }
    }

    func syncTableSelectionWithViewModel() {
        selectTableRow(at: suggestionContainerViewModel.selectedRowIndex)
    }

    private func selectTableRow(at rowIndex: Int?) {
        if tableView.selectedRow == rowIndex {
            if let rowIndex, let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? SuggestionTableCellView {
                cell.updateDeleteImageViewVisibility()
            }
            return
        }

        isUpdatingTableSelection = true
        defer { isUpdatingTableSelection = false }

        guard let rowIndex,
              rowIndex >= 0,
              rowIndex < suggestionContainerViewModel.numberOfRows else {
            if let defaultRow = suggestionContainerViewModel.defaultSelectedRow {
                tableView.selectRowIndexes(IndexSet(integer: defaultRow), byExtendingSelection: false)
                // Sync view model with the default selection so keyboard navigation works correctly
                suggestionContainerViewModel.selectRow(at: defaultRow)
            } else {
                self.clearSelection()
            }
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    }

    private func selectRowFromMousePoint(_ point: NSPoint) {
        let flippedPoint = view.convert(point, to: tableView)
        let tableRow = tableView.row(at: flippedPoint)

        guard tableRow >= 0 else {
            suggestionContainerViewModel.clearRowSelection()
            syncTableSelectionWithViewModel()
            return
        }

        guard suggestionContainerViewModel.isSelectableRow(tableRow) else {
            return
        }

        suggestionContainerViewModel.selectRow(at: tableRow)
        syncTableSelectionWithViewModel()
    }

    private func clearSelection() {
        tableView.deselectAll(self)
    }

    override func mouseMoved(with event: NSEvent) {
        selectRowFromMousePoint(event.locationInWindow)
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

        // Calculate total height considering different row heights (divider is smaller)
        var totalHeight: CGFloat = 0
        for row in 0..<totalRows {
            totalHeight += tableView(tableView, heightOfRow: row)
        }

        let barStyleProvider = themeManager.theme.addressBarStyleProvider

        if barStyleProvider.shouldLeaveBottomPaddingInSuggestions {
            tableViewHeightConstraint.constant = totalHeight
            + (tableView.enclosingScrollView?.contentInsets.top ?? 0)
            + (tableView.enclosingScrollView?.contentInsets.bottom ?? 0)
        } else {
            tableViewHeightConstraint.constant = totalHeight
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

        // Cache the viewModel row index
        selectedRowCache = tableView.selectedRow >= 0 ? tableView.selectedRow : nil

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
        guard let rowContent = suggestionContainerViewModel.rowContent(at: row) else {
            return nil
        }

        // Handle section divider separately
        if case .sectionDivider = rowContent {
            return makeSectionDividerView()
        }

        let cell = tableView.makeView(withIdentifier: SuggestionTableCellView.identifier, owner: self) as? SuggestionTableCellView ?? SuggestionTableCellView()
        cell.theme = themeManager.theme
        cell.isAIChatToggleBeingDisplayed = isAIChatToggleBeingDisplayed

        switch rowContent {
        case .searchCell:
            let userText = suggestionContainerViewModel.userStringValue ?? ""
            let searchIcon = themeManager.theme.iconsProvider.suggestionsIconsProvider.phraseEntryIcon
            cell.display(userText: userText, style: .search, icon: searchIcon, isBurner: self.isBurner)

        case .aiChatCell:
            let userText = suggestionContainerViewModel.userStringValue ?? ""
            let aiChatIcon: NSImage = .aiChat
            cell.display(userText: userText, style: .aiChat, icon: aiChatIcon, isBurner: self.isBurner)

        case .visitCell:
            let userText = suggestionContainerViewModel.userStringValue ?? ""
            let host = suggestionContainerViewModel.visitCellHost ?? ""
            let websiteIcon = themeManager.theme.iconsProvider.suggestionsIconsProvider.websiteEntryIcon
            cell.display(userText: userText, style: .visit(host: host), icon: websiteIcon, isBurner: self.isBurner)

        case .sectionDivider:
            break // Already handled above

        case .suggestion(let suggestionIndex):
            guard let suggestionViewModel = suggestionContainerViewModel.suggestionViewModel(at: suggestionIndex) else {
                assertionFailure("SuggestionViewController: Failed to get suggestion")
                return nil
            }
            cell.display(suggestionViewModel, isBurner: self.isBurner)
        }

        return cell
    }

    private static let sectionDividerViewIdentifier = NSUserInterfaceItemIdentifier("SectionDividerView")

    private func makeSectionDividerView() -> NSView {
        if let reusedView = tableView.makeView(withIdentifier: Self.sectionDividerViewIdentifier, owner: self) {
            return reusedView
        }

        let containerView = NSView()
        containerView.identifier = Self.sectionDividerViewIdentifier
        containerView.wantsLayer = true

        let dividerLine = NSView()
        dividerLine.wantsLayer = true
        dividerLine.layer?.backgroundColor = NSColor.addressBarSeparator.cgColor
        dividerLine.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(dividerLine)

        NSLayoutConstraint.activate([
            dividerLine.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            dividerLine.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            dividerLine.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            dividerLine.heightAnchor.constraint(equalToConstant: 1)
        ])

        return containerView
    }

    private static let sectionDividerRowHeight: CGFloat = 9

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if suggestionContainerViewModel.isDividerRow(row) {
            return Self.sectionDividerRowHeight
        }
        let barStyleProvider = themeManager.theme.addressBarStyleProvider
        return barStyleProvider.sizeForSuggestionRow(isHomePage: suggestionContainerViewModel.isHomePage)
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
        guard !isUpdatingTableSelection else { return }

        if tableView.selectedRow == -1 {
            suggestionContainerViewModel.clearRowSelection()
            return
        }

        guard suggestionContainerViewModel.isSelectableRow(tableView.selectedRow) else {
            return
        }

        if suggestionContainerViewModel.selectedRowIndex != tableView.selectedRow {
            suggestionContainerViewModel.selectRow(at: tableView.selectedRow)
        }
    }
}
