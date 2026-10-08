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
        XCTAssertEqual(controller.buttonsStack.arrangedSubviews.count, 4)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[0], controller.aiChatChip)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[1], controller.aiChatMenuButton)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[2], controller.fireButton)
        // addTabButton is positioned manually outside buttonsStack, see recomputeItemSize()/TabsBarLayout.
        XCTAssertFalse(controller.buttonsStack.arrangedSubviews.contains(controller.addTabButton))
        XCTAssertIdentical(controller.addTabButton.superview, controller.view)
    }

    // MARK: - Duck.ai chrome controls

    @MainActor
    func testAIChatMenuButtonIsTheDuckAIPill() throws {
        let controller = TabsBarViewController.create()
        controller.loadViewIfNeeded()

        let configuration = try XCTUnwrap(controller.aiChatMenuButton.configuration)
        XCTAssertEqual(configuration.title, UserText.actionOpenAIChat)
        let icon = try XCTUnwrap(configuration.image)
        XCTAssertEqual(icon.size, CGSize(width: 16, height: 16))
        XCTAssertEqual(icon.renderingMode, .alwaysTemplate)
        XCTAssertEqual(configuration.background.cornerRadius, TabsBarViewController.Constants.aiChatMenuButtonCornerRadius)
        XCTAssertEqual(controller.aiChatMenuButton.accessibilityLabel, UserText.accessibilityLabelOpenAIChat)
    }

    @MainActor
    func testWhenContextualSessionIsActiveThenAIChatMenuButtonSwapsToTheDownGlyph() throws {
        let controller = TabsBarViewController.create()
        controller.loadViewIfNeeded()
        let closedGlyph = try XCTUnwrap(controller.aiChatMenuButton.configuration?.image?.pngData())

        controller.updateAIChatMenuButtonForContextualChat(hasContextualSession: true)

        let openGlyph = try XCTUnwrap(controller.aiChatMenuButton.configuration?.image?.pngData())
        XCTAssertNotEqual(openGlyph, closedGlyph)

        controller.updateAIChatMenuButtonForContextualChat(hasContextualSession: false)

        XCTAssertEqual(try XCTUnwrap(controller.aiChatMenuButton.configuration?.image?.pngData()), closedGlyph)
    }

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

    @MainActor
    func testDragReentryHidesSourceBeforeInsertionSlotChangesAndExitRestoresIt() throws {
        let controller = TabsBarViewController.create()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 40)
        controller.view.layoutIfNeeded()
        let tabs = (0..<4).map { _ in Tab(desktop: true, fireTab: false) }
        let model = TabsModel(tabs: tabs, desktop: true)
        controller.refresh(tabsModel: model)
        let collectionView = controller.collectionView
        collectionView.layoutIfNeeded()
        let sourceIndex = IndexPath(item: 0, section: 0)
        let source = try XCTUnwrap(collectionView.cellForItem(at: sourceIndex) as? TabsBarCell)
        let session = TabsDragDropSession(locationView: collectionView,
                                          point: CGPoint(x: source.frame.minX + 20, y: source.frame.midY))
        session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: sourceIndex)
        XCTAssertEqual(session.items.count, 1)

        controller.collectionView(collectionView, dragSessionWillBegin: session)
        XCTAssertTrue(source.contentView.isHidden)
        controller.collectionView(collectionView, dropSessionDidExit: session)
        XCTAssertFalse(source.contentView.isHidden)
        controller.collectionView(collectionView, dropSessionDidEnter: session)
        XCTAssertTrue(source.contentView.isHidden)
        controller.collectionView(collectionView, dragSessionDidEnd: session)
        XCTAssertFalse(source.contentView.isHidden)
        XCTAssertEqual(model.tabs, tabs)
    }

    @MainActor
    func testDraggedTabPreviewHasOpaqueBackgroundAndFourRoundedCorners() throws {
        let (controller, model) = makeOverflowingController()
        defer { withExtendedLifetime(model) {} }
        let collectionView = controller.collectionView
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath))
        let parameters = try XCTUnwrap(controller.collectionView(collectionView, dragPreviewParametersForItemAt: indexPath))
        let path = try XCTUnwrap(parameters.visiblePath)

        XCTAssertGreaterThan(parameters.backgroundColor.cgColor.alpha, 0.5)
        XCTAssertEqual(path.bounds, cell.bounds)
        for x in [cell.bounds.minX + 1, cell.bounds.maxX - 1] {
            for y in [cell.bounds.minY + 1, cell.bounds.maxY - 1] {
                XCTAssertFalse(path.contains(CGPoint(x: x, y: y)))
            }
        }
        XCTAssertTrue(path.contains(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY)))
        XCTAssertTrue(path.contains(CGPoint(x: cell.bounds.midX, y: cell.bounds.maxY - 1)))
    }

    @MainActor
    func testReorderScrollsInsideBothEdgesAndStopsOnExitAndEnd() throws {
        let (controller, model) = makeOverflowingController()
        let collectionView = controller.collectionView
        collectionView.contentOffset.x = 400
        collectionView.layoutIfNeeded()
        let source = IndexPath(item: 4, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
        let session = TabsDragDropSession(locationView: collectionView,
                                         point: CGPoint(x: cell.frame.minX + 20, y: cell.frame.midY))
        session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
        XCTAssertEqual(session.items.count, 1)
        let currentTab = model.currentTab

        for direction in [CGFloat(-1), 1] {
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            session.point = CGPoint(x: direction < 0 ? viewport.minX + 60 : viewport.maxX - 60, y: viewport.midY)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
            let previousOffset = collectionView.contentOffset.x
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertGreaterThan(direction * (collectionView.contentOffset.x - previousOffset), 0)
        }

        session.point = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        let centerOffset = collectionView.contentOffset
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertEqual(collectionView.contentOffset, centerOffset)

        controller.collectionView(collectionView, dropSessionDidExit: session)
        let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        session.point = CGPoint(x: viewport.maxX - 60, y: viewport.midY)
        let exitOffset = collectionView.contentOffset
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertEqual(collectionView.contentOffset, exitOffset)

        controller.collectionView(collectionView, dropSessionDidEnter: session)
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertGreaterThan(collectionView.contentOffset.x, exitOffset.x)
        controller.collectionView(collectionView, dragSessionDidEnd: session)
        let endOffset = collectionView.contentOffset
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertEqual(collectionView.contentOffset, endOffset)
        XCTAssertIdentical(model.currentTab, currentTab)
    }

    @MainActor
    func testReorderScrollsEarlyAndContinuouslyWithStationaryFingerAtEitherEdge() throws {
        let (controller, model) = makeOverflowingController()
        defer { withExtendedLifetime(model) {} }
        let collectionView = controller.collectionView
        let source = IndexPath(item: 4, section: 0)
        let layout = try XCTUnwrap(collectionView.collectionViewLayout as? TabsBarCollectionViewLayout)
        let tabWidth = layout.itemSize.width

        for direction in [CGFloat(-1), 1] {
            collectionView.contentOffset.x = 400
            collectionView.layoutIfNeeded()
            let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
            let session = TabsDragDropSession(locationView: controller.view,
                                             point: cell.convert(CGPoint(x: tabWidth / 2, y: cell.bounds.midY), to: controller.view))
            session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
            XCTAssertEqual(session.items.count, 1)
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            let fingerX = direction < 0 ? viewport.minX + tabWidth * 1.5 : viewport.maxX - tabWidth * 1.5
            session.point = collectionView.convert(CGPoint(x: fingerX, y: viewport.midY), to: controller.view)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)

            for _ in 0..<10 {
                let previousOffset = collectionView.contentOffset.x
                controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
                XCTAssertGreaterThan(direction * (collectionView.contentOffset.x - previousOffset), 0)
            }
            controller.collectionView(collectionView, dragSessionDidEnd: session)
        }
    }

    @MainActor
    func testReorderScrollingDependsOnPreviewEdgesInsteadOfFingerGrabPosition() throws {
        let (controller, model) = makeOverflowingController()
        defer { withExtendedLifetime(model) {} }
        let collectionView = controller.collectionView
        let source = IndexPath(item: 4, section: 0)
        var distances: [CGFloat] = []

        for grabOffset in [CGFloat(20), 60] {
            collectionView.contentOffset.x = 400
            collectionView.layoutIfNeeded()
            let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
            let session = TabsDragDropSession(locationView: controller.view,
                                             point: cell.convert(CGPoint(x: grabOffset, y: cell.bounds.midY), to: controller.view))
            session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
            XCTAssertEqual(session.items.count, 1)
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            let previewMinX = viewport.minX + cell.bounds.width
            session.point = collectionView.convert(CGPoint(x: previewMinX + grabOffset, y: viewport.midY), to: controller.view)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
            let previousOffset = collectionView.contentOffset.x
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            distances.append(collectionView.contentOffset.x - previousOffset)
            controller.collectionView(collectionView, dragSessionDidEnd: session)
        }
        XCTAssertLessThan(distances[0], 0)
        XCTAssertEqual(distances[0], distances[1], accuracy: 0.001)
    }

    @MainActor
    func testReorderScrollingUsesPreviewEdgesInNarrowStrips() throws {
        for width in [CGFloat(600), 300] {
            let (controller, model) = makeOverflowingController()
            defer { withExtendedLifetime(model) {} }
            controller.view.frame.size.width = width
            controller.view.layoutIfNeeded()
            controller.refresh(tabsModel: model)
            let collectionView = controller.collectionView
            collectionView.contentOffset.x = 400
            collectionView.layoutIfNeeded()
            let source = IndexPath(item: 8, section: 0)
            let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            XCTAssertLessThan(viewport.width, cell.bounds.width * 11 / 3)
            XCTAssertGreaterThan(viewport.width, 0)
            let session = TabsDragDropSession(locationView: controller.view,
                                             point: cell.convert(CGPoint(x: 20, y: cell.bounds.midY), to: controller.view))
            session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
            XCTAssertEqual(session.items.count, 1)
            let fingerX = viewport.midX - cell.bounds.width / 2 + 20
            session.point = collectionView.convert(CGPoint(x: fingerX, y: viewport.midY), to: controller.view)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
            let previousOffset = collectionView.contentOffset
            for _ in 0..<10 {
                controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            }
            XCTAssertEqual(collectionView.contentOffset.x, previousOffset.x, accuracy: 0.001)
            session.point.x += 20
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertGreaterThan(collectionView.contentOffset.x, previousOffset.x)
            controller.collectionView(collectionView, dragSessionDidEnd: session)
        }
    }

    @MainActor
    func testReorderScrollingClampsAtBothContentEnds() throws {
        let (controller, model) = makeOverflowingController()
        defer { withExtendedLifetime(model) {} }
        let collectionView = controller.collectionView
        let source = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
        let session = TabsDragDropSession(locationView: collectionView,
                                         point: CGPoint(x: cell.frame.minX + 20, y: cell.frame.midY))
        session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
        XCTAssertEqual(session.items.count, 1)
        let minimumOffset = -collectionView.adjustedContentInset.left
        let maximumOffset = collectionView.contentSize.width - collectionView.bounds.width + collectionView.adjustedContentInset.right

        for (limit, direction) in [(minimumOffset, CGFloat(-1)), (maximumOffset, CGFloat(1))] {
            collectionView.contentOffset.x = limit - direction
            collectionView.layoutIfNeeded()
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            session.point = CGPoint(x: direction < 0 ? viewport.minX + 1 : viewport.maxX - 1, y: viewport.midY)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertEqual(collectionView.contentOffset.x, limit, accuracy: 0.001)
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertEqual(collectionView.contentOffset.x, limit, accuracy: 0.001)
        }
        controller.collectionView(collectionView, dragSessionDidEnd: session)
    }

    @MainActor
    func testDroppingInactiveTabAtEdgeRevealsItsNeighborWithoutSelectingIt() async throws {
        let (controller, model) = makeOverflowingController()
        let collectionView = controller.collectionView
        collectionView.contentOffset.x = 400
        collectionView.layoutIfNeeded()
        let source = IndexPath(item: 4, section: 0)
        let destination = IndexPath(item: 2, section: 0)
        let movedTab = try XCTUnwrap(model.get(tabAt: source.item))
        let selectedTab = model.currentTab
        let session = TabsDragDropSession(locationView: collectionView, point: CGPoint(x: 500, y: 20))
        session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
        _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: destination)
        let item = TabsCollectionDropItem(sourceIndexPath: source)
        let coordinator = TabsCollectionDropCoordinator(item: item, destination: destination, session: session)
        let layout = try XCTUnwrap(collectionView.collectionViewLayout as? TabsBarCollectionViewLayout)
        let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: destination))
        let revealed = keyValueObservingExpectation(for: collectionView, keyPath: "contentOffset") { _, _ in
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            return viewport.contains(revealFrame)
        }

        controller.collectionView(collectionView, performDropWith: coordinator)
        let dropOffset = collectionView.contentOffset
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertEqual(collectionView.contentOffset, dropOffset)
        coordinator.animator.completion?(.end)

        await fulfillment(of: [revealed], timeout: 2)
        XCTAssertIdentical(model.currentTab, selectedTab)
        XCTAssertIdentical(model.get(tabAt: destination.item), movedTab)
        XCTAssertEqual(coordinator.droppedIndexPath, destination)
    }

    @MainActor
    private func makeOverflowingController() -> (TabsBarViewController, TabsModel) {
        let controller = TabsBarViewController.create()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 40)
        controller.view.layoutIfNeeded()
        let tabs = (0..<17).map { _ in Tab(desktop: true, fireTab: false) }
        let model = TabsModel(tabs: tabs, currentIndex: 8, desktop: true)
        controller.refresh(tabsModel: model)
        controller.collectionView.layoutIfNeeded()
        return (controller, model)
    }

    @MainActor
    func testScrollCallbackKeepsFlareAlignedWithPinnedSelectedCellBeforeNextLayoutPass() throws {
        let controller = TabsBarViewController.create()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 40)
        controller.view.layoutIfNeeded()
        let tabs = (0..<17).map { _ in Tab(desktop: true, fireTab: false) }
        let model = TabsModel(tabs: tabs, currentIndex: 8, desktop: true)
        controller.refresh(tabsModel: model)
        let collectionView = controller.collectionView
        collectionView.layoutIfNeeded()
        let background = try XCTUnwrap(collectionView.subviews.compactMap { $0 as? TabFlaredBackgroundView }.first)
        let layout = try XCTUnwrap(collectionView.collectionViewLayout as? TabsBarCollectionViewLayout)
        let indexPath = IndexPath(item: 8, section: 0)
        let rampWidth = TabsBarViewController.Constants.tabRampSize.width

        for (initialOffset, direction) in [(CGFloat(0), CGFloat(1)), (1200, -1)] {
            collectionView.contentOffset.x = initialOffset
            collectionView.layoutIfNeeded()
            controller.scrollViewDidScroll(collectionView)
            let selected = try XCTUnwrap(collectionView.cellForItem(at: indexPath))
            XCTAssertNotEqual(selected.frame, layout.unpinnedFrameForItem(at: indexPath))
            for distance in [CGFloat(20), 40, 60] {
                collectionView.contentOffset.x = initialOffset + direction * distance
                controller.scrollViewDidScroll(collectionView)
                XCTAssertEqual(background.frame, selected.frame.insetBy(dx: -rampWidth, dy: 0))
            }
        }
    }
}

