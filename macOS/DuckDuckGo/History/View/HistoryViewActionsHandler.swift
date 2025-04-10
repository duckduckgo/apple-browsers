//
//  HistoryViewActionsHandler.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import HistoryView
import PixelKit
import SwiftUIExtensions

protocol HistoryViewBookmarksHandling: AnyObject {
    func isUrlBookmarked(url: URL) -> Bool
    func isUrlFavorited(url: URL) -> Bool
    func getBookmark(for url: URL) -> Bookmark?
    func markAsFavorite(_ bookmark: Bookmark)
    func addNewBookmarks(for websiteInfos: [WebsiteInfo])
    func addNewFavorite(for url: URL, title: String)
}

extension LocalBookmarkManager: HistoryViewBookmarksHandling {
    func addNewBookmarks(for websiteInfos: [WebsiteInfo]) {
        makeBookmarks(for: websiteInfos, inNewFolderNamed: nil, withinParentFolder: .root)
    }

    func addNewFavorite(for url: URL, title: String) {
        makeBookmark(for: url, title: title, isFavorite: true)
    }
}

final class HistoryViewActionsHandler: HistoryView.ActionsHandling {

    weak var dataProvider: HistoryViewDataProviding?
    private let bookmarksHandler: HistoryViewBookmarksHandling
    private let tabOpener: HistoryViewTabOpening
    private let dialogPresenter: HistoryViewDialogPresenting

    /**
     * A handle to the context menu response. This is returned to FE from `showContextMenu(for:using:)`.
     *
     * Context menu response is a local variable because it may be modified by context
     * menu actions. The action handlers are Objective-C selectors and we can't easily
     * pass the response to action handlers - hence a local variable.
     */
    private var contextMenuResponse: DataModel.DeleteDialogResponse = .noAction

    /**
     * This is a handle to a Task that calls `showDeleteDialog` in response to a context menu 'Delete' action.
     *
     * `showContextMenu` function is expected to return a value indicating whether some items have been deleted
     * as a result of showing it. Deleting multiple items via context menu requires that the user confirms a delete dialog.
     * So the flow is:
     * 1. `showContextMenu` called
     * 2. context menu shown
     * 3. delete action triggered
     * 4. delete dialog shown and accepted
     * 5. deleting data
     * 6. return from the function
     * Context menu itself blocks main thread, but once 'Delete' action is selected, the context menu stops blocking the thread
     * and would return from the function. In order to wait for the dialog, we're showing that dialog in an async @MainActor Task
     * and then at the bottom of `showContextMenu` function we're awaiting that task (if it's not nil).
     *
     * This ensures that the dialog response is returned form the `showContextMenu` function.
     */
    private var deleteDialogTask: Task<DataModel.DeleteDialogResponse, Never>?
    private var firePixel: (HistoryViewPixel, PixelKit.Frequency) -> Void

    init(
        dataProvider: HistoryViewDataProviding,
        dialogPresenter: HistoryViewDialogPresenting = DefaultHistoryViewDialogPresenter(),
        tabOpener: HistoryViewTabOpening = DefaultHistoryViewTabOpener(),
        bookmarksHandler: HistoryViewBookmarksHandling = LocalBookmarkManager.shared,
        firePixel: @escaping (HistoryViewPixel, PixelKit.Frequency) -> Void = { PixelKit.fire($0, frequency: $1) }
    ) {
        self.dataProvider = dataProvider
        self.dialogPresenter = dialogPresenter
        self.tabOpener = tabOpener
        self.tabOpener.dialogPresenter = dialogPresenter
        self.bookmarksHandler = bookmarksHandler
        self.firePixel = firePixel
    }

