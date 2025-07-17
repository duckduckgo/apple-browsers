//
//  BookmarkManagementDetailViewController.swift
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
import Carbon
import Combine
import Common
import SwiftUI

protocol BookmarkManagementDetailViewControllerDelegate: AnyObject {

    func bookmarkManagementDetailViewControllerDidSelectFolder(_ folder: BookmarkFolder)
    func bookmarkManagementDetailViewControllerDidStartSearching()
    func bookmarkManagementDetailViewControllerSortChanged(_ mode: BookmarksSortMode)

}

private struct EditedBookmarkMetadata {
    let uuid: String
    let index: Int
}

final class BookmarkManagementDetailViewController: NSViewController, NSMenuItemValidation {

    // adjust spacing between image and title in toolbar
    // buttons to ~5px
    private static let thinSpace = "\u{2009}"

    private let toolbarButtonsStackView = NSStackView()
    private lazy var newBookmarkButton = MouseOverButton(title: Self.thinSpace + UserText.newBookmark, target: self, action: #selector(presentAddBookmarkModal))
        .withAccessibilityIdentifier("BookmarkManagementDetailViewController.newBookmarkButton")
    private lazy var newFolderButton = MouseOverButton(title: Self.thinSpace + UserText.newFolder, target: tableView.menu, action: #selector(FolderMenuItemSelectors.newFolder))
        .withAccessibilityIdentifier("BookmarkManagementDetailViewController.newFolderButton")
    private lazy var deleteItemsButton = MouseOverButton(title: Self.thinSpace + UserText.bookmarksBarContextMenuDelete, target: self, action: #selector(delete))
        .withAccessibilityIdentifier("BookmarkManagementDetailViewController.deleteItemsButton")
    private lazy var sortItemsButton = MouseOverButton(title: Self.thinSpace + UserText.bookmarksSort.capitalized, target: self, action: #selector(sortBookmarks))
        .withAccessibilityIdentifier("BookmarkManagementDetailViewController.sortItemsButton")

    lazy var searchBar = NSSearchField()
        .withAccessibilityIdentifier("BookmarkManagementDetailViewController.searchBar")
    private lazy var separator = NSBox()
    private lazy var scrollView = NSScrollView()
    private lazy var tableView = NSTableView()

    private lazy var loadingProgressIndicator = NSProgressIndicator()
    private lazy var emptyState = NSView()
    private lazy var emptyStateImageView = NSImageView(image: .bookmarksEmpty)
        .withAccessibilityIdentifier(BookmarksEmptyStateContent.imageAccessibilityIdentifier)
    private lazy var emptyStateTitle = NSTextField()
        .withAccessibilityIdentifier(BookmarksEmptyStateContent.titleAccessibilityIdentifier)
    private lazy var emptyStateMessage = NSTextField()
        .withAccessibilityIdentifier(BookmarksEmptyStateContent.descriptionAccessibilityIdentifier)
    private lazy var importButton = NSButton(title: UserText.importBookmarksButtonTitle, target: self, action: #selector(onImportClicked))

    weak var delegate: BookmarkManagementDetailViewControllerDelegate?

    let managementDetailViewModel: BookmarkManagementDetailViewModel
    private let bookmarkManager: BookmarkManager
    private let dragDropManager: BookmarkDragDropManager
    private let sortBookmarksViewModel: SortBookmarksViewModel
    private let visualStyle: VisualStyleProviding
    private var selectionState: BookmarkManagementSidebarViewController.SelectionState = .empty {
        didSet {
            reloadData()
        }
    }
    private var cancellables = Set<AnyCancellable>()

    private var documentView = FlippedView()

    private lazy var syncPromoManager: SyncPromoManaging = SyncPromoManager()

    private lazy var syncPromoViewHostingView: NSView = {
        let model = SyncPromoViewModel(touchpointType: .bookmarks, primaryButtonAction: { [weak self] in
            self?.syncPromoManager.goToSyncSettings(for: .bookmarks)
        }, dismissButtonAction: { [weak self] in
            self?.syncPromoManager.dismissPromoFor(.bookmarks)
        })

        let headerView = SyncPromoView(viewModel: model,
                                       layout: .auto(verticalLayoutTopPadding: 0),
                                       autoLayoutWidthThreshold: 525)

        let hostingView = NSHostingView(rootView: headerView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return hostingView
    }()

    func update(selectionState: BookmarkManagementSidebarViewController.SelectionState) {
        if case .folder = selectionState {
            clearSearch()
        }

        managementDetailViewModel.update(selection: selectionState,
                                         mode: sortBookmarksViewModel.selectedSortMode,
                                         searchQuery: searchBar.stringValue)
        self.selectionState = selectionState
    }

    init(bookmarkManager: BookmarkManager,
         dragDropManager: BookmarkDragDropManager,
         visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle) {
        self.bookmarkManager = bookmarkManager
        self.dragDropManager = dragDropManager
        let metrics = BookmarksSearchAndSortMetrics()
        let navigationEngagementMetrics = BookmarksNavigationEngagementMetrics()
        let sortViewModel = SortBookmarksViewModel(manager: bookmarkManager, metrics: metrics, origin: .manager)
        self.sortBookmarksViewModel = sortViewModel
        self.visualStyle = visualStyle
        self.managementDetailViewModel = BookmarkManagementDetailViewModel(bookmarkManager: bookmarkManager,
                                                                           metrics: metrics,
                                                                           navigationEngagementMetrics: navigationEngagementMetrics,
                                                                           mode: bookmarkManager.sortMode)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    override func loadView() {
        let showSyncPromo = syncPromoManager.shouldPresentPromoFor(.bookmarks)
        view = ColorView(frame: .zero, backgroundColor: visualStyle.colorsProvider.bookmarksManagerBackgroundColor)
        view.translatesAutoresizingMaskIntoConstraints = false

        // set menu before `newFolderButton` initialization as it uses the menu as its target
        tableView.menu = BookmarksContextMenu(bookmarkManager: bookmarkManager, delegate: self)

        view.addSubview(separator)
        view.addSubview(scrollView)
        view.addSubview(loadingProgressIndicator)
        view.addSubview(emptyState)
        view.addSubview(toolbarButtonsStackView)
        view.addSubview(searchBar)

        toolbarButtonsStackView.addArrangedSubview(newBookmarkButton)
        toolbarButtonsStackView.addArrangedSubview(newFolderButton)
        toolbarButtonsStackView.addArrangedSubview(deleteItemsButton)
        toolbarButtonsStackView.addArrangedSubview(sortItemsButton)
        toolbarButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        toolbarButtonsStackView.distribution = .fill
        toolbarButtonsStackView.setClippingResistancePriority(.defaultHigh, for: .horizontal)

        configureToolbarButton(newBookmarkButton, image: visualStyle.iconsProvider.bookmarksIconsProvider.addBookmarkIcon, isHidden: false)
        configureToolbarButton(newFolderButton, image: visualStyle.iconsProvider.bookmarksIconsProvider.addBookmarkFolderIcon, isHidden: false)
        configureToolbarButton(deleteItemsButton, image: visualStyle.iconsProvider.bookmarksIconsProvider.deleteBookmarkIcon, isHidden: false)
        configureToolbarButton(sortItemsButton, image: visualStyle.iconsProvider.bookmarksIconsProvider.sortBookmarkManuallyIcon, isHidden: false)

        loadingProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingProgressIndicator.style = .spinning
        loadingProgressIndicator.isHidden = true

        emptyState.addSubview(emptyStateImageView)
        emptyState.addSubview(emptyStateTitle)
        emptyState.addSubview(emptyStateMessage)
        emptyState.addSubview(importButton)

        emptyState.isHidden = true
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        importButton.translatesAutoresizingMaskIntoConstraints = false

        configureEmptyState(
            label: emptyStateTitle,
            font: .systemFont(ofSize: 15, weight: .semibold),
            attributedTitle: .make(
                UserText.bookmarksEmptyStateTitle,
                lineHeight: 1.14,
                kern: -0.23
            )
        )

        configureEmptyState(
            label: emptyStateMessage,
            font: .systemFont(ofSize: 13),
            attributedTitle: .make(
                UserText.bookmarksEmptyStateMessage,
                lineHeight: 1.05,
                kern: -0.08
            )
        )

        emptyStateImageView.setContentHuggingPriority(.init(rawValue: 251), for: .horizontal)
        emptyStateImageView.setContentHuggingPriority(.init(rawValue: 251), for: .vertical)
        emptyStateImageView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateImageView.imageScaling = .scaleProportionallyDown

        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.usesPredominantAxisScrolling = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.scrollerInsets = NSEdgeInsets(top: -22, left: 0, bottom: -22, right: 0)
        scrollView.contentInsets = NSEdgeInsets(top: 22, left: 0, bottom: 22, right: 0)

        let clipView = NSClipView()

        if !showSyncPromo {
            clipView.documentView = tableView

            clipView.autoresizingMask = [.width, .height]
            clipView.backgroundColor = .clear
            clipView.drawsBackground = false
            clipView.frame = CGRect(x: 0, y: 0, width: 640, height: 601)
            scrollView.contentView = clipView
        }

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tableView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
        tableView.usesAutomaticRowHeights = true
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.delegate = self
        tableView.dataSource = self

        separator.boxType = .separator
        separator.setContentHuggingPriority(.defaultHigh, for: .vertical)
        separator.translatesAutoresizingMaskIntoConstraints = false

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholderString = UserText.bookmarksSearch
        searchBar.delegate = self

        view.addSubview(KeyEquivalentView(keyEquivalents: [
            [.command, "f"]: { [weak self] in
                return self?.handleCmdF($0) ?? false
            }
        ]))
        if showSyncPromo {
            setupSyncPromoView()
        }

        setupLayout()
    }

    private func setupLayout() {
        newBookmarkButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        newBookmarkButton.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        newFolderButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        newFolderButton.setContentCompressionResistancePriority(.init(251), for: .horizontal)
        deleteItemsButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        deleteItemsButton.setContentCompressionResistancePriority(.init(252), for: .horizontal)
        sortItemsButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sortItemsButton.setContentCompressionResistancePriority(.init(253), for: .horizontal)

        NSLayoutConstraint.activate([
            toolbarButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 16),
            separator.topAnchor.constraint(equalTo: toolbarButtonsStackView.bottomAnchor, constant: 24),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),

            searchBar.heightAnchor.constraint(equalToConstant: 28),
            searchBar.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarButtonsStackView.trailingAnchor, constant: 8),
            searchBar.widthAnchor.constraint(equalToConstant: 256).priority(150),
            searchBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            searchBar.centerYAnchor.constraint(equalTo: toolbarButtonsStackView.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: searchBar.trailingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 16),
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            loadingProgressIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingProgressIndicator.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbarButtonsStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            emptyState.topAnchor.constraint(greaterThanOrEqualTo: separator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            newBookmarkButton.heightAnchor.constraint(equalToConstant: 24),
            newBookmarkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            newFolderButton.heightAnchor.constraint(equalToConstant: 24),
            deleteItemsButton.heightAnchor.constraint(equalToConstant: 24),
            sortItemsButton.heightAnchor.constraint(equalToConstant: 24),

            newBookmarkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            newFolderButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            deleteItemsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            emptyStateMessage.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),

            importButton.topAnchor.constraint(equalTo: emptyStateMessage.bottomAnchor, constant: 8),
            emptyState.heightAnchor.constraint(equalToConstant: 218).priority(150),
            emptyStateMessage.topAnchor.constraint(equalTo: emptyStateTitle.bottomAnchor, constant: 8),
            importButton.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            emptyStateImageView.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            emptyState.widthAnchor.constraint(equalToConstant: 224),
            emptyStateImageView.topAnchor.constraint(equalTo: emptyState.topAnchor),
            emptyStateTitle.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            emptyStateTitle.topAnchor.constraint(equalTo: emptyStateImageView.bottomAnchor, constant: 8),

            emptyStateMessage.widthAnchor.constraint(equalToConstant: 192),

            emptyStateTitle.widthAnchor.constraint(equalToConstant: 192),

            emptyStateImageView.widthAnchor.constraint(equalToConstant: 128),
            emptyStateImageView.heightAnchor.constraint(equalToConstant: 96)
        ])

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.setDraggingSourceOperationMask([.move], forLocal: true)
        tableView.registerForDraggedTypes(BookmarkDragDropManager.draggedTypes)

        reloadData()
    }

    override func viewDidAppear() {
        subscribeToSelectedSortMode()
        subscribeToFirstResponder()
        // reloadData() will be called from BookmarkManagementSidebarViewController → dataSource.$selectedFolders observer → update(selectionState:)
        // updatesyncPromoViewHostingVisibility() will be called from reloadData()
    }

    override func viewWillDisappear() {
        cancellables.removeAll()
    }

    private func subscribeToSelectedSortMode() {
        sortBookmarksViewModel.$selectedSortMode.sink { [weak self] newSortMode in
            guard let self else { return }

            switch newSortMode {
            case .nameDescending:
                self.sortItemsButton.title = Self.thinSpace + UserText.bookmarksSortByNameTitle
                self.sortItemsButton.image = visualStyle.iconsProvider.bookmarksIconsProvider.sortBookmarkDescendingIcon
            case .nameAscending:
                self.sortItemsButton.title = Self.thinSpace + UserText.bookmarksSortByNameTitle
                self.sortItemsButton.image = visualStyle.iconsProvider.bookmarksIconsProvider.sortBookmarkAscendingIcon
            case .manual:
                self.sortItemsButton.title = Self.thinSpace + UserText.bookmarksSort
                self.sortItemsButton.image = visualStyle.iconsProvider.bookmarksIconsProvider.sortBookmarkManuallyIcon
            }

            delegate?.bookmarkManagementDetailViewControllerSortChanged(newSortMode)
            self.setupSort(mode: newSortMode)
        }.store(in: &cancellables)
    }

    private func subscribeToFirstResponder() {
        guard let window = view.window else {
            assert([.unitTests, .integrationTests].contains(AppVersion.runType),
                   "BookmarkManagementDetailViewController.subscribeToFirstResponder: view.window is nil")
            return
        }
        NotificationCenter.default
            .publisher(for: MainWindow.firstResponderDidChangeNotification, object: window)
            .sink { [weak self] in
                self?.firstResponderDidChange($0)
            }
            .store(in: &cancellables)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelectedItems()
        default:
            super.keyDown(with: event)
        }
    }

    private func handleCmdF(_ event: NSEvent) -> Bool {
        guard case .nonEmpty = managementDetailViewModel.contentState else {
            __NSBeep()
            return true
        }
        searchBar.makeMeFirstResponder()
        return true
    }

    fileprivate func reloadData() {
        handleItemsVisibility()

        let scrollPosition = tableView.visibleRect.origin
        tableView.reloadData()
        tableView.scroll(scrollPosition)

        updateToolbarButtons()
    }

    private func handleItemsVisibility() {
        switch managementDetailViewModel.contentState {
        case .empty(let emptyState):
            showEmptyStateView(for: emptyState)
        case .nonEmpty:
            emptyState.isHidden = true
            loadingProgressIndicator.stopAnimation(nil)
            loadingProgressIndicator.isHidden = true
            tableView.isHidden = false
            searchBar.isEnabled = true
            sortItemsButton.isEnabled = true
        case .loading:
            emptyState.isHidden = true
            tableView.isHidden = true
            loadingProgressIndicator.isHidden = false
            loadingProgressIndicator.startAnimation(nil)
            searchBar.isEnabled = false
            sortItemsButton.isEnabled = false
        }
        updatesyncPromoViewHostingVisibility()
    }

    private func showEmptyStateView(for mode: BookmarksEmptyStateContent) {
        tableView.isHidden = true
        emptyState.isHidden = false
        loadingProgressIndicator.isHidden = true
        loadingProgressIndicator.stopAnimation(nil)
        emptyStateTitle.stringValue = mode.title
        emptyStateMessage.stringValue = mode.description
        emptyStateImageView.image = mode.image
        importButton.isHidden = mode.shouldHideImportButton
        searchBar.isEnabled = mode != .noBookmarks
        sortItemsButton.isEnabled = mode != .noBookmarks
    }

    @objc func onImportClicked(_ sender: NSButton) {
        DataImportView(isDataTypePickerExpanded: true).show()
    }

    @objc func handleDoubleClick(_ sender: NSTableView) {
        if sender.selectedRowIndexes.count > 1 {
            let entities = sender.selectedRowIndexes.map { fetchEntity(at: $0) }
            let bookmarks = entities.compactMap { $0 as? Bookmark }
            openBookmarksInNewTabs(bookmarks)

            return
        }

        let index = sender.clickedRow

        guard index != -1, let entity = fetchEntity(at: index) else {
            return
        }

        managementDetailViewModel.onBookmarkTapped()

        if let bookmark = entity as? Bookmark {
            managementDetailViewModel.onNavigateToBookmark(bookmark)
            Application.appDelegate.windowControllersManager.open(bookmark, with: NSApp.currentEvent)
        } else if let folder = entity as? BookmarkFolder {
            clearSearch()
            resetSelections()
            delegate?.bookmarkManagementDetailViewControllerDidSelectFolder(folder)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard case .middle = event.button,
              let row = tableView.withMouseLocationInViewCoordinates(event.locationInWindow, convert: tableView.row(at:)), row != -1,
              let bookmark = fetchEntity(at: row) as? Bookmark else { return }

        Application.appDelegate.windowControllersManager.open(bookmark, with: NSApp.currentEvent)
    }

    @objc func presentAddBookmarkModal(_ sender: Any) {
        BookmarksDialogViewFactory.makeAddBookmarkView(parent: selectionState.folder, bookmarkManager: bookmarkManager)
            .show(in: view.window)
    }

    private func firstResponderDidChange(_ notification: Notification) {
        // clear delete undo history when activating the Address Bar
        if view.window?.firstResponder is AddressBarTextEditor {
            undoManager?.removeAllActions(withTarget: bookmarkManager)
        }
    }

    @objc func delete(_ sender: AnyObject) {
        if tableView.selectedRowIndexes.isEmpty {
            guard let folder = selectionState.folder else {
                assertionFailure("Cannot delete root folder")
                return
            }
            bookmarkManager.remove(folder: folder, undoManager: undoManager)
            return
        }

        deleteSelectedItems()
    }

    @objc func sortBookmarks(_ sender: NSButton) {
        let menu = sortBookmarksViewModel.menu
        managementDetailViewModel.onSortButtonTapped()
        menu.popUpAtMouseLocation(in: sortItemsButton)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(BookmarkManagementDetailViewController.delete(_:)):
            return !tableView.selectedRowIndexes.isEmpty
        default:
            return true
        }
    }

    private func setupSort(mode: BookmarksSortMode) {
        clearSearch()
        managementDetailViewModel.update(selection: selectionState, mode: mode)
        tableView.reloadData()
        sortItemsButton.backgroundColor = mode.shouldHighlightButton ? .buttonMouseDown : .clear
        sortItemsButton.mouseOverColor = mode.shouldHighlightButton ? .buttonMouseDown : .buttonMouseOver
    }

    private func clearSearch() {
        searchBar.stringValue = ""
    }

    private func totalRows() -> Int {
        return managementDetailViewModel.totalRows()
    }

    private func deleteSelectedItems() {
        guard !tableView.selectedRowIndexes.isEmpty else {
            return
        }
        let entities = tableView.selectedRowIndexes.compactMap { fetchEntity(at: $0) }
        let entityUUIDs = entities.map(\.id)

        bookmarkManager.remove(objectsWithUUIDs: entityUUIDs, undoManager: undoManager)
    }

    private(set) lazy var faviconsFetcherOnboarding: FaviconsFetcherOnboarding? = {
        guard let syncService = NSApp.delegateTyped.syncService, let syncBookmarksAdapter = NSApp.delegateTyped.syncDataProviders?.bookmarksAdapter else {
            assertionFailure("SyncService and/or SyncBookmarksAdapter is nil")
            return nil
        }
        return .init(syncService: syncService, syncBookmarksAdapter: syncBookmarksAdapter)
    }()
}

// MARK: - NSTableView

extension BookmarkManagementDetailViewController: NSTableViewDelegate, NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return totalRows()
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return fetchEntity(at: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = BookmarkTableRowView()
        rowView.onSelectionChanged = onSelectionChanged

        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let entity = fetchEntity(at: row) else { return nil }

        let cell = tableView.makeView(withIdentifier: .init(BookmarkTableCellView.className()), owner: nil) as? BookmarkTableCellView
        ?? BookmarkTableCellView(identifier: .init(BookmarkTableCellView.className()), visualStyle: visualStyle)

        cell.delegate = self

        if let bookmark = entity as? Bookmark {
            cell.update(from: bookmark)

            if bookmark.favicon(.small) == nil {
                faviconsFetcherOnboarding?.presentOnboardingIfNeeded()
            }
        } else if let folder = entity as? BookmarkFolder {
            cell.update(from: folder)
        } else {
            assertionFailure("Failed to cast bookmark")
        }
        cell.isSelected = tableView.selectedRowIndexes.contains(row)

        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let entity = fetchEntity(at: row) else { return nil }
        return entity.pasteboardWriter
    }

    private func destination(for dropOperation: NSTableView.DropOperation, at row: Int) -> Any {
        switch dropOperation {
        case .on:
            if let entity = fetchEntity(at: row) {
                return entity
            }
        case .above:
            if let folder = selectionState.folder {
                return folder
            }
        @unknown default: preconditionFailure()
        }
        return selectionState == .favorites ? PseudoFolder.favorites : PseudoFolder.bookmarks
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if !sortBookmarksViewModel.selectedSortMode.isReorderingEnabled { return .none }
        let destination = destination(for: dropOperation, at: row)

        guard !isSearching || destination is BookmarkFolder else { return .none }

        return dragDropManager.validateDrop(info, to: destination)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {

        let destination = destination(for: dropOperation, at: row)
        let index = dropOperation == .above ? row : -1

        return dragDropManager.acceptDrop(info, to: destination, at: index)
    }

    private func fetchEntity(at row: Int) -> BaseBookmarkEntity? {
        return managementDetailViewModel.fetchEntity(at: row)
    }

    /// Updates the next/previous selection state of each row, and clears the selection flag.
    fileprivate func resetSelections() {
        guard totalRows() > 0 else { return }

        let indexes = tableView.selectedRowIndexes
        for index in 0 ..< totalRows() {
            let row = self.tableView.rowView(atRow: index, makeIfNecessary: false) as? BookmarkTableRowView
            row?.hasPrevious = indexes.contains(index - 1)
            row?.hasNext = indexes.contains(index + 1)

            let cell = self.tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? BookmarkTableCellView
            cell?.isSelected = false
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelectionChanged()
    }

    func onSelectionChanged() {
        func updateCellSelections() {
            resetSelections()
            tableView.selectedRowIndexes.forEach {
                let cell = self.tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? BookmarkTableCellView
                cell?.isSelected = true
            }
        }

        updateCellSelections()
        updateToolbarButtons()
    }

    private func updateToolbarButtons() {
        newFolderButton.cell?.representedObject = selectionState.folder

        let selectedRowsCount = tableView.selectedRowIndexes.count
        let canDeleteFolder = selectionState.folder != nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            if selectedRowsCount > 0 {
                deleteItemsButton.animator().title = UserText.delete
                deleteItemsButton.animator().isEnabled = true
            } else if canDeleteFolder {
                deleteItemsButton.animator().title = UserText.deleteFolder
                deleteItemsButton.animator().isEnabled = true
            } else {
                deleteItemsButton.animator().title = UserText.delete
                deleteItemsButton.animator().isEnabled = false
            }
            newBookmarkButton.animator().isEnabled = selectedRowsCount <= 1
            newFolderButton.animator().isEnabled = selectedRowsCount <= 1
        }
    }

    fileprivate func openBookmarksInNewTabs(_ bookmarks: [Bookmark]) {
        guard let tabCollection = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else {
            assertionFailure("Cannot open in new tabs")
            return
        }

        let tabs = bookmarks.compactMap { bookmark -> Tab? in
            guard let url = bookmark.urlObject else {
                return nil
            }

            return Tab(content: .url(url, source: .bookmark(isFavorite: bookmark.isFavorite)),
                       shouldLoadInBackground: true,
                       burnerMode: tabCollection.burnerMode)
        }
        tabCollection.append(tabs: tabs, andSelect: true)
    }
}

// MARK: - Private

private extension BookmarkManagementDetailViewController {

    func configureToolbarButton(_ button: MouseOverButton, image: NSImage, isHidden: Bool) {
        button.bezelStyle = .shadowlessSquare
        button.cornerRadius = 4
        button.normalTintColor = .button
        button.mouseDownColor = .buttonMouseDown
        button.mouseOverColor = .buttonMouseOver
        button.imageHugsTitle = true
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.alignment = .center
        button.font = .systemFont(ofSize: 13)
        button.image = image
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.isHidden = isHidden
        button.lineBreakMode = .byTruncatingTail
        button.cell?.wraps = false
    }

    func configureEmptyState(label: NSTextField, font: NSFont, attributedTitle: NSAttributedString) {
        label.isEditable = false
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentHuggingPriority(.init(rawValue: 251), for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.drawsBackground = false
        label.isBordered = false
        label.font = font
        label.textColor = .labelColor
        label.attributedStringValue = attributedTitle
    }

}

// MARK: - BookmarkTableCellViewDelegate

extension BookmarkManagementDetailViewController: BookmarkTableCellViewDelegate {

    func bookmarkTableCellViewRequestedMenu(_ sender: NSButton, cell: BookmarkTableCellView) {
        // will update the menu using `BookmarksContextMenuDelegate.selectedItems`
        tableView.menu?.popUpAtMouseLocation(in: cell)
    }

}

// MARK: - BookmarksContextMenuDelegate

extension BookmarkManagementDetailViewController: BookmarksContextMenuDelegate {

    var isSearching: Bool { managementDetailViewModel.isSearching }

    var parentFolder: BookmarkFolder? {
        return managementDetailViewModel.fetchParent()
    }

    var shouldIncludeManageBookmarksItem: Bool { false }

    func selectedItems() -> [Any] {
        guard let row = tableView.clickedRowIfValid ?? tableView.withMouseLocationInViewCoordinates(convert: { point in
            tableView.row(at: point)
        }), row != -1 else { return [] }

        // If only one item is selected try to get the item and its parent folder otherwise show the menu for multiple items.
        if tableView.selectedRowIndexes.contains(row), tableView.selectedRowIndexes.count > 1 {
            return tableView.selectedRowIndexes.compactMap { index in
                return fetchEntity(at: index)
            }
        }

        return fetchEntity(at: row).map { [$0] } ?? []
    }

    func showDialog(_ dialog: any ModalView) {
        dialog.show(in: view.window)
    }

    func closePopoverIfNeeded() {}

}

extension BookmarkManagementDetailViewController: BookmarkSearchMenuItemSelectors {
    func showInFolder(_ sender: NSMenuItem) {
        guard let baseBookmark = sender.representedObject as? BaseBookmarkEntity else {
            assertionFailure("Failed to retrieve Bookmark from Show in Folder context menu item")
            return
        }

        if let bookmark = baseBookmark as? Bookmark,
            let folder = managementDetailViewModel.searchForParent(bookmark: bookmark) {
            delegate?.bookmarkManagementDetailViewControllerDidSelectFolder(folder)
        } else if let folder = baseBookmark as? BookmarkFolder {
            delegate?.bookmarkManagementDetailViewControllerDidSelectFolder(folder)
        }
    }
}

// MARK: - Search field delegate

extension BookmarkManagementDetailViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        if let searchField = obj.object as? NSSearchField {
            managementDetailViewModel.update(selection: selectionState,
                                             mode: sortBookmarksViewModel.selectedSortMode,
                                             searchQuery: searchField.stringValue)
            delegate?.bookmarkManagementDetailViewControllerDidStartSearching()
            reloadData()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchBar else {
            assertionFailure("Unexpected delegating control")
            return false
        }
        switch selector {
        case #selector(cancelOperation):
            // handle Esc key press while in search mode
            self.tableView.makeMeFirstResponder()
        default:
            return false
        }
        return true
    }

}

// MARK: - Sync Promo

extension BookmarkManagementDetailViewController {

    private func setupSyncPromoView() {
        documentView.addSubview(syncPromoViewHostingView)
        documentView.addSubview(tableView)

        scrollView.contentView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = documentView

        documentView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        tableView.focusRingType = .none

        setupSyncPromoLayout()
    }

    private func setupSyncPromoLayout() {
        NSLayoutConstraint.activate([
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.contentView.trailingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 224),
        ])

        NSLayoutConstraint.activate([
            syncPromoViewHostingView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 0),
            syncPromoViewHostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 2),
            syncPromoViewHostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -2),

            tableView.topAnchor.constraint(equalTo: syncPromoViewHostingView.bottomAnchor, constant: 4)
                .autoDeactivatedWhenViewIsHidden(syncPromoViewHostingView),

            tableView.topAnchor.constraint(equalTo: documentView.topAnchor).priority(300),
            tableView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            tableView.bottomAnchor.constraint(greaterThanOrEqualTo: documentView.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncPromoDismissed),
            name: SyncPromoManager.SyncPromoManagerNotifications.didDismissPromo,
            object: nil)
    }

