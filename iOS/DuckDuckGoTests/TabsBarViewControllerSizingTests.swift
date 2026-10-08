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
    private let point: CGPoint

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
