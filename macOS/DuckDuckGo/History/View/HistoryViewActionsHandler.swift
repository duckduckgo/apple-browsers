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
import PrivacyConfig
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
    private let fireCoordinator: FireCoordinator
    private let featureFlagger: FeatureFlagger

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
    private let pasteboard: NSPasteboard

    init(
        dataProvider: HistoryViewDataProviding,
        dialogPresenter: HistoryViewDialogPresenting = DefaultHistoryViewDialogPresenter(),
        tabOpener: HistoryViewTabOpening = DefaultHistoryViewTabOpener(),
        bookmarksHandler: HistoryViewBookmarksHandling,
        fireCoordinator: FireCoordinator = Application.appDelegate.fireCoordinator,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
        firePixel: @escaping (HistoryViewPixel, PixelKit.Frequency) -> Void = { PixelKit.fire($0, frequency: $1) },
        pasteboard: NSPasteboard = .general
    ) {
        self.dataProvider = dataProvider
        self.dialogPresenter = dialogPresenter
        self.tabOpener = tabOpener
        self.tabOpener.dialogPresenter = dialogPresenter
        self.bookmarksHandler = bookmarksHandler
        self.fireCoordinator = fireCoordinator
        self.featureFlagger = featureFlagger
        self.firePixel = firePixel
        self.pasteboard = pasteboard
    }

    func showDeleteDialog(for query: DataModel.HistoryQueryKind, in window: NSWindow?) async -> DataModel.DeleteDialogResponse {
        guard let dataProvider, !query.shouldSkipDeleteDialog else {
            return .noAction
        }

        // Load visits matching the query
        let scopeVisits = await dataProvider.visits(matching: query)
        guard !scopeVisits.isEmpty else { return .noAction }

        // Adjust query when not a range filter and matches all items
        let adjustedQuery: DataModel.HistoryQueryKind = await {
            switch query {
            case .rangeFilter, .dateFilter, .visits:
                return query
            default:
                let allVisitsCount = await dataProvider.visits(matching: .rangeFilter(.all)).count
                return allVisitsCount == scopeVisits.count ? .rangeFilter(.all) : query
            }
        }()

        let result = await dialogPresenter.showDeleteDialog(for: adjustedQuery, visits: scopeVisits, in: window)

        let pixelScope = HistoryViewPixel.DeletedBatchKind(adjustedQuery)
        switch result {
        case .burn(let burnChats):
            // FireCoordinator handles the result of the new Fire Dialog
            if featureFlagger.isFeatureOn(.fireDialog) {
                await dataProvider.refreshData()
            } else {
                await dataProvider.burnVisits(matching: adjustedQuery, and: burnChats)
            }
            self.firePixel(.delete, .daily)
            self.firePixel(.multipleItemsDeleted(pixelScope, burn: true), .dailyAndStandard)
        case .delete(let deleteChats):
            // FireCoordinator handles the result of the new Fire Dialog
            if featureFlagger.isFeatureOn(.fireDialog) {
                await dataProvider.refreshData()
            } else {
                await dataProvider.deleteVisits(matching: adjustedQuery, and: deleteChats)
            }
            self.firePixel(.delete, .daily)
            self.firePixel(.multipleItemsDeleted(pixelScope, burn: false), .dailyAndStandard)
        case .noAction: break
        }
        return mapDialogResponse(result)
    }

    func showDeleteDialog(for entries: [String], in window: NSWindow?) async -> DataModel.DeleteDialogResponse {
        // If entries represent site selections (e.g., "site:example.com"),
        // mirror the context menu behavior and present the Fire dialog for sites.
        let siteDomains = extractSiteDomains(from: entries)

        if !siteDomains.isEmpty {
            return await showDeleteDialog(for: .domainFilter(Set(siteDomains)), in: window)
        }

        return await showDeleteDialog(for: entries.compactMap(VisitIdentifier.init), in: window)
    }

    @MainActor
    private func deleteDomains(_ domains: Set<String>, window: NSWindow?) {
        deleteDialogTask = Task { @MainActor in
            await showDeleteDialog(for: .domainFilter(domains), in: window)
        }
    }

    @MainActor
    func showContextMenu(for entries: [String], using presenter: any ContextMenuPresenting) async -> DataModel.DeleteDialogResponse {
        // Reset context menu response every time before showing a context menu.
        // Context menu actions may udpate the response before it's returned.
        contextMenuResponse = .noAction

        let identifiers = entries.compactMap(VisitIdentifier.init)
        let siteDomains = extractSiteDomains(from: entries)

        // Unify sites vs identifiers: compute selection kind and build a single menu differing only by delete item
        let isSiteSelection = identifiers.isEmpty && !siteDomains.isEmpty

        // Resolve URLs and delete behavior
        let urls: [URL]
        let deleteTitle: String
        let performDelete: () -> Void

        if isSiteSelection {
            urls = siteDomains.compactMap { dataProvider?.preferredURL(forSiteDomain: $0) }
            deleteTitle = UserText.deleteHistoryAndBrowsingDataMenuItem
            performDelete = { [weak self] in self?.deleteDomains(Set(siteDomains), window: presenter.window) }
        } else {
            guard !identifiers.isEmpty else { return .noAction }
            urls = identifiers.compactMap(\.url.url)
            deleteTitle = UserText.delete
            performDelete = { [weak self] in self?.delete(identifiers, window: presenter.window) }
        }

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

            if isSiteSelection || urls.count == 1 {
                NSMenuItem(title: UserText.showAllHistoryFromThisSite) { [weak self] _ in
                    self?.showAllHistoryFromThisSite()
                }
                .withAccessibilityIdentifier("HistoryView.showAllHistoryFromThisSite")

                NSMenuItem.separator()
            }

            if urls.count == 1, let url = urls.first {
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
            NSMenuItem(title: deleteTitle) { _ in
                performDelete()
            }
            .withAccessibilityIdentifier("HistoryView.delete")
        }

        presenter.showContextMenu(menu)

        // Await potential delete dialog result before returning
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
        pasteboard.copy(url)
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
            await dataProvider.deleteVisits(matching: .visits(identifiers))
            firePixel(.delete, .daily)
            firePixel(.singleItemDeleted, .dailyAndStandard)
            return .delete
        }

        return await showDeleteDialog(for: .visits(identifiers), in: window)
    }

    private func mapDialogResponse(_ response: HistoryViewDeleteDialogModel.Response) -> DataModel.DeleteDialogResponse {
        switch response {
        case .noAction:
            return .noAction
        case .delete, .burn:
            return .delete
        }
    }

    private func extractSiteDomains(from entries: [String]) -> [String] {
        entries.compactMap { entry in
            guard entry.hasPrefix("site:"), let idx = entry.firstIndex(of: ":") else { return nil }
            let domain = entry[entry.index(after: idx)...]
            return domain.isEmpty ? nil : String(domain)
        }
    }
}

