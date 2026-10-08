//
//  TabsBarLayoutTests.swift
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

import UIKit
import XCTest
@testable import DuckDuckGo

final class TabsBarLayoutTests: XCTestCase {

    private let accuracy: CGFloat = 0.001
    private let buttonWidth: CGFloat = 44
    private let gap: CGFloat = 6
    private let minWidth: CGFloat = 120

    private func layout(stripWidth: CGFloat, tabsCount: Int, maxWidth: CGFloat) -> TabsBarLayout {
        TabsBarLayout(stripWidth: stripWidth, tabsCount: tabsCount, minItemWidth: minWidth, maxItemWidth: maxWidth,
                      buttonWidth: buttonWidth, buttonGap: gap)
    }

    // MARK: - itemWidth (equal-division / cap / floor)

    func testItemWidthCappedAtMaxWidth() {
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 1, minWidth: minWidth, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 2, minWidth: minWidth, maxWidth: 300), 300, accuracy: accuracy)
    }

    func testItemWidthFillsEquallyWhenMaxWidthDoesNotBind() {
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 4, minWidth: minWidth, maxWidth: 300), 225, accuracy: accuracy)
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 6, minWidth: minWidth, maxWidth: 300), 150, accuracy: accuracy)
    }

    func testItemWidthFloorsAtMinWidth() {
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 8, minWidth: minWidth, maxWidth: 300), 120, accuracy: accuracy)
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 20, minWidth: minWidth, maxWidth: 300), 120, accuracy: accuracy)
    }

    func testItemWidthMinWidthWinsWhenMaxBelowFloor() {
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 300, visibleItems: 1, minWidth: minWidth, maxWidth: 99), 120, accuracy: accuracy)
    }

    func testItemWidthZeroVisibleItemsReturnsZero() {
        XCTAssertEqual(TabsBarLayout.itemWidth(availableWidth: 900, visibleItems: 0, minWidth: minWidth, maxWidth: 300), 0, accuracy: accuracy)
    }

    // MARK: - Full layout, not floored (equal-division/capped regimes are always safe by construction)

    func testFewTabsSitInlineWithGapAfterLastTab() {
        let result = layout(stripWidth: 900, tabsCount: 1, maxWidth: 300)
        XCTAssertFalse(result.isFloored)
        XCTAssertEqual(result.addTabButtonLeadingOffset, result.itemWidth + gap, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, 0, accuracy: accuracy)
    }

    func testEqualDivisionTabsAlwaysLeaveExactlyButtonWidthOfRoom() {
        // Regression (3-tab crop / clip bugs): equal-division tabs must always leave exactly
        // buttonWidth of room after contentWidth + gap, never overshoot into the fixed icon cluster.
        let result = layout(stripWidth: 900, tabsCount: 3, maxWidth: 300)
        XCTAssertFalse(result.isFloored)
        XCTAssertEqual(result.addTabButtonLeadingOffset, 900 - buttonWidth, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, 0, accuracy: accuracy)
    }

    // MARK: - Full layout, floored (tabs can't shrink further)

    func testFlooredTabsCapButtonFlushWhenGenuinelyOverflowing() {
        let result = layout(stripWidth: 900, tabsCount: 8, maxWidth: 300)
        XCTAssertTrue(result.isFloored)
        XCTAssertEqual(result.addTabButtonLeadingOffset, 900 - buttonWidth, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, buttonWidth + gap, accuracy: accuracy)
    }

    func testFlooredTabsCapButtonFlushEvenWhenContentStillFitsRawStripWidth() {
        // Regression (13" iPad repro): floored contentWidth (1200) can still be under raw stripWidth
        // (1210) while already exceeding the safe reservation threshold (1210-44-6=1160). The button
        // must cap flush here, not follow contentWidth + gap (1206), which would overshoot the fixed
        // icon cluster's boundary (1166) despite technically fitting within the raw strip.
        let result = layout(stripWidth: 1210, tabsCount: 10, maxWidth: 400)
        XCTAssertTrue(result.isFloored)
        XCTAssertEqual(result.itemWidth, 120, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonLeadingOffset, 1210 - buttonWidth, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, buttonWidth + gap, accuracy: accuracy)
    }

    // MARK: - Degenerate inputs

    func testZeroStripWidthReturnsAllZero() {
        let result = layout(stripWidth: 0, tabsCount: 3, maxWidth: 300)
        XCTAssertEqual(result.itemWidth, 0, accuracy: accuracy)
        XCTAssertFalse(result.isFloored)
        XCTAssertEqual(result.addTabButtonLeadingOffset, 0, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, 0, accuracy: accuracy)
    }

    func testZeroTabsOffsetIsJustTheGap() {
        let result = layout(stripWidth: 900, tabsCount: 0, maxWidth: 300)
        XCTAssertFalse(result.isFloored)
        XCTAssertEqual(result.addTabButtonLeadingOffset, gap, accuracy: accuracy)
        XCTAssertEqual(result.addTabButtonContentInsetRight, 0, accuracy: accuracy)
    }
}

