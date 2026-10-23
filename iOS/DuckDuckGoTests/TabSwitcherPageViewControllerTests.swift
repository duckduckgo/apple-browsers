//
//  TabSwitcherPageViewControllerTests.swift
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

import XCTest
import UIKit
@testable import DuckDuckGo

@MainActor
final class TabSwitcherPageViewControllerTests: XCTestCase {

    private final class Settings: TabSwitcherSettings {
        var isGridViewEnabled = true
        var hasSeenNewLayout = false
        var showTrackerCountInTabSwitcher = false
        var lastTrackerCountInTabSwitcher: Int64?
    }

    private func makePage(tabs: [Tab] = [],
                          mode: BrowsingMode = .fire,
                          settings: TabSwitcherSettings = Settings()) -> TabSwitcherPageViewController {
        let page = TabSwitcherPageViewController(
            browsingMode: mode,
            tabsModel: TabsModel(tabs: tabs, desktop: false, mode: mode),
            previewsSource: MockTabPreviewsSource(),
            tabSwitcherSettings: settings,
            trackerCountViewModel: nil,
            isFireModeEnabled: true,
            isFloatingTabSwitcherEnabled: true,
            duckAIGridContentProvider: nil,
            duckAIVoiceSessionTracker: nil)
        page.loadViewIfNeeded()
        return page
    }

    func testEmptyFirePageDefersEmptyStateUntilPreparedForDisplay() throws {
        let page = makePage()
        page.updateEmptyStateVisibility()
        XCTAssertTrue(page.children.isEmpty)

        page.prepareForDisplay()

        let emptyState = try XCTUnwrap(page.children.first)
        XCTAssertEqual(page.children.count, 1)
        XCTAssertFalse(emptyState.view.isHidden)
        XCTAssertTrue(page.collectionView.isHidden)
    }

    func testRepeatedPreparationReusesEmptyState() throws {
        let page = makePage()
        page.prepareForDisplay()
        let emptyState = try XCTUnwrap(page.children.first)

        page.prepareForDisplay()
        page.updateEmptyStateVisibility()

        XCTAssertEqual(page.children.count, 1)
        XCTAssertTrue(page.children.first === emptyState)
    }

    func testNonemptyFirePageDoesNotBuildEmptyState() {
        let page = makePage(tabs: [Tab(fireTab: true)])

        page.prepareForDisplay()

        XCTAssertTrue(page.children.isEmpty)
        XCTAssertFalse(page.collectionView.isHidden)
    }

    func testDeletingLastFireTabBuildsEmptyStateAfterPreparation() throws {
        let tab = Tab(fireTab: true)
        let page = makePage(tabs: [tab])
        page.prepareForDisplay()
        XCTAssertTrue(page.children.isEmpty)

        page.tabsModel.remove(tab: tab)
        page.reloadData()

        let emptyState = try XCTUnwrap(page.children.first)
        XCTAssertFalse(emptyState.view.isHidden)
        XCTAssertTrue(page.collectionView.isHidden)
    }

    func testAddingFireTabHidesExistingEmptyState() throws {
        let page = makePage()
        page.prepareForDisplay()
        let emptyState = try XCTUnwrap(page.children.first)

        page.tabsModel.insert(tab: Tab(fireTab: true), placement: .atEnd, selectNewTab: true)
        page.reloadData()

        XCTAssertTrue(emptyState.view.isHidden)
        XCTAssertFalse(page.collectionView.isHidden)
        XCTAssertEqual(page.children.count, 1)
    }

    func testDeferredEmptyStateUsesLatestFloatingClearance() throws {
        let page = makePage()
        page.applyFloatingTopClearance(100)

        page.prepareForDisplay()

        let emptyState = try XCTUnwrap(page.children.first)
        let topConstraint = try XCTUnwrap(page.view.constraints.first {
            $0.firstItem === emptyState.view && $0.firstAttribute == .top
        })
        XCTAssertEqual(topConstraint.constant, 110)
        page.applyFloatingTopClearance(120)
        XCTAssertEqual(topConstraint.constant, 130)
    }

    func testNormalPageDoesNotBuildFireEmptyState() {
        let page = makePage(mode: .normal)

        page.prepareForDisplay()

        XCTAssertTrue(page.children.isEmpty)
        XCTAssertFalse(page.collectionView.isHidden)
    }

    func testCollectionLayoutTracksPageSizeInGridAndList() throws {
        for isGrid in [true, false] {
            let settings = Settings()
            settings.isGridViewEnabled = isGrid
            let page = makePage(mode: .normal, settings: settings)
            page.prepareForDisplay()

            let sizes = [CGSize(width: 390, height: 844), CGSize(width: 390, height: 350),
                         CGSize(width: 780, height: 350), CGSize(width: 390, height: 844)]
            for size in sizes {
                page.view.frame = CGRect(origin: .zero, size: size)
                page.view.layoutIfNeeded()
                let indexPath = IndexPath(row: 0, section: 0)
                let attributes = try XCTUnwrap(page.collectionView.layoutAttributesForItem(at: indexPath))
                let expectedSize = page.collectionView(page.collectionView,
                                                       layout: page.collectionView.collectionViewLayout,
                                                       sizeForItemAt: indexPath)
                XCTAssertEqual(attributes.size, expectedSize)
            }
        }
    }

