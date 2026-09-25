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
import FeatureFlags_macOS
import PrivacyConfig
import History
import Suggestions
import AIChat

protocol SuggestionViewControllerDelegate: AnyObject {

    func suggestionViewControllerDidConfirmSelection(_ suggestionViewController: SuggestionViewController)

}

final class SuggestionViewController: NSViewController {

    weak var delegate: SuggestionViewControllerDelegate?

    private(set) var shadowView: ShadowView!

    private(set) var backgroundView: ColorView!
    private(set) var innerBorderView: ColorView!
    private(set) var innerBorderViewTopConstraint: NSLayoutConstraint!
    private(set) var innerBorderViewBottomConstraint: NSLayoutConstraint!
    private(set) var innerBorderViewLeadingConstraint: NSLayoutConstraint!
    private(set) var innerBorderViewTrailingConstraint: NSLayoutConstraint!

    private(set) var tableView: NSTableView!
    private(set) var tableViewHeightConstraint: NSLayoutConstraint!
    private(set) var pixelPerfectConstraint: NSLayoutConstraint!
    private(set) var backgroundViewTopConstraint: NSLayoutConstraint!
    private(set) var topSeparatorView: NSView!
    private(set) var scrollView: NSScrollView!

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let suggestionContainerViewModel: SuggestionContainerViewModel
    private var isBurner: Bool {
        suggestionContainerViewModel.isBurner
    }

    private lazy var sectionDividerRowHeight: CGFloat = {
        let rebrandedHeight: CGFloat = 14
        let legacyHeight: CGFloat = 9
        return themeManager.isAppRebranded ? rebrandedHeight : legacyHeight
    }()

    private lazy var scrollViewBottomInset: CGFloat = {
        let rebrandedInset: CGFloat = 3
        let legacyInset: CGFloat = 5
        return themeManager.isAppRebranded ? rebrandedInset : legacyInset
    }()

    required init?(coder: NSCoder) {
        fatalError("SuggestionViewController: Bad initializer")
    }

    init(suggestionContainerViewModel: SuggestionContainerViewModel,
         themeManager: ThemeManaging,
         aiChatPreferencesStorage: AIChatPreferencesStorage,
         featureFlagger: FeatureFlagger) {
        self.suggestionContainerViewModel = suggestionContainerViewModel
        self.themeManager = themeManager
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        self.featureFlagger = featureFlagger
        super.init(nibName: nil, bundle: nil)
    }

    private enum LayoutConstants {
        static let shadowRadius: CGFloat = 8
        static let shadowCornerRadius: CGFloat = 14
        static let shadowInset: CGFloat = 20
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let scrollViewHorizontalInset: CGFloat = 4
        static let scrollViewTopInset: CGFloat = 21
        static let backgroundViewTopOverhang: CGFloat = -20
        static let tableViewHeight: CGFloat = 200
        static let rowHeight: CGFloat = 28
        static let scrollViewSize = CGSize(width: 609, height: 102)
    }

