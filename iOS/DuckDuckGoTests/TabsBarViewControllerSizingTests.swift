//
//  TabsBarViewControllerSizingTests.swift
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

final class TabsBarViewControllerSizingTests: XCTestCase {

    // Per-tab sizing and add-tab-button placement math now lives in TabsBarLayoutTests; this file
    // covers only the view controller's programmatic hierarchy.

    @MainActor
    func testCreateBuildsProgrammaticHierarchy() {
        let controller = TabsBarViewController.create()

        controller.loadViewIfNeeded()

        XCTAssertNotNil(controller.collectionView)
        XCTAssertNotNil(controller.buttonsBackground)
        XCTAssertNotNil(controller.buttonsStack)
        XCTAssertIdentical(controller.collectionView.delegate, controller)
        XCTAssertIdentical(controller.collectionView.dataSource, controller)
        XCTAssertEqual(controller.buttonsStack.spacing, TabsBarViewController.Constants.stackSpacing)
        XCTAssertEqual(controller.buttonsStack.arrangedSubviews.count, 3)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[0], controller.aiChatChip)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[1], controller.fireButton)
        // addTabButton is positioned manually outside buttonsStack, see recomputeItemSize()/TabsBarLayout.
        XCTAssertFalse(controller.buttonsStack.arrangedSubviews.contains(controller.addTabButton))
        XCTAssertIdentical(controller.addTabButton.superview, controller.view)
    }

    /// The collection view starts one ramp width before the tabs so the first tab's leading fillet
    /// isn't clipped, so both cases check the margin minus that ramp.
    @MainActor
    func testTabStripStartsAtDefaultFirstTabLeadingMargin() {
        let view = TabsBarView()
        view.frame = CGRect(x: 0, y: 0, width: 1024, height: 40)

        view.layoutIfNeeded()

        let expected = TabsBarViewController.Constants.firstTabLeadingMargin - TabsBarViewController.Constants.tabRampSize.width
        XCTAssertEqual(view.collectionView.frame.minX, expected)
    }

    @MainActor
    func testTabStripStartsAfterWindowControlsWhenMarginGrows() {
        let view = TabsBarView()
        view.frame = CGRect(x: 0, y: 0, width: 1024, height: 40)

        view.firstTabLeadingMargin = 96
        view.layoutIfNeeded()

        XCTAssertEqual(view.collectionView.frame.minX, 96 - TabsBarViewController.Constants.tabRampSize.width)
    }

    @MainActor
    func testCollectionViewRegistersTabsBarCell() {
        let controller = TabsBarViewController.create()

        controller.loadViewIfNeeded()

        let cell = controller.collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier,
                                                                 for: IndexPath(item: 0, section: 0))
        XCTAssertTrue(cell is TabsBarCell)
    }
}