    func testReorderingPreservesSelectedTabAndNotifiesAfterDropAnimation() throws {
        for isEditing in [false, true] {
            let tabs = (0..<3).map { _ in Tab(fireTab: true) }
            let page = makePage(tabs: tabs)
            let selectedTab = tabs[isEditing ? 1 : 0]
            page.tabsModel.select(tab: selectedTab)
            page.currentSelection = page.tabsModel.currentIndex
            page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            page.view.layoutIfNeeded()
            let delegate = ReorderDelegate(isEditing: isEditing)
            page.pageDelegate = delegate
            let source = IndexPath(item: 0, section: 0)
            let destination = IndexPath(item: 2, section: 0)
            let drop = Drop(source: source, destination: destination)
            let expectedOrder = [tabs[1].uid, tabs[2].uid, tabs[0].uid]
            var reorderCount = 0
            delegate.onReorder = {
                reorderCount += 1
                XCTAssertEqual(page.tabsModel.tabs.map(\.uid), expectedOrder)
                XCTAssertIdentical(page.selectedTab, selectedTab)
            }

            UIView.performWithoutAnimation {
                page.collectionView(page.collectionView, performDropWith: drop)
            }

            XCTAssertEqual(page.tabsModel.tabs.map(\.uid), expectedOrder)
            XCTAssertIdentical(page.tabsModel.currentTab, selectedTab)
            XCTAssertIdentical(page.selectedTab, selectedTab)
            XCTAssertEqual(reorderCount, 0)
            XCTAssertEqual(drop.droppedAt, destination)
            let completion = try XCTUnwrap(drop.completion)

            completion(.end)

            XCTAssertEqual(reorderCount, 1)
            if isEditing {
                XCTAssertEqual(page.selectedIndexPaths, [destination])
            }
        }
    }

    private final class ReorderDelegate: TabSwitcherPageDelegate {
        let isEditing: Bool
        var isProcessingUpdates = false
        var canDismissOnEmpty = true
        var onReorder: (() -> Void)?

        init(isEditing: Bool) {
            self.isEditing = isEditing
        }

        func page(_ page: TabSwitcherPageViewController, didReorderTabs: Void) { onReorder?() }
        func page(_ page: TabSwitcherPageViewController, didSelectTabAt index: Int) {}
        func page(_ page: TabSwitcherPageViewController, didDeselectTab: Void) {}
        func page(_ page: TabSwitcherPageViewController, willDeleteTabs tabs: [Tab], allDeleted: Bool) {}
        func pageDidDeleteTabs(_ page: TabSwitcherPageViewController, allDeleted: Bool) {}
        func page(_ page: TabSwitcherPageViewController, contextMenuForTabsAt indexPaths: [IndexPath]) -> UIMenu? { nil }
        func pageDidRequestDismiss(_ page: TabSwitcherPageViewController) {}
        func pageCellDidBeginSwipe(_ page: TabSwitcherPageViewController) {}
        func pageCellDidEndSwipe(_ page: TabSwitcherPageViewController) {}
        func pageCellDidBeginDrag(_ page: TabSwitcherPageViewController) {}
        func pageCellDidEndDrag(_ page: TabSwitcherPageViewController) {}
    }

    private final class Drop: NSObject, UICollectionViewDropCoordinator, UICollectionViewDropItem, UIDragAnimating {
        var items: [UICollectionViewDropItem] { [self] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        let sourceIndexPath: IndexPath?
        let destinationIndexPath: IndexPath?
        let previewSize = CGSize(width: 120, height: 40)
        let proposal = UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        var completion: ((UIViewAnimatingPosition) -> Void)?
        var droppedAt: IndexPath?
        var session: UIDropSession { fatalError("The page does not access the drop session") }

        init(source: IndexPath, destination: IndexPath) {
            sourceIndexPath = source
            destinationIndexPath = destination
        }

        func addAnimations(_ animations: @escaping () -> Void) { animations() }
        func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) { self.completion = completion }
        func drop(_ dragItem: UIDragItem, toItemAt indexPath: IndexPath) -> UIDragAnimating {
            droppedAt = indexPath
            return self
        }
        func drop(_ dragItem: UIDragItem, intoItemAt indexPath: IndexPath, rect: CGRect) -> UIDragAnimating {
            fatalError("The page does not drop into an item")
        }
        func drop(_ dragItem: UIDragItem, to target: UIDragPreviewTarget) -> UIDragAnimating {
            fatalError("The page does not use a preview target")
        }
        func drop(_ dragItem: UIDragItem, to placeholder: UICollectionViewDropPlaceholder) -> UICollectionViewDropPlaceholderContext {
            fatalError("The page does not use placeholder drops")
        }
    }
}
