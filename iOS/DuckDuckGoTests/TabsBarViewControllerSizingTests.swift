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

    private let accuracy: CGFloat = 0.001
    private let minWidth = TabsBarViewController.Constants.minItemWidth

    private func itemWidth(_ available: CGFloat, _ visibleItems: Int, maxWidth: CGFloat) -> CGFloat {
        TabsBarViewController.itemWidth(availableWidth: available, visibleItems: visibleItems, minWidth: minWidth, maxWidth: maxWidth)
    }

    func testTabsAreCappedAtMaxWidth() {
        XCTAssertEqual(itemWidth(900, 1, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 2, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 3, maxWidth: 300), 300, accuracy: accuracy)
    }

    func testTabsFillEquallyWhenMaxWidthDoesNotBind() {
        XCTAssertEqual(itemWidth(900, 4, maxWidth: 300), 225, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 6, maxWidth: 300), 150, accuracy: accuracy)
    }

    func testTabsFloorAtMinWidth() {
        XCTAssertEqual(itemWidth(900, 8, maxWidth: 300), 120, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 20, maxWidth: 300), 120, accuracy: accuracy)
    }

    func testMinWidthWinsWhenMaxBelowFloor() {
        XCTAssertEqual(itemWidth(300, 1, maxWidth: 99), 120, accuracy: accuracy)
    }

    func testZeroVisibleItemsReturnsZero() {
        XCTAssertEqual(itemWidth(900, 0, maxWidth: 300), 0, accuracy: accuracy)
    }

    private let buttonWidth = TabsBarViewController.Constants.buttonWidth
    private let gap = TabsBarViewController.Constants.addTabButtonGap

    private func addTabButtonLeadingOffset(_ contentWidth: CGFloat, _ availableWidth: CGFloat, isFloored: Bool = false) -> CGFloat {
        TabsBarViewController.addTabButtonLeadingOffset(contentWidth: contentWidth, availableWidth: availableWidth, buttonWidth: buttonWidth, gap: gap, isFloored: isFloored)
    }

    func testAddTabButtonSitsGapAfterLastTabWhenTabsDoNotFillStrip() {
        XCTAssertEqual(addTabButtonLeadingOffset(200, 900), 200 + gap, accuracy: accuracy)
    }

    func testAddTabButtonFollowsContentWidthEvenCloseToAvailableWidthWhenNotFloored() {
        // Capped-but-not-floored tabs can land close to availableWidth (891/900); must still follow
        // contentWidth, not cap early, else the button sits under the last tab's own content.
        XCTAssertEqual(addTabButtonLeadingOffset(891, 900), 891 + gap, accuracy: accuracy)
    }

    func testAddTabButtonFlushWithTrailingEdgeWhenFloored() {
        XCTAssertEqual(addTabButtonLeadingOffset(1500, 900, isFloored: true), 900 - buttonWidth, accuracy: accuracy)
    }

    func testAddTabButtonFlushEvenWhenFlooredContentStillFitsRawStripWidth() {
        // Regression: floored tabs whose contentWidth hasn't yet exceeded raw availableWidth (the gap
        // between the reservation threshold and true overflow) must still cap flush, not overshoot
        // into the fixed icon cluster by following contentWidth + gap.
        XCTAssertEqual(addTabButtonLeadingOffset(870, 900, isFloored: true), 900 - buttonWidth, accuracy: accuracy)
    }

    func testAddTabButtonOffsetIsJustTheGapWithNoTabs() {
        XCTAssertEqual(addTabButtonLeadingOffset(0, 900), gap, accuracy: accuracy)
    }

    func testAddTabButtonOffsetInDegenerateStripNarrowerThanButton() {
        XCTAssertEqual(addTabButtonLeadingOffset(0, 20), gap, accuracy: accuracy)
    }

    func testAddTabButtonOffsetIsZeroWhenAvailableWidthIsZero() {
        XCTAssertEqual(addTabButtonLeadingOffset(200, 0), 0, accuracy: accuracy)
    }

    func testTabStripFlooredWhenItemWidthAtMinimum() {
        XCTAssertTrue(TabsBarViewController.isTabStripFloored(itemWidth: minWidth, minWidth: minWidth))
    }

    func testTabStripNotFlooredWhenItemWidthAboveMinimum() {
        XCTAssertFalse(TabsBarViewController.isTabStripFloored(itemWidth: minWidth + 1, minWidth: minWidth))
    }

    func testTabStripNotFlooredWhenItemWidthIsZero() {
        XCTAssertFalse(TabsBarViewController.isTabStripFloored(itemWidth: 0, minWidth: minWidth))
    }

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
        // addTabButton is positioned manually outside buttonsStack, see updateAddTabButtonPosition().
        XCTAssertFalse(controller.buttonsStack.arrangedSubviews.contains(controller.addTabButton))
        XCTAssertIdentical(controller.addTabButton.superview, controller.view)
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