@MainActor
private final class TabsDragDropSession: NSObject, UIDragSession, UIDropSession {
    var items: [UIDragItem] = []
    var localContext: Any?
    var localDragSession: UIDragSession? { self }
    var allowsMoveOperation: Bool { true }
    var isRestrictedToDraggingApplication: Bool { true }
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .none
    var progress = Progress(totalUnitCount: 0)
    private let locationView: UIView
    var point: CGPoint

    init(locationView: UIView, point: CGPoint) {
        self.locationView = locationView
        self.point = point
    }

    func location(in view: UIView) -> CGPoint { view.convert(point, from: locationView) }
    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { false }
    func canLoadObjects(ofClass aClass: NSItemProviderReading.Type) -> Bool { false }
    func loadObjects(ofClass aClass: NSItemProviderReading.Type, completion: @escaping ([NSItemProviderReading]) -> Void) -> Progress {
        completion([])
        return progress
    }
}

@MainActor
private final class TabsCollectionDropItem: NSObject, UICollectionViewDropItem {
    let dragItem = UIDragItem(itemProvider: NSItemProvider())
    let sourceIndexPath: IndexPath?
    let previewSize = CGSize(width: 120, height: 40)

    init(sourceIndexPath: IndexPath) {
        self.sourceIndexPath = sourceIndexPath
    }
}

