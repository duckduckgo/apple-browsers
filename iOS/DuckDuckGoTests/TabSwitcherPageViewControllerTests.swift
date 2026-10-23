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
}
