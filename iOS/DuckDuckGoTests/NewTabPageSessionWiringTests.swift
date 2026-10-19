//
//  NewTabPageSessionWiringTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Bookmarks
import Testing
import UIKit
@testable import DuckDuckGo

@Suite("New Tab Page session wiring")
@MainActor
struct NewTabPageSessionWiringTests {

    // MARK: - Page design

    @available(iOS 16, macOS 13, *)
    @Test("The redesigned page reports the redesign", .timeLimit(.minutes(1)))
    func redesignedPageReportsRedesign() {
        let page = RedesignedNewTabPageViewController(blocks: [])

        #expect(NewTabPageSessionWideEventData.PageDesign(of: page) == .redesign)
    }

    // MARK: - Redesigned page

    @available(iOS 16, macOS 13, *)
    @Test("Dragging the redesigned page reports a scroll", .timeLimit(.minutes(1)))
    func draggingRedesignedPageReportsScroll() {
        let page = RedesignedNewTabPageViewController(blocks: [])
        let delegate = NewTabPageDelegateSpy()
        page.delegate = delegate
        page.loadViewIfNeeded()

        page.scrollViewWillBeginDragging(UIScrollView())

        #expect(delegate.scrollCount == 1)
    }

    // MARK: - Sheets

    @available(iOS 16, macOS 13, *)
    @Test("Closing the customization sheet reports its dismissal", .timeLimit(.minutes(1)))
    func closingCustomizationSheetReportsDismissal() async throws {
        let host = try SheetHost()
        defer { host.tearDown() }
        let sheet = NewTabPageCustomizationViewController(model: makeCustomizationModel())
        var dismissalCount = 0
        sheet.onDismissed = { dismissalCount += 1 }

        await host.present(sheet)
        #expect(dismissalCount == 0)
        await host.dismiss(sheet)

        #expect(dismissalCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the Add Favorite sheet reports its dismissal", .timeLimit(.minutes(1)))
    func closingAddFavoriteSheetReportsDismissal() async throws {
        let host = try SheetHost()
        defer { host.tearDown() }
        let sheet = AddFavoriteViewController(model: AddFavoriteViewModel(bookmarks: BookmarksStub()))
        var dismissalCount = 0
        sheet.onDismissed = { dismissalCount += 1 }

        await host.present(sheet)
        #expect(dismissalCount == 0)
        await host.dismiss(sheet)

        #expect(dismissalCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Covering a sheet with another screen does not report its dismissal", .timeLimit(.minutes(1)))
    func coveringSheetDoesNotReportDismissal() async throws {
        let host = try SheetHost()
        defer { host.tearDown() }
        let sheet = NewTabPageCustomizationViewController(model: makeCustomizationModel())
        var dismissalCount = 0
        sheet.onDismissed = { dismissalCount += 1 }
        await host.present(sheet)

        await withCheckedContinuation { continuation in
            sheet.present(UIViewController(), animated: false) { continuation.resume() }
        }

        #expect(dismissalCount == 0)
    }

    private func makeCustomizationModel() -> NewTabPageCustomizationModel {
        NewTabPageCustomizationModel(persistor: CustomizationPersistorStub(), pixelFiring: nil)
    }
}

/// Hosts presented sheets in a visible window so UIKit runs their appearance callbacks.
@MainActor
private final class SheetHost {

    private let window: UIWindow
    private let root = UIViewController()
    private let originalKeyWindow = UIApplication.shared.firstKeyWindow

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
    }

    func present(_ sheet: UIViewController) async {
        await withCheckedContinuation { continuation in
            root.present(sheet, animated: false) { continuation.resume() }
        }
    }

    func dismiss(_ sheet: UIViewController) async {
        await withCheckedContinuation { continuation in
            sheet.dismiss(animated: false) { continuation.resume() }
        }
    }

    func tearDown() {
        root.dismiss(animated: false)
        window.isHidden = true
        originalKeyWindow?.makeKey()
    }
}

private final class NewTabPageDelegateSpy: NewTabPageControllerDelegate {

    private(set) var scrollCount = 0

    func newTabPageDidScroll(_ controller: any NewTabPage) {
        scrollCount += 1
    }

    func newTabPageDidSelectFavorite(_ controller: any NewTabPage, favorite: BookmarkEntity) { }
    func newTabPageDidEditFavorite(_ controller: any NewTabPage, favorite: BookmarkEntity) { }
    func newTabPageDidRequestFaviconsFetcherOnboarding(_ controller: any NewTabPage) { }
    func newTabPageDidRequestSwitchToTab(_ controller: any NewTabPage, tab: Tab) { }
    func newTabPageDidRequestTabSwitcher(_ controller: any NewTabPage) { }
}

private final class CustomizationPersistorStub: NewTabPageCustomizationPersisting {
    var isFavoritesSectionVisible = true
    var isMessagesSectionVisible = true
}

private final class BookmarksStub: MenuBookmarksInteracting {
    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)

    func createOrToggleFavorite(title: String, url: URL) { }
    func saveFavorite(title: String?, urlString: String) -> Bool { false }
    func createBookmark(title: String, url: URL) { }
    func favorite(for url: URL) -> BookmarkEntity? { nil }
    func bookmark(for url: URL) -> BookmarkEntity? { nil }
}
