//
//  VerticalTabTearOffIntegrationTests.swift
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

import AppKit
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VerticalTabTearOffIntegrationTests: XCTestCase {

    func testAppKitDragEventsShowTheSidebarPreviewAndMoveTheTabIntoANewWindowOnMouseUp() async throws {
        TestRunHelper.allowAppSendUserEvents = true
        defer { TestRunHelper.allowAppSendUserEvents = false }
        let draggedTab = Tab(content: .bookmarks)
        let otherTab = Tab(content: .newtab)
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [draggedTab, otherTab]),
                                                selectionIndex: .unpinned(0), pinnedTabsManagerProvider: nil)
        var destinationWindow: NSWindow?
        var dropPoint: NSPoint?
        defer { destinationWindow?.close() }
        let detached = expectation(description: "Mouse-up creates the destination window")
        let model = VerticalTabsViewModel(tabCollectionViewModel: collection, onCloseTab: { _ in }, onTearOffTab: { index, point in
            collection.moveTabToNewWindow(at: .unpinned(index), droppingPoint: point) { tab, point in
                dropPoint = point
                destinationWindow = WindowsManager.openNewWindow(with: tab, droppingPoint: point)
                detached.fulfill()
                return destinationWindow
            }
        }, openNewTab: {})
        let controller = VerticalTabsViewController(viewModel: model, themeManager: NSApp.delegateTyped.themeManager)
        let sourceWindow = NSWindow(contentViewController: controller)
        sourceWindow.isReleasedWhenClosed = false
        sourceWindow.setContentSize(NSSize(width: 200, height: 480))
        sourceWindow.center()
        sourceWindow.orderFront(nil)
        defer { sourceWindow.close() }
        controller.view.layoutSubtreeIfNeeded()

        func post(_ type: NSEvent.EventType, at point: NSPoint) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sourceWindow.windowNumber,
                                                        context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            NSApp.postEvent(event, atStart: false)
        }
        let inside = NSPoint(x: 80, y: 350)
        let outside = NSPoint(x: sourceWindow.frame.width + 30, y: inside.y)
        let outsideOnScreen = sourceWindow.convertPoint(toScreen: outside)
        controller.dragSession.beginDragging(draggedTab.uuid)
        try post(.leftMouseDragged, at: inside)
        let insideSource = expectation(for: NSPredicate { _, _ in controller.dragSession.isPointerOverSidebar }, evaluatedWith: nil)
        await fulfillment(of: [insideSource], timeout: 2)
        XCTAssertTrue(sourceWindow.childWindows?.isEmpty ?? true)

        try post(.leftMouseDragged, at: outside)
        let showingPreview = expectation(for: NSPredicate { _, _ in sourceWindow.childWindows?.first is NSPanel }, evaluatedWith: nil)
        await fulfillment(of: [showingPreview], timeout: 2)
        let preview = try XCTUnwrap(sourceWindow.childWindows?.first as? NSPanel)
        XCTAssertTrue(preview.ignoresMouseEvents)
        XCTAssertNil(destinationWindow)
        try post(.leftMouseUp, at: outside)
        await fulfillment(of: [detached], timeout: 2)

        XCTAssertEqual(dropPoint, outsideOnScreen)
        XCTAssertTrue(sourceWindow.childWindows?.isEmpty ?? true)
        let destination = try XCTUnwrap(destinationWindow?.windowController as? MainWindowController)
        XCTAssertIdentical(destination.mainViewController.tabCollectionViewModel.selectedTab, draggedTab)
        XCTAssertEqual(collection.tabs.map(\.uuid), [otherTab.uuid])
    }
}