    func showDeleteDialog(for query: DataModel.HistoryQueryKind, in window: NSWindow?) async -> DataModel.DeleteDialogResponse {
        guard let dataProvider, !query.shouldSkipDeleteDialog else {
            return .noAction
        }

        let visitsCount = await dataProvider.countVisibleVisits(matching: query)
        guard visitsCount > 0 else {
            return .noAction
        }

        let adjustedQuery: DataModel.HistoryQueryKind = await {
            switch query {
            case .rangeFilter:
                return query
            default:
                let allVisitsCount = await dataProvider.countVisibleVisits(matching: .rangeFilter(.all))
                return allVisitsCount == visitsCount ? .rangeFilter(.all) : query
            }
        }()

        switch await dialogPresenter.showDeleteDialog(for: visitsCount, deleteMode: adjustedQuery.deleteMode, in: window) {
        case .burn:
            await dataProvider.burnVisits(matching: adjustedQuery)
            firePixel(.delete, .daily)
            firePixel(.multipleItemsDeleted(.init(adjustedQuery), burn: true), .dailyAndStandard)
            return .delete
        case .delete:
            await dataProvider.deleteVisits(matching: adjustedQuery)
            firePixel(.delete, .daily)
            firePixel(.multipleItemsDeleted(.init(adjustedQuery), burn: false), .dailyAndStandard)
            return .delete
        default:
            return .noAction
        }
    }

    func showDeleteDialog(for entries: [String], in window: NSWindow?) async -> DataModel.DeleteDialogResponse {
        await showDeleteDialog(for: entries.compactMap(VisitIdentifier.init), in: window)
    }

