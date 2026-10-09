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
    // covers the hierarchy and interactions that need a real view controller.

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
    func testDragScrollsEarlyAndContinuouslyAtEitherEdgeAndStopsOutsideStrip() throws {
        let (controller, model) = makeOverflowingController()
        defer { withExtendedLifetime(model) {} }
        let collectionView = controller.collectionView
        let source = IndexPath(item: 4, section: 0)
        for direction in [CGFloat(-1), 1] {
            collectionView.contentOffset.x = 400
            collectionView.layoutIfNeeded()
            let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
            let session = TabsDragDropSession(locationView: controller.view,
                                             point: cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: controller.view))
            session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
            controller.collectionView(collectionView, dragSessionWillBegin: session)
            XCTAssertTrue(cell.contentView.isHidden)
            let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            let fingerX = direction < 0 ? viewport.minX + cell.bounds.width * 1.5 : viewport.maxX - cell.bounds.width * 1.5
            session.point = collectionView.convert(CGPoint(x: fingerX, y: viewport.midY), to: controller.view)
            _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
            for _ in 0..<2 {
                let previousOffset = collectionView.contentOffset.x
                controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
                XCTAssertGreaterThan(direction * (collectionView.contentOffset.x - previousOffset), 0)
            }

            controller.collectionView(collectionView, dropSessionDidExit: session)
            XCTAssertFalse(cell.contentView.isHidden)
            let exitOffset = collectionView.contentOffset
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertEqual(collectionView.contentOffset, exitOffset)
            controller.collectionView(collectionView, dropSessionDidEnter: session)
            XCTAssertTrue(cell.contentView.isHidden)
            controller.collectionView(collectionView, dragSessionDidEnd: session)
            XCTAssertFalse(cell.contentView.isHidden)
            let endOffset = collectionView.contentOffset
            controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
            XCTAssertEqual(collectionView.contentOffset, endOffset)
        }
    }

    @MainActor
    func testDraggingInNarrowStripStaysStillAtCenterAndScrollsTowardEdge() throws {
        let (controller, model) = makeOverflowingController()
        controller.view.frame.size.width = 300
        controller.view.layoutIfNeeded()
        controller.refresh(tabsModel: model)
        let collectionView = controller.collectionView
        collectionView.contentOffset.x = 400
        collectionView.layoutIfNeeded()
        let source = IndexPath(item: 8, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: source))
        let session = TabsDragDropSession(locationView: controller.view,
                                         point: cell.convert(CGPoint(x: 20, y: cell.bounds.midY), to: controller.view))
        session.items = controller.collectionView(collectionView, itemsForBeginning: session, at: source)
        let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        let fingerX = viewport.midX - cell.bounds.width / 2 + 20
        session.point = collectionView.convert(CGPoint(x: fingerX, y: viewport.midY), to: controller.view)
        _ = controller.collectionView(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: source)
        let initialOffset = collectionView.contentOffset.x
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertEqual(collectionView.contentOffset.x, initialOffset, accuracy: 0.001)
        session.point.x += 20
        controller.scrollDuringReorder(elapsedTime: 1.0 / 60)
        XCTAssertGreaterThan(collectionView.contentOffset.x, initialOffset)
        controller.collectionView(collectionView, dragSessionDidEnd: session)
        withExtendedLifetime(model) {}
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
    func testDroppingInactiveTabRevealsItWithoutChangingSelection() async throws {
        let (controller, model) = makeOverflowingController()
        let collectionView = controller.collectionView
        collectionView.contentOffset.x = 400
        collectionView.layoutIfNeeded()
        let source = IndexPath(item: 4, section: 0)
        let destination = IndexPath(item: 2, section: 0)
        let movedTab = try XCTUnwrap(model.get(tabAt: source.item))
        let selectedTab = model.currentTab
        let session = TabsDragDropSession(locationView: collectionView, point: CGPoint(x: 500, y: 20))
        let drop = TabsDrop(source: source, destination: destination, session: session)
        let layout = try XCTUnwrap(collectionView.collectionViewLayout as? TabsBarCollectionViewLayout)
        let revealFrame = try XCTUnwrap(layout.frameForRevealingItem(at: destination))
        let revealed = keyValueObservingExpectation(for: collectionView, keyPath: "contentOffset") { _, _ in
            collectionView.bounds.inset(by: collectionView.adjustedContentInset).contains(revealFrame)
        }

        controller.collectionView(collectionView, performDropWith: drop)

        await fulfillment(of: [revealed], timeout: 2)
        XCTAssertIdentical(model.currentTab, selectedTab)
        XCTAssertIdentical(model.get(tabAt: destination.item), movedTab)
    }

    @MainActor
    func testSelectionAndScrollingKeepFlareAlignedBeforeNextLayoutPass() throws {
        for isTrailingEdge in [false, true] {
            let (controller, model) = makeOverflowingController()
            defer { withExtendedLifetime(model) {} }
            let collectionView = controller.collectionView
            let layout = try XCTUnwrap(collectionView.collectionViewLayout as? TabsBarCollectionViewLayout)
            let indexPath = IndexPath(item: isTrailingEdge ? 10 : 6, section: 0)
            let naturalFrame = try XCTUnwrap(layout.unpinnedFrameForItem(at: indexPath))
            collectionView.contentOffset.x = isTrailingEdge
                ? naturalFrame.maxX - collectionView.bounds.width + collectionView.adjustedContentInset.right
                : naturalFrame.minX - collectionView.adjustedContentInset.left
            collectionView.layoutIfNeeded()
            let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath))
            XCTAssertNotEqual(cell.frame, naturalFrame)
            model.select(tab: try XCTUnwrap(model.get(tabAt: indexPath.item)))
            controller.refreshStyleInPlace(tabsModel: model)
            let background = try XCTUnwrap(collectionView.subviews.compactMap { $0 as? TabFlaredBackgroundView }.first)
            let ramp = TabsBarViewController.Constants.tabRampSize.width
            XCTAssertFalse(background.isHidden)
            XCTAssertGreaterThan(cell.layer.zPosition, background.layer.zPosition)
            XCTAssertEqual(background.frame, cell.frame.insetBy(dx: -ramp, dy: 0))

            collectionView.contentOffset.x += isTrailingEdge ? -60 : 60
            controller.scrollViewDidScroll(collectionView)
            XCTAssertEqual(background.frame, cell.frame.insetBy(dx: -ramp, dy: 0))
        }
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
private final class TabsDrop: NSObject, UICollectionViewDropCoordinator, UICollectionViewDropItem, UIDragAnimating {
    var items: [UICollectionViewDropItem] { [self] }
    let dragItem = UIDragItem(itemProvider: NSItemProvider())
    let sourceIndexPath: IndexPath?
    let destinationIndexPath: IndexPath?
    let previewSize = CGSize(width: 120, height: 40)
    let proposal = UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    let session: UIDropSession

    init(source: IndexPath, destination: IndexPath, session: UIDropSession) {
        sourceIndexPath = source
        destinationIndexPath = destination
        self.session = session
    }

    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) { completion(.end) }
    func drop(_ dragItem: UIDragItem, toItemAt indexPath: IndexPath) -> UIDragAnimating { self }
    func drop(_ dragItem: UIDragItem, intoItemAt indexPath: IndexPath, rect: CGRect) -> UIDragAnimating { self }
    func drop(_ dragItem: UIDragItem, to target: UIDragPreviewTarget) -> UIDragAnimating { self }
    func drop(_ dragItem: UIDragItem, to placeholder: UICollectionViewDropPlaceholder) -> UICollectionViewDropPlaceholderContext {
        fatalError("Placeholder drops are not used by these tests")
    }
}
