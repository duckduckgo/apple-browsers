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

    private var selectedIndex: () -> Int? = { nil }

    func testSelectedTabStaysVisibleAcrossScrollingAndSelectionChanges() throws {
        var currentIndex = 0
        let (collectionView, layout) = makeCollectionView(currentIndex: { currentIndex }, contentOffset: 300)
        for (index, offset) in [(0, CGFloat(300)), (99, 300), (4, 200)] {
            currentIndex = index
            collectionView.contentOffset.x = offset
            layout.invalidateLayout()
            collectionView.layoutIfNeeded()
            let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
            let current = try XCTUnwrap(attributes.first { $0.indexPath.item == index })
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            XCTAssertTrue(viewport.contains(current.frame))
            XCTAssertNotNil(collectionView.cellForItem(at: current.indexPath))
            XCTAssertTrue(attributes.filter { $0.indexPath != current.indexPath }.allSatisfy { $0.zIndex < current.zIndex })
            if index != 0 {
                XCTAssertFalse(attributes.contains { $0.indexPath.item == 0 })
            }
            if index == 4 {
                XCTAssertEqual(current.frame, layout.unpinnedFrameForItem(at: current.indexPath))
            }
        }
    }

    func testOutgoingAccordionTabRemainsMaterializedWhileStillExposed() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 4 }, contentOffset: 380)
        let indexPath = IndexPath(item: 2, section: 0)
        let naturalFrame = try XCTUnwrap(layout.unpinnedFrameForItem(at: indexPath))
        XCTAssertFalse(naturalFrame.intersects(collectionView.bounds))
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        XCTAssertTrue(attributes.contains { $0.indexPath == indexPath })
        let outgoing = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? TabsBarCell)
        XCTAssertGreaterThan(outgoing.visiblePointerRect(in: outgoing.contentView).width, 0)
    }

    func testPointerPreviewClipsCoveredTabsAndExcludesTabContent() throws {
        let (collectionView, _) = makeCollectionView(currentIndex: { 2 }, contentOffset: 0)
        let window = UIWindow(frame: collectionView.frame)
        window.addSubview(collectionView)
        defer { collectionView.removeFromSuperview() }
        for (index, exposedRect) in [(0, CGRect(x: 0, y: 0, width: 110, height: 40)),
                                     (4, CGRect(x: 60, y: 0, width: 60, height: 40)), (5, .zero)] {
            let cell = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? TabsBarCell)
            cell.layoutIfNeeded()
            XCTAssertEqual(cell.visiblePointerRect(in: cell.contentView), exposedRect)
            let pointer = try XCTUnwrap(cell.contentView.interactions.compactMap { $0 as? UIPointerInteraction }.first)
            let style = cell.pointerInteraction(pointer, styleFor: UIPointerRegion(rect: cell.contentView.bounds))
            if exposedRect.isEmpty {
                XCTAssertNil(style)
            } else if #available(iOS 17, *) {
                let effect = try XCTUnwrap(style?.__effect as? __UIPointerHoverEffect)
                XCTAssertEqual(effect.preview.parameters.visiblePath?.bounds, exposedRect)
                XCTAssertIdentical(effect.preview.view.superview, cell.contentView)
                XCTAssertTrue(effect.preview.view.subviews.isEmpty, "Hover must not independently render the title or favicon")
            }
        }
    }

    func testRevealingEdgeTabExposesItAndANeighborWithOrWithoutPinnedSelection() throws {
        for (current, target, neighbor, offset) in [(2, 2, 1, CGFloat(300)), (7, 7, 8, 330),
                                                   (0, 20, 19, 2600), (99, 20, 21, 2000)] {
            let (collectionView, layout) = makeCollectionView(currentIndex: { current }, contentOffset: offset)
            let indexPath = IndexPath(item: target, section: 0)
            let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: indexPath))
            collectionView.scrollRectToVisible(revealFrame, animated: false)
            collectionView.layoutIfNeeded()

            let revealed = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? TabsBarCell)
            let adjacent = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: neighbor, section: 0)) as? TabsBarCell)
            XCTAssertEqual(revealed.visiblePointerRect(in: revealed.contentView), revealed.contentView.bounds)
            XCTAssertGreaterThan(adjacent.visiblePointerRect(in: adjacent.contentView).width, 0)
            XCTAssertTrue(CGRect(origin: .zero, size: collectionView.contentSize).contains(revealFrame))
        }
    }

    private func makeCollectionView(currentIndex: @escaping () -> Int?, contentOffset: CGFloat)
        -> (UICollectionView, TabsBarCollectionViewLayout) {
        selectedIndex = currentIndex
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

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 100 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier, for: indexPath)
        (cell as? TabsBarCell)?.applyCurrentStyle(isCurrent: indexPath.item == selectedIndex(),
                                                isNextCurrent: indexPath.item + 1 == selectedIndex(),
                                                hidesInactiveCloseButton: false,
                                                withTheme: ThemeManager.shared.currentTheme)
        return cell
    }
}