@MainActor
final class TabsBarCollectionViewLayoutTests: XCTestCase, UICollectionViewDataSource {

    private var itemCount = 10

    func testCurrentTabRemainsVisibleWhenScrolledPastLeadingEdge() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 0 }, contentOffset: 300)
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        let current = try XCTUnwrap(attributes.first { $0.indexPath.item == 0 })

        XCTAssertEqual(current.frame.minX, 310)
        XCTAssertEqual(current.zIndex, 2)
        XCTAssertEqual(layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))?.frame.minX, 360)

        let flare = TabFlareBackgroundController(collectionView: collectionView,
                                                topCornerRadius: TabsBarCell.cornerRadius,
                                                rampSize: TabsBarViewController.Constants.tabRampSize,
                                                currentIndex: { 0 },
                                                fillColor: { .white })
        flare.update()
        let cell = try XCTUnwrap(collectionView.cellForItem(at: current.indexPath))
        let background = try XCTUnwrap(collectionView.subviews.compactMap { $0 as? TabFlaredBackgroundView }.first)
        XCTAssertFalse(background.isHidden)
        XCTAssertGreaterThan(cell.layer.zPosition, background.layer.zPosition)
    }

    func testCurrentTabPinsBeforeTrailingButtonSpaceAndPreservesNaturalFrame() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 9 })
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        let current = try XCTUnwrap(attributes.first { $0.indexPath.item == 9 })

        XCTAssertEqual(current.frame.maxX, 540)
        XCTAssertEqual(layout.unpinnedFrameForItem(at: current.indexPath)?.minX, 1080)
    }

    func testCurrentTabKeepsNaturalPositionWhileFullyVisible() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 4 }, contentOffset: 200)
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        let current = try XCTUnwrap(attributes.first { $0.indexPath.item == 4 })

        XCTAssertEqual(current.frame.minX, 480)
        XCTAssertEqual(current.frame, layout.unpinnedFrameForItem(at: current.indexPath))
    }

    func testChangingCurrentTabReleasesPreviouslyPinnedTab() throws {
        var currentIndex = 0
        let (collectionView, layout) = makeCollectionView(currentIndex: { currentIndex }, contentOffset: 300)
        let previousIndexPath = IndexPath(item: 0, section: 0)
        XCTAssertEqual(layout.layoutAttributesForItem(at: previousIndexPath)?.frame.minX, 310)

        currentIndex = 9
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))

        let previous = try XCTUnwrap(layout.layoutAttributesForItem(at: previousIndexPath))
        let middle = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 5, section: 0)))
        XCTAssertEqual(previous.frame.minX, 310)
        XCTAssertLessThan(previous.zIndex, middle.zIndex)
        XCTAssertFalse(attributes.contains { $0.indexPath == previousIndexPath })
        XCTAssertEqual(attributes.first { $0.indexPath.item == 9 }?.frame.maxX, 840)
    }

    func testEdgeStacksStayInsideTabViewportWithManyTabs() throws {
        var sawLeadingOverlap = false
        var sawTrailingOverlap = false
        for offset in [CGFloat(30), 5790, 11460] {
            let (collectionView, layout) = makeCollectionView(currentIndex: { 50 }, contentOffset: offset, itemCount: 100)
            let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
            let leading = collectionView.bounds.minX + collectionView.adjustedContentInset.left
            let trailing = collectionView.bounds.maxX - collectionView.adjustedContentInset.right
            XCTAssertLessThan(attributes.count, 15)
            XCTAssertEqual(attributes.filter { $0.indexPath.item == 50 }.count, 1)
            XCTAssertFalse(collectionView.visibleCells.isEmpty)
            for cell in collectionView.visibleCells {
                XCTAssertGreaterThanOrEqual(cell.frame.minX, leading)
                XCTAssertLessThanOrEqual(cell.frame.maxX, trailing)
            }
            let reservedPoint = CGPoint(x: trailing + 1, y: collectionView.bounds.midY)
            XCTAssertTrue(collectionView.hitTest(reservedPoint, with: nil) === collectionView)

            let inactive = attributes.filter { $0.indexPath.item != 50 }.sorted { $0.indexPath.item < $1.indexPath.item }
            for (left, right) in zip(inactive, inactive.dropFirst()) where left.frame.intersects(right.frame) {
                if left.frame.minX == leading {
                    sawLeadingOverlap = true
                    XCTAssertLessThan(left.zIndex, right.zIndex)
                }
                if right.frame.maxX == trailing {
                    sawTrailingOverlap = true
                    XCTAssertGreaterThan(left.zIndex, right.zIndex)
                }
            }
        }
        XCTAssertTrue(sawLeadingOverlap)
        XCTAssertTrue(sawTrailingOverlap)
    }

    func testPointerBoundsExcludeCoveredPartsOfEdgeTabsAndCloseButton() throws {
        let (collectionView, _) = makeCollectionView(currentIndex: { 2 }, contentOffset: 10)
        let window = UIWindow(frame: collectionView.frame)
        window.addSubview(collectionView)
        defer { window.subviews.forEach { $0.removeFromSuperview() } }
        let leading = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? TabsBarCell)
        let trailing = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 4, section: 0)) as? TabsBarCell)
        let selected = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 2, section: 0)) as? TabsBarCell)
        let covered = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 5, section: 0)) as? TabsBarCell)
        for cell in [leading, trailing, selected, covered] {
            cell.layoutIfNeeded()
        }

        let leadingRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let trailingRect = CGRect(x: 50, y: 0, width: 70, height: 40)
        XCTAssertEqual(leading.visiblePointerRect(in: leading.contentView), leadingRect)
        XCTAssertEqual(trailing.visiblePointerRect(in: trailing.contentView), trailingRect)
        XCTAssertEqual(selected.visiblePointerRect(in: selected.contentView), selected.contentView.bounds)
        XCTAssertTrue(covered.visiblePointerRect(in: covered.contentView).isEmpty)
        XCTAssertEqual(leading.visiblePointerRect(in: leading.removeButton), CGRect(x: 0, y: 0, width: 20, height: 40))

        let interaction = try XCTUnwrap(covered.contentView.interactions.compactMap { $0 as? UIPointerInteraction }.first)
        let region = UIPointerRegion(rect: covered.contentView.bounds, identifier: nil)
        XCTAssertNil(covered.pointerInteraction(interaction, styleFor: region))

        if #available(iOS 17, *) {
            for (cell, expectedRect) in [(leading, leadingRect), (trailing, trailingRect)] {
                let pointer = try XCTUnwrap(cell.contentView.interactions.compactMap { $0 as? UIPointerInteraction }.first)
                let style = try XCTUnwrap(cell.pointerInteraction(pointer, styleFor: UIPointerRegion(rect: cell.contentView.bounds)))
                // Inspect UIKit's Objective-C effect; the Swift hover-style overlay erases its concrete type.
                let effect = try XCTUnwrap(style.__effect as? __UIPointerHoverEffect)
                XCTAssertEqual(effect.preview.parameters.visiblePath?.bounds, expectedRect)
                XCTAssertFalse(effect.prefersScaledContent)
            }
        }
    }

    private func makeCollectionView(currentIndex: @escaping () -> Int?, contentOffset: CGFloat = 0, itemCount: Int = 10)
        -> (UICollectionView, TabsBarCollectionViewLayout) {
        self.itemCount = itemCount
        let layout = TabsBarCollectionViewLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 40)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.currentIndex = currentIndex
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 600, height: 40), collectionViewLayout: layout)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 60)
        collectionView.register(TabsBarCell.self, forCellWithReuseIdentifier: TabsBarCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.contentOffset.x = contentOffset
        collectionView.layoutIfNeeded()
        return (collectionView, layout)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier, for: indexPath)
    }
}