extension DataModel.HistoryQueryKind {
    var deleteMode: HistoryViewDeleteDialogModel.DeleteMode {
        switch self {
        case .rangeFilter(.all),
             .rangeFilter(.allSites):
            return .all
        case .rangeFilter(.today):
            return .today
        case .rangeFilter(.yesterday):
            return .yesterday
        case .rangeFilter(.older):
            return .older
        case .rangeFilter(.sunday),
             .rangeFilter(.monday),
             .rangeFilter(.tuesday),
             .rangeFilter(.wednesday),
             .rangeFilter(.thursday),
             .rangeFilter(.friday),
             .rangeFilter(.saturday):
            guard let date = historyRange?.date(for: Date()) else {
                assertionFailure("Daily history range must always compute a valid date")
                return .unspecified
            }
            return .date(date)

        case .dateFilter(let date):
            return .date(date)
        case .domainFilter(let domains):
            return .sites(domains)
        case .searchTerm, .visits:
            return .unspecified
        }
    }

    var shouldSkipDeleteDialog: Bool {
        switch self {
        case .searchTerm(let term):
            return term.isEmpty
        case .domainFilter(let domains):
            return domains.isEmpty
        case .visits(let visits):
            return visits.isEmpty
        case .rangeFilter, .dateFilter:
            return false
        }
    }
}
