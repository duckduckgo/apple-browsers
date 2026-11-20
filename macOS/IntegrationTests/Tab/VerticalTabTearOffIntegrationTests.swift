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
import FeatureFlags_macOS
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VerticalTabTearOffIntegrationTests: XCTestCase {

    func testDroppingOnAnotherSidebarInsertsBetweenItsRowsWithoutOpeningAWindow() async throws {
        let app = NSApp.delegateTyped
        let flags = try XCTUnwrap(app.featureFlagger as? MockFeatureFlagger)
        let key = FeatureFlag.verticalTabs.rawValue
        let previousFlag = flags.featuresStub[key]
        let previousPreference = app.appearancePreferences.useVerticalTabs
        flags.featuresStub[key] = true
        flags.triggerUpdate()
        app.appearancePreferences.useVerticalTabs = true
        defer {
            app.appearancePreferences.useVerticalTabs = previousPreference
            flags.featuresStub[key] = previousFlag
            flags.triggerUpdate()
        }

        let dragged = Tab(content: .bookmarks)
        let remaining = Tab(content: .settings(pane: nil))
        let sourceTabs = TabCollectionViewModel(tabCollection: TabCollection(tabs: [dragged, remaining]),
                                                selectionIndex: .unpinned(0), pinnedTabsManagerProvider: nil)
        let first = Tab(content: .bookmarks)
        let second = Tab(content: .settings(pane: nil))
        let targetTabs = TabCollectionViewModel(tabCollection: TabCollection(tabs: [first, second]),
                                                selectionIndex: .unpinned(0), pinnedTabsManagerProvider: nil)
        let size = NSSize(width: 900, height: 600)
        let source = try XCTUnwrap(WindowsManager.openNewWindow(with: sourceTabs, burnerMode: .regular, contentSize: size))
        defer { autoreleasepool { source.close() } }
        let target = try XCTUnwrap(WindowsManager.openNewWindow(with: targetTabs, burnerMode: .regular, contentSize: size))
        defer { autoreleasepool { target.close() } }
        func sidebar(in window: NSWindow) throws -> VerticalTabsViewController {
            let main = try XCTUnwrap((window.windowController as? MainWindowController)?.mainViewController)
            return try XCTUnwrap(main.children.compactMap { $0 as? VerticalTabsViewController }.first)
        }
        let sourceSidebar = try sidebar(in: source)
        let targetSidebar = try sidebar(in: target)
        let rows = targetSidebar.dragSession.rowsAnchor
        let laidOut = expectation(for: NSPredicate { [weak rows, weak target] _, _ in
            guard let rows, let target else { return false }
            return rows.window === target && !rows.bounds.isEmpty
        }, evaluatedWith: nil)
        await fulfillment(of: [laidOut], timeout: 2)
        let middle = NSPoint(x: rows.bounds.midX, y: rows.bounds.midY)
        let drop = target.convertPoint(toScreen: rows.convert(middle, to: nil))
        // Both frames contain the pointer. The drop belongs to the topmost window.
        source.setFrame(target.frame, display: false)
        XCTAssertTrue(source.frame.contains(drop))
        let windowCount = app.windowControllersManager.mainWindowControllers.count
        func releaseOverTarget() {
            sourceSidebar.dragSession.beginDragging(dragged.uuid)
            sourceSidebar.dragSession.end(at: drop) { point in
                XCTAssertEqual(point, drop)
                return target
            }
        }

        targetTabs.changesEnabled = false
        releaseOverTarget()
        XCTAssertEqual(sourceTabs.tabs.map(\.uuid), [dragged.uuid, remaining.uuid])
        XCTAssertEqual(targetTabs.tabs.map(\.uuid), [first.uuid, second.uuid])
        targetTabs.changesEnabled = true
        releaseOverTarget()

        XCTAssertEqual(app.windowControllersManager.mainWindowControllers.count, windowCount)
        XCTAssertIdentical(targetTabs.selectedTab, dragged)
        XCTAssertEqual(targetTabs.tabs.map(\.uuid), [first.uuid, dragged.uuid, second.uuid])
        XCTAssertEqual(sourceTabs.tabs.map(\.uuid), [remaining.uuid])
    }

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