    /// Three nested containers: the outer one clips the drop shadow, the inner one clips the
    /// rounded background, and the background hosts the table so its top edge can slide under
    /// the address bar without the shadow showing through.
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 633, height: 267))

        let layoutView = NSView()
        layoutView.translatesAutoresizingMaskIntoConstraints = false

        let shadowClipView = NSView()
        shadowClipView.translatesAutoresizingMaskIntoConstraints = false

        shadowView = ShadowView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.shadowColor = .suggestionsShadow
        shadowView.shadowRadius = LayoutConstants.shadowRadius
        shadowView.cornerRadius = LayoutConstants.shadowCornerRadius
        shadowView.shadowOpacity = 1
        shadowClipView.addSubview(shadowView)

        let clipView = NSView()
        clipView.translatesAutoresizingMaskIntoConstraints = false

        backgroundView = ColorView(frame: .zero,
                                   backgroundColor: .addressBarBackground,
                                   cornerRadius: LayoutConstants.cornerRadius,
                                   borderColor: .addressBarBorder,
                                   borderWidth: LayoutConstants.borderWidth)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        innerBorderView = ColorView(frame: .zero,
                                    cornerRadius: LayoutConstants.cornerRadius,
                                    borderColor: .addressBarInnerBorder,
                                    borderWidth: LayoutConstants.borderWidth)
        innerBorderView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        let column = NSTableColumn()
        column.resizingMask = [.autoresizingMask, .userResizingMask]
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridColor = .gridColor
        tableView.rowHeight = LayoutConstants.rowHeight
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsMultipleSelection = false
        tableView.allowsExpansionToolTips = true
        tableView.autoresizingMask = [.width, .height]
        // A table created in code defaults to a 17pt horizontal intercell.
        // `viewDidLayout` sets the column to the full frame width, so any spacing makes
        // the table wider than the clip view and the suggestions scroll sideways.
        // The row's own 8pt/11pt insets provide all the padding needed.
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.setContentHuggingPriority(.init(750), for: .vertical)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0,
                                                width: LayoutConstants.scrollViewSize.width,
                                                height: LayoutConstants.scrollViewSize.height))
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Sized to the scroll view and resizing with it: starting at zero would leave the table
        // laid out against a collapsed container.
        let tableClipView = NSClipView(frame: scrollView.frame)
        tableClipView.translatesAutoresizingMaskIntoConstraints = true
        tableClipView.autoresizingMask = [.width, .height]
        tableClipView.drawsBackground = false
        tableClipView.backgroundColor = .clear
        tableClipView.documentView = tableView
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.usesPredominantAxisScrolling = false
        scrollView.horizontalLineScroll = LayoutConstants.rowHeight
        scrollView.verticalLineScroll = LayoutConstants.rowHeight
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 3, right: 0)
        scrollView.contentView = tableClipView

        backgroundView.addSubview(innerBorderView)
        backgroundView.addSubview(scrollView)

        topSeparatorView = ColorView(frame: .zero, backgroundColor: .addressBarSeparator)
        topSeparatorView.translatesAutoresizingMaskIntoConstraints = false

        clipView.addSubview(backgroundView)
        clipView.addSubview(topSeparatorView)

        layoutView.addSubview(shadowClipView)
        layoutView.addSubview(clipView)
        view.addSubview(layoutView)

        pixelPerfectConstraint = layoutView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        backgroundViewTopConstraint = scrollView.topAnchor
            .constraint(equalTo: backgroundView.topAnchor, constant: LayoutConstants.scrollViewTopInset)
        innerBorderViewTopConstraint = innerBorderView.topAnchor
            .constraint(equalTo: backgroundView.topAnchor, constant: LayoutConstants.borderWidth)
        innerBorderViewBottomConstraint = backgroundView.bottomAnchor
            .constraint(equalTo: innerBorderView.bottomAnchor, constant: LayoutConstants.borderWidth)
        innerBorderViewLeadingConstraint = innerBorderView.leadingAnchor
            .constraint(equalTo: backgroundView.leadingAnchor, constant: LayoutConstants.borderWidth)
        innerBorderViewTrailingConstraint = backgroundView.trailingAnchor
            .constraint(equalTo: innerBorderView.trailingAnchor, constant: LayoutConstants.borderWidth)
        tableViewHeightConstraint = clipView.heightAnchor
            .constraint(equalToConstant: LayoutConstants.tableViewHeight)
        tableViewHeightConstraint.priority = .init(950)

        NSLayoutConstraint.activate([
            layoutView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: layoutView.bottomAnchor),
            layoutView.widthAnchor.constraint(equalTo: view.widthAnchor),
            pixelPerfectConstraint,

            shadowClipView.leadingAnchor.constraint(equalTo: layoutView.leadingAnchor),
            layoutView.trailingAnchor.constraint(equalTo: shadowClipView.trailingAnchor),
            shadowClipView.topAnchor.constraint(equalTo: layoutView.topAnchor, constant: LayoutConstants.borderWidth),
            layoutView.bottomAnchor.constraint(equalTo: shadowClipView.bottomAnchor),

            shadowView.leadingAnchor.constraint(equalTo: shadowClipView.leadingAnchor,
                                                constant: LayoutConstants.shadowInset),
            shadowClipView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor,
                                                     constant: LayoutConstants.shadowInset),
            shadowView.topAnchor.constraint(equalTo: shadowClipView.topAnchor,
                                            constant: -LayoutConstants.shadowCornerRadius),
            shadowClipView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor,
                                                   constant: LayoutConstants.shadowInset),

            clipView.leadingAnchor.constraint(equalTo: layoutView.leadingAnchor, constant: LayoutConstants.shadowInset),
            layoutView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor, constant: LayoutConstants.shadowInset),
            clipView.topAnchor.constraint(equalTo: layoutView.topAnchor),
            layoutView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor, constant: LayoutConstants.shadowInset),
            clipView.heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutConstants.rowHeight),
            tableViewHeightConstraint,

            backgroundView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: clipView.topAnchor,
                                                constant: LayoutConstants.backgroundViewTopOverhang),
            clipView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            innerBorderViewTopConstraint,
            innerBorderViewBottomConstraint,
            innerBorderViewLeadingConstraint,
            innerBorderViewTrailingConstraint,

            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor,
                                                constant: LayoutConstants.scrollViewHorizontalInset),
            backgroundView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor,
                                                     constant: LayoutConstants.scrollViewHorizontalInset),
            backgroundViewTopConstraint,
            backgroundView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            topSeparatorView.heightAnchor.constraint(equalToConstant: LayoutConstants.borderWidth),
            topSeparatorView.topAnchor.constraint(equalTo: clipView.topAnchor),
            topSeparatorView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor,
                                                      constant: LayoutConstants.borderWidth),
            clipView.trailingAnchor.constraint(equalTo: topSeparatorView.trailingAnchor,
                                               constant: LayoutConstants.borderWidth),
        ])

        self.view = view
    }

    private var suggestionResultCancellable: AnyCancellable?
    private var selectionSyncCancellable: AnyCancellable?

    private var eventMonitorCancellables = Set<AnyCancellable>()
    private var appObserver: Any?

    /// Flag to prevent re-entrancy when programmatically updating table selection
    private var isUpdatingTableSelection = false
    private var isAIChatToggleBeingDisplayed: Bool = false
    private let aiChatPreferencesStorage: AIChatPreferencesStorage
    private let featureFlagger: FeatureFlagger

    override func viewDidLoad() {
        super.viewDidLoad()

        setupTableView()
        addTrackingArea()
        subscribeToSuggestionResult()
        subscribeToSelectionSync()
        setupRoundedCorners()
        subscribeToThemeChanges()
        applyThemeStyle()

        topSeparatorView?.isHidden = true
    }

    private func updateAIChatToggleFlag() {
        let isToggleFeatureEnabled = aiChatPreferencesStorage.isAIFeaturesEnabled
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
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .plain
        tableView.enclosingScrollView?.contentInsets.bottom = scrollViewBottomInset
        tableView.setAccessibilityIdentifier("SuggestionViewController.tableView")
    }

    private func setupRoundedCorners() {
        guard themeManager.isAppRebranded else {
            return
        }

        let roundedCorners: RoundedCorners = [.bottomLeft, .bottomRight]
        backgroundView.roundedCorners = roundedCorners
        innerBorderView.roundedCorners = roundedCorners
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

    @objc func confirmButtonAction(_ sender: NSButton) {
        delegate?.suggestionViewControllerDidConfirmSelection(self)
        closeWindow()
    }

    @objc func removeButtonAction(_ sender: NSButton) {
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
        if suggestionContainerViewModel.suggestionContainer.result != nil {
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
            self.clearSelection()
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
        backgroundView.setCornerRadius(barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions)
        innerBorderView.setCornerRadius(barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions)

        shadowView.shadowSides = [.left, .right, .bottom]
        shadowView.shadowRadius = barStyleProvider.suggestionShadowRadius
        shadowView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions

        NSAppearance.withAppearance(from: view) {
            shadowView.shadowColor = colorsProvider.addressBarShadowColor
            backgroundView.backgroundColor = colorsProvider.suggestionsBackgroundColor(isBurner: isBurner)
        }

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
        guard let rowContent = suggestionContainerViewModel.rowContent(at: row) else { return nil }

        // Handle section divider separately
        if case .sectionDivider = rowContent {
            return makeSectionDividerView()
        }

        let cell = tableView.makeView(withIdentifier: SuggestionTableCellView.identifier,
                                      owner: self) as? SuggestionTableCellView ?? SuggestionTableCellView(frame: .zero)
        cell.setActionTarget(self,
                             confirmAction: #selector(confirmButtonAction(_:)),
                             removeAction: #selector(removeButtonAction(_:)))
        cell.theme = themeManager.theme

        /// `isAIChatToggleBeingDisplayed` adds an extra leading padding. The AppRebrand new UX already picks the right leading padding via `AddressBarStyleProviding`
        cell.isAIChatToggleBeingDisplayed = isAIChatToggleBeingDisplayed && !themeManager.isAppRebranded

        switch rowContent {
        case .aiChatCell:
            let userText = suggestionContainerViewModel.userStringValue ?? ""
            let aiChatIcon: NSImage = .aiChat
            cell.display(userText: userText, style: .aiChat, icon: aiChatIcon, isBurner: self.isBurner)

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

        let isAppRebranded = themeManager.isAppRebranded
        let leadingConstant: CGFloat = isAppRebranded ? 0 : 12
        let trailingConstant: CGFloat = isAppRebranded ? 0 : -12

        let verticalConstraint: NSLayoutConstraint = {
            if isAppRebranded {
                return dividerLine.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8)
            }

            return dividerLine.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        }()

        NSLayoutConstraint.activate([
            dividerLine.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingConstant),
            dividerLine.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: trailingConstant),
            dividerLine.heightAnchor.constraint(equalToConstant: 1),
            verticalConstraint
        ])

        return containerView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if suggestionContainerViewModel.isDividerRow(row) {
            return sectionDividerRowHeight
        }
        let barStyleProvider = themeManager.theme.addressBarStyleProvider
        return barStyleProvider.sizeForSuggestionRow(isHomePage: suggestionContainerViewModel.isHomePage)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let suggestionTableRowView = tableView.makeView(withIdentifier: SuggestionTableRowView.identifier,
                                                        owner: self) as? SuggestionTableRowView ?? SuggestionTableRowView()

        suggestionTableRowView.theme = themeManager.theme
        suggestionTableRowView.isAppRebranded = themeManager.isAppRebranded
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
