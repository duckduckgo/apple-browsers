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
    private var selectedIndex: () -> Int? = { nil }

    func testCurrentTabRemainsVisibleWhenScrolledPastLeadingEdge() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 0 }, contentOffset: 300)
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        let current = try XCTUnwrap(attributes.first { $0.indexPath.item == 0 })

        XCTAssertEqual(current.frame.minX, 310)
        XCTAssertEqual(current.zIndex, 2)
        let neighbor = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0)))
        XCTAssertGreaterThan(neighbor.frame.minX, 360)
        XCTAssertLessThan(neighbor.frame.minX, 361)

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
        let (collectionView, _) = makeCollectionView(currentIndex: { 2 })
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

        let leadingRect = CGRect(x: 0, y: 0, width: 110, height: 40)
        let trailingRect = CGRect(x: 60, y: 0, width: 60, height: 40)
        XCTAssertEqual(leading.visiblePointerRect(in: leading.contentView), leadingRect)
        XCTAssertEqual(trailing.visiblePointerRect(in: trailing.contentView), trailingRect)
        XCTAssertEqual(selected.visiblePointerRect(in: selected.contentView), selected.contentView.bounds)
        XCTAssertTrue(covered.visiblePointerRect(in: covered.contentView).isEmpty)
        XCTAssertEqual(leading.visiblePointerRect(in: leading.removeButton), CGRect(x: 0, y: 0, width: 30, height: 40))

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

    func testActiveDragKeepsAccordionTabsInsideVisibleStrip() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 0 }, contentOffset: 300, activeDrag: true)
        XCTAssertTrue(collectionView.hasActiveDrag)
        let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in: collectionView.bounds))
        XCTAssertEqual(attributes.first { $0.indexPath.item == 0 }?.frame.minX, 310)
        XCTAssertGreaterThan(collectionView.visibleCells.count, 1)
        for cell in collectionView.visibleCells {
            XCTAssertGreaterThanOrEqual(cell.frame.minX, 310)
            XCTAssertLessThanOrEqual(cell.frame.maxX, 840)
        }
    }

    func testEdgeAccordionStartsMovingNextTabAtHalfExposureAndOuterTabMovesFaster() throws {
        for (offset, direction, outerIndex, innerIndex) in [(CGFloat(290), CGFloat(1), 2, 3), (360, -1, 7, 6)] {
            let (collectionView, _) = makeCollectionView(currentIndex: { 4 }, contentOffset: offset)
            let outer = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: outerIndex, section: 0)) as? TabsBarCell)
            let inner = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: innerIndex, section: 0)))
            var previousOuterX = outer.frame.minX
            var previousInnerX = inner.frame.minX
            var previousExposure = outer.visiblePointerRect(in: outer.contentView).width
            XCTAssertEqual(previousExposure, outer.bounds.width / 2)

            for distance in [CGFloat(10), 20] {
                collectionView.contentOffset.x = offset + direction * distance
                collectionView.layoutIfNeeded()
                let outerMovement = direction * (outer.frame.minX - previousOuterX)
                let innerMovement = direction * (inner.frame.minX - previousInnerX)
                XCTAssertGreaterThan(innerMovement, 0)
                XCTAssertGreaterThan(outerMovement, innerMovement)
                XCTAssertLessThanOrEqual(outerMovement, 10)
                let exposure = outer.visiblePointerRect(in: outer.contentView).width
                XCTAssertGreaterThan(exposure, 0)
                XCTAssertLessThan(exposure, previousExposure)
                previousOuterX = outer.frame.minX
                previousInnerX = inner.frame.minX
                previousExposure = exposure
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

    func testReorderAttributesKeepInactiveCellsBelowSelectionAndResetOnReuse() throws {
        let (collectionView, layout) = makeCollectionView(currentIndex: { 2 }, contentOffset: 10)
        let selected = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 2, section: 0)) as? TabsBarCell)
        let inactive = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? TabsBarCell)
        let inactiveAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let originalOrder = inactive.layer.zPosition
        XCTAssertLessThan(originalOrder, 0)

        for (cell, index) in [(selected, 2), (inactive, 0)] {
            let attributes = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.copy() as? UICollectionViewLayoutAttributes)
            attributes.zIndex = 1000
            cell.apply(attributes)
        }
        XCTAssertEqual(selected.layer.zPosition, 2)
        XCTAssertEqual(inactive.layer.zPosition, 0)
        inactive.apply(inactiveAttributes)
        XCTAssertEqual(inactive.layer.zPosition, originalOrder)

        let theme = ThemeManager.shared.currentTheme
        inactive.applyCurrentStyle(isCurrent: true, isNextCurrent: false, hidesInactiveCloseButton: false, withTheme: theme)
        XCTAssertEqual(inactive.layer.zPosition, 2)
        inactive.applyCurrentStyle(isCurrent: false, isNextCurrent: false, hidesInactiveCloseButton: false, withTheme: theme)
        XCTAssertEqual(inactive.layer.zPosition, 0)
        inactive.applyCurrentStyle(isCurrent: true, isNextCurrent: false, hidesInactiveCloseButton: false, withTheme: theme)
        inactive.contentView.isHidden = true
        inactive.prepareForReuse()
        inactive.apply(inactiveAttributes)
        XCTAssertFalse(inactive.contentView.isHidden)
        XCTAssertEqual(inactive.layer.zPosition, originalOrder)
    }

    func testSelectingPartiallyCoveredEdgeTabRevealsItWithNeighborStillExposed() throws {
        for (offset, index, neighborIndex) in [(CGFloat(300), 2, 1), (330, 7, 8)] {
            var currentIndex = 4
            let (collectionView, layout) = makeCollectionView(currentIndex: { currentIndex }, contentOffset: offset)
            let indexPath = IndexPath(item: index, section: 0)
            let edge = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? TabsBarCell)
            let exposedWidth = edge.visiblePointerRect(in: edge.contentView).width
            XCTAssertGreaterThan(exposedWidth, 0)
            XCTAssertLessThan(exposedWidth, edge.bounds.width)

            currentIndex = index
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: indexPath))
            collectionView.scrollRectToVisible(revealFrame, animated: false)
            collectionView.layoutIfNeeded()

            let selected = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? TabsBarCell)
            let neighbor = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: neighborIndex, section: 0)) as? TabsBarCell)
            XCTAssertEqual(selected.frame, layout.unpinnedFrameForItem(at: indexPath))
            XCTAssertEqual(selected.visiblePointerRect(in: selected.contentView), selected.contentView.bounds)
            XCTAssertEqual(neighbor.visiblePointerRect(in: neighbor.contentView).width, 60)
        }
    }

    func testRevealingInactiveEdgeTabLeavesNeighborExposedBesidePinnedCurrentTab() throws {
        for (currentIndex, revealedIndex, neighborIndex, offset) in [(0, 20, 19, CGFloat(2600)), (99, 20, 21, CGFloat(2000))] {
            let (collectionView, layout) = makeCollectionView(currentIndex: { currentIndex }, contentOffset: offset, itemCount: 100)
            let indexPath = IndexPath(item: revealedIndex, section: 0)
            let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: indexPath))
            collectionView.scrollRectToVisible(revealFrame, animated: false)
            collectionView.layoutIfNeeded()

            let revealed = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? TabsBarCell)
            let neighbor = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: neighborIndex, section: 0)) as? TabsBarCell)
            XCTAssertEqual(revealed.visiblePointerRect(in: revealed.contentView), revealed.contentView.bounds)
            XCTAssertGreaterThan(neighbor.visiblePointerRect(in: neighbor.contentView).width, 0)
            XCTAssertLessThanOrEqual(revealFrame.width, collectionView.bounds.inset(by: collectionView.adjustedContentInset).width)
        }
    }

    func testRevealFrameRespectsContentEndsAndNarrowStripWithoutOverscroll() throws {
        for (width, expectedRevealWidth) in [(CGFloat(600), CGFloat(180)), (230, 140), (200, 125), (180, 120)] {
            let (collectionView, layout) = makeCollectionView(currentIndex: { nil }, contentOffset: 300)
            collectionView.bounds.size.width = width
            collectionView.layoutIfNeeded()
            let contentBounds = CGRect(origin: .zero, size: collectionView.contentSize)
            for index in [0, 9] {
                let indexPath = IndexPath(item: index, section: 0)
                let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: indexPath))
                let naturalFrame = try XCTUnwrap(layout.unpinnedFrameForItem(at: indexPath))
                XCTAssertTrue(contentBounds.contains(revealFrame))
                XCTAssertTrue(revealFrame.contains(naturalFrame))
                XCTAssertEqual(revealFrame.width, expectedRevealWidth)
                XCTAssertEqual(index == 0 ? revealFrame.minX : revealFrame.maxX, index == 0 ? 0 : contentBounds.maxX)
                collectionView.scrollRectToVisible(revealFrame, animated: false)
                collectionView.layoutIfNeeded()
                if width >= 200 {
                    XCTAssertEqual(collectionView.cellForItem(at: indexPath)?.frame, naturalFrame)
                    let usableBounds = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
                    for cell in collectionView.visibleCells {
                        XCTAssertTrue(usableBounds.contains(cell.frame))
                    }
                }
                XCTAssertGreaterThanOrEqual(collectionView.contentOffset.x, -collectionView.adjustedContentInset.left)
                XCTAssertLessThanOrEqual(collectionView.contentOffset.x, contentBounds.width - width + collectionView.adjustedContentInset.right)
            }
        }
    }

    func testFlareAnimatesToSelectedTabWhenReorderEnds() throws {
        var currentIndex = 0
        let (collectionView, layout) = makeCollectionView(currentIndex: { currentIndex }, contentOffset: 300)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = collectionView.frame
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(collectionView)
        window.makeKeyAndVisible()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer {
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let flare = TabFlareBackgroundController(collectionView: collectionView,
                                                topCornerRadius: TabsBarCell.cornerRadius,
                                                rampSize: TabsBarViewController.Constants.tabRampSize,
                                                currentIndex: { currentIndex },
                                                fillColor: { .white })
        flare.update()
        window.layoutIfNeeded()
        CATransaction.flush()
        let background = try XCTUnwrap(collectionView.subviews.compactMap { $0 as? TabFlaredBackgroundView }.first)
        XCTAssertEqual(background.frame, CGRect(x: 300, y: 0, width: 140, height: 40))

        flare.beginReorder()
        currentIndex = 5
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        flare.endReorder()
        CATransaction.flush()

        XCTAssertEqual(background.frame, CGRect(x: 590, y: 0, width: 140, height: 40))
        let animationKeys = background.layer.animationKeys() ?? []
        let positionAnimations = animationKeys.compactMap { background.layer.animation(forKey: $0) as? CAPropertyAnimation }
            .filter { $0.keyPath == "position" }
        if UIAccessibility.isReduceMotionEnabled {
            XCTAssertTrue(positionAnimations.isEmpty)
        } else {
            let animation = try XCTUnwrap(positionAnimations.first, "Expected a position animation; registered keys: \(animationKeys)")
            XCTAssertGreaterThan(animation.duration, 0)
        }

        collectionView.contentOffset.x = 700
        collectionView.layoutIfNeeded()
        flare.update(animated: true)
        CATransaction.flush()

        XCTAssertEqual(background.frame, CGRect(x: 700, y: 0, width: 140, height: 40))
        let remainingAnimations = (background.layer.animationKeys() ?? []).compactMap { background.layer.animation(forKey: $0) as? CAPropertyAnimation }
        XCTAssertFalse(remainingAnimations.contains { $0.keyPath == "position" })
    }

    private func makeCollectionView(currentIndex: @escaping () -> Int?, contentOffset: CGFloat = 0, itemCount: Int = 10, activeDrag: Bool = false)
        -> (UICollectionView, TabsBarCollectionViewLayout) {
        self.itemCount = itemCount
        selectedIndex = currentIndex
        let layout = TabsBarCollectionViewLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 40)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.currentIndex = currentIndex
        let collectionView = DraggingTabsCollectionView(frame: CGRect(x: 0, y: 0, width: 600, height: 40), collectionViewLayout: layout)
        collectionView.activeDrag = activeDrag
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
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier, for: indexPath)
        (cell as? TabsBarCell)?.applyCurrentStyle(isCurrent: indexPath.item == selectedIndex(),
                                                isNextCurrent: indexPath.item + 1 == selectedIndex(),
                                                hidesInactiveCloseButton: false,
                                                withTheme: ThemeManager.shared.currentTheme)
        return cell
    }
}

@MainActor
private final class DraggingTabsCollectionView: UICollectionView {
    var activeDrag = false
    override var hasActiveDrag: Bool { activeDrag }
}