    private var shouldShowSyncPromo: Bool {
        return emptyState.isHidden
        && loadingProgressIndicator.isHidden
        && !managementDetailViewModel.isSearching
        && !tableView.isHidden
        && parentFolder == nil
        && (bookmarkManager.list?.totalBookmarks ?? 0) > 0
        && totalRows() > 0
        && syncPromoManager.shouldPresentPromoFor(.bookmarks)
    }

    @objc private func syncPromoDismissed(notification: Notification) {
        updatesyncPromoViewHostingVisibility()
    }

    private func updatesyncPromoViewHostingVisibility() {
        syncPromoViewHostingView.isHidden = !shouldShowSyncPromo
    }

}

#if DEBUG
@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 700, height: 660)) {
    let bkman = {
        let manager = LocalBookmarkManager(
            bookmarkStore: BookmarkStoreMock(
                bookmarks: [
                    BookmarkFolder(id: "1", title: "Folder 1", children: [
                        BookmarkFolder(id: "2", title: "Nested Folder", children: [
                            Bookmark(id: "b1", url: URL.duckDuckGo.absoluteString, title: "DuckDuckGo", isFavorite: false, parentFolderUUID: "2")
                        ])
                    ]),
                    BookmarkFolder(id: "3", title: "Another Folder", children: [
                        BookmarkFolder(id: "4", title: "Nested Folder", children: [
                            BookmarkFolder(id: "5", title: "Another Nested Folder", children: [
                                Bookmark(id: "b2", url: URL.duckDuckGo.absoluteString, title: "DuckDuckGo", isFavorite: false, parentFolderUUID: "5")
                            ])
                        ])
                    ]),
                    Bookmark(id: "b3", url: URL.duckDuckGo.absoluteString, title: "Bookmark 1", isFavorite: false, parentFolderUUID: ""),
                    Bookmark(id: "b4", url: URL.duckDuckGo.absoluteString, title: "Bookmark 2", isFavorite: false, parentFolderUUID: ""),
                    Bookmark(id: "b5", url: URL.duckDuckGo.absoluteString, title: "DuckDuckGo", isFavorite: false, parentFolderUUID: "")
                ]
            ),
            appearancePreferences: .mock
        )
        manager.loadBookmarks()
        customAssertionFailure = { _, _, _ in }

        return manager
    }()

    return BookmarkManagementDetailViewController(bookmarkManager: bkman, dragDropManager: .init(bookmarkManager: bkman))

}
#endif