@MainActor
private final class TabsDropAnimator: NSObject, UIDragAnimating {
    var completion: ((UIViewAnimatingPosition) -> Void)?

    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) { self.completion = completion }
}

@MainActor
private final class TabsCollectionDropCoordinator: NSObject, UICollectionViewDropCoordinator {
    let items: [UICollectionViewDropItem]
    let destinationIndexPath: IndexPath?
    let proposal = UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    let session: UIDropSession
    let animator = TabsDropAnimator()
    private(set) var droppedIndexPath: IndexPath?

    init(item: UICollectionViewDropItem, destination: IndexPath, session: UIDropSession) {
        items = [item]
        destinationIndexPath = destination
        self.session = session
    }

    func drop(_ dragItem: UIDragItem, toItemAt indexPath: IndexPath) -> UIDragAnimating {
        droppedIndexPath = indexPath
        return animator
    }

    func drop(_ dragItem: UIDragItem, to placeholder: UICollectionViewDropPlaceholder) -> UICollectionViewDropPlaceholderContext {
        fatalError("Placeholder drops are not used by these tests")
    }

    func drop(_ dragItem: UIDragItem, intoItemAt indexPath: IndexPath, rect: CGRect) -> UIDragAnimating { animator }
    func drop(_ dragItem: UIDragItem, to target: UIDragPreviewTarget) -> UIDragAnimating { animator }
}