    @MainActor
    func showContextMenu(for entries: [String], using presenter: any ContextMenuPresenting) async -> DataModel.DeleteDialogResponse {
        // Reset context menu response every time before showing a context menu.
        // Context menu actions may udpate the response before it's returned.
        contextMenuResponse = .noAction

        let identifiers = entries.compactMap(VisitIdentifier.init)
        guard !identifiers.isEmpty else {
            return .noAction
        }

        let urls = identifiers.map(\.url)
        let menu = NSMenu {
            NSMenuItem(title: urls.count == 1 ? UserText.openInNewTab : UserText.openAllInNewTabs) { [weak self] _ in
                self?.openInNewTab(urls, window: presenter.window)
            }
            .withAccessibilityIdentifier("HistoryView.openInNewTab")

            NSMenuItem(title: urls.count == 1 ? UserText.openInNewWindow : UserText.openAllTabsInNewWindow) { [weak self] _ in
                self?.openInNewWindow(urls, window: presenter.window)
            }
            .withAccessibilityIdentifier("HistoryView.openInNewWindow")

            NSMenuItem(title: urls.count == 1 ? UserText.openInNewFireWindow : UserText.openAllInNewFireWindow) { [weak self] _ in
                self?.openInNewFireWindow(urls, window: presenter.window)
            }
            .withAccessibilityIdentifier("HistoryView.openInNewFireWindow")

            NSMenuItem.separator()

            if urls.count == 1, let url = urls.first {
                NSMenuItem(title: UserText.showAllHistoryFromThisSite) { [weak self] _ in
                    self?.showAllHistoryFromThisSite()
                }
                .withAccessibilityIdentifier("HistoryView.showAllHistoryFromThisSite")
                NSMenuItem.separator()
                NSMenuItem(title: UserText.copyLink, action: #selector(copy(_:)), target: self, representedObject: url)
                    .withAccessibilityIdentifier("HistoryView.copyLink")
                if !bookmarksHandler.isUrlBookmarked(url: url) {
                    NSMenuItem(title: UserText.addToBookmarks) { [weak self] _ in
                        self?.addBookmarks(for: [url])
                    }
                    .withAccessibilityIdentifier("HistoryView.addBookmark")
                }
                if !bookmarksHandler.isUrlFavorited(url: url) {
                    NSMenuItem(title: UserText.addToFavorites) { [weak self] _ in
                        self?.addFavorite(for: url)
                    }
                    .withAccessibilityIdentifier("HistoryView.addFavorite")
                }
            } else if urls.contains(where: { !bookmarksHandler.isUrlBookmarked(url: $0) }) {
                NSMenuItem(title: UserText.addAllToBookmarks) { [weak self] _ in
                    self?.addBookmarks(for: urls)
                }
                .withAccessibilityIdentifier("HistoryView.addBookmark")
            }

            NSMenuItem.separator()
            NSMenuItem(title: UserText.delete) { [weak self] _ in
                self?.delete(identifiers, window: presenter.window)
            }
            .withAccessibilityIdentifier("HistoryView.delete")
        }

        presenter.showContextMenu(menu)

        // If 'Delete' action was selected and it displayed a dialog, await the response from that dialog before continuing.
        if let deleteDialogResponse = await deleteDialogTask?.value {
            deleteDialogTask = nil
            contextMenuResponse = deleteDialogResponse
        }
        return contextMenuResponse
    }

    func open(_ url: URL, window: NSWindow?) async {
        firePixel(.itemOpened(.single), .dailyAndStandard)
        await tabOpener.open(url, window: window)
    }

    private func openInNewTab(_ urls: [URL], window: NSWindow?) {
        Task {
            fireItemOpenedPixel(urls)
            await tabOpener.openInNewTab(urls, sourceWindow: window)
        }
    }

    private func openInNewWindow(_ urls: [URL], window: NSWindow?) {
        Task {
            fireItemOpenedPixel(urls)
            await tabOpener.openInNewWindow(urls, sourceWindow: window)
        }
    }

    private func openInNewFireWindow(_ urls: [URL], window: NSWindow?) {
        Task {
            fireItemOpenedPixel(urls)
            await tabOpener.openInNewFireWindow(urls, sourceWindow: window)
        }
    }

    private func fireItemOpenedPixel(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        firePixel(.itemOpened(urls.count == 1 ? .single : .multiple), .dailyAndStandard)
    }

    @MainActor
    @objc private func copy(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        NSPasteboard.general.copy(url)
    }

    @MainActor
    private func addBookmarks(for urls: [URL]) {
        guard let dataProvider else { return }

        let titles = dataProvider.titles(for: urls)
        let websiteInfos = urls.map { WebsiteInfo(url: $0, title: titles[$0]) }
        bookmarksHandler.addNewBookmarks(for: websiteInfos)
    }

    @MainActor
    private func addFavorite(for url: URL) {
        guard let dataProvider else { return }
        let titles = dataProvider.titles(for: [url])
        if let bookmark = bookmarksHandler.getBookmark(for: url) {
            bookmarksHandler.markAsFavorite(bookmark)
        } else {
            bookmarksHandler.addNewFavorite(for: url, title: titles[url] ?? url.absoluteString)
        }
    }

    @MainActor
    private func showAllHistoryFromThisSite() {
        contextMenuResponse = .domainSearch
    }

    @MainActor
    private func delete(_ identifiers: [VisitIdentifier], window: NSWindow?) {
        deleteDialogTask = Task { @MainActor in
            await showDeleteDialog(for: identifiers, in: window)
        }
    }

    @MainActor
    private func showDeleteDialog(for identifiers: [VisitIdentifier], in window: NSWindow?) async -> DataModel.DeleteDialogResponse {
        guard let dataProvider, identifiers.count > 0 else {
            return .noAction
        }

        guard identifiers.count > 1 else {
            await dataProvider.deleteVisits(for: identifiers)
            firePixel(.delete, .daily)
            firePixel(.singleItemDeleted, .dailyAndStandard)
            return .delete
        }

        let visitsCount = identifiers.count

        switch await dialogPresenter.showDeleteDialog(for: visitsCount, deleteMode: .unspecified, in: window) {
        case .burn:
            await dataProvider.burnVisits(for: identifiers)
            firePixel(.delete, .daily)
            firePixel(.multipleItemsDeleted(.multiSelect, burn: true), .dailyAndStandard)
            return .delete
        case .delete:
            await dataProvider.deleteVisits(for: identifiers)
            firePixel(.delete, .daily)
            firePixel(.multipleItemsDeleted(.multiSelect, burn: false), .dailyAndStandard)
            return .delete
        default:
            return .noAction
        }
    }
}

extension DataModel.HistoryQueryKind {
    var deleteMode: HistoryViewDeleteDialogModel.DeleteMode {
        guard case let .rangeFilter(range) = self else {
            return .unspecified
        }

        switch range {
        case .all:
            return .all
        case .today:
            return .today
        case .yesterday:
            return .yesterday
        case .older:
            return .unspecified
        default:
            guard let date = range.date(for: Date()) else {
                return .unspecified
            }
            return .date(date)
        }
    }

    var shouldSkipDeleteDialog: Bool {
        switch self {
        case .searchTerm(let term), .domainFilter(let term):
            return term.isEmpty
        case .rangeFilter:
            return false
        }
    }
}
