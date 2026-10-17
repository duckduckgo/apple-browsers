//
//  TabBarTabPreviewTests.swift
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
import Combine
import Common
import FeatureFlags_macOS
import FoundationExtensions
import History
import HistoryView
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// https://app.asana.com/1/137249556945/project/1199230911884351/task/1208347387296425
@MainActor
final class TabBarTabPreviewTests: XCTestCase {

    private var window: OverlayTestWindow!
    private var mainViewController: MainViewController!
    private var tabCollectionViewModel: TabCollectionViewModel!

    override func setUp() async throws {
        tabCollectionViewModel = TabCollectionViewModel(isPopup: false)
        tabCollectionViewModel.appendNewTab(with: .none, selected: true)
        // enough tabs for them not to be at their maximum width, so the tab width changes when a tab is closed
        for _ in 1..<8 {
            tabCollectionViewModel.appendNewTab(with: .none, selected: false, forceChange: true)
        }

        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: Application.appDelegate.featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: MockFireproofDomains(),
                                              faviconManagement: FaviconManagerMock(),
                                              windowControllersManager: WindowControllersManagerMock(),
                                              dataClearingPreferences: Application.appDelegate.dataClearingPreferences,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())
        mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: MockBookmarkManager(),
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger()),
            fireCoordinator: fireCoordinator
        )

        window = OverlayTestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = mainViewController.view
        mainViewController.tabBarViewController.viewWillAppear()
        mainViewController.tabBarViewController.viewDidAppear()
        window.orderFront(nil)
        mainViewController.view.layoutSubtreeIfNeeded()
    }

    override func tearDown() async throws {
        window.childWindows?.forEach { window.removeChildWindow($0); $0.orderOut(nil) }
        window.orderOut(nil)
        window.contentView = nil
        mainViewController = nil
        tabCollectionViewModel = nil
        window = nil
    }

    /// A non-activating overlay (system notification, etc.) takes the pointer: the tab receives `mouseExited` while the window stays key
    /// and the cursor‘s coordinates are still over the tab. The preview must go away.
    func testWhenTabReceivesMouseExitedWhileCursorIsStillOverItThenPreviewIsHidden() async throws {
        let tabView = try XCTUnwrap(inactiveTabMouseOverView())
        placeWindow(sothat: tabView, isUnderCursor: true)
        tabView.updateTrackingAreas() // cursor is over the tab: hovered, preview scheduled

        try await waitUntil("preview is shown") { self.isTabPreviewShown }

        try sendMouseExited(to: tabView)
        XCTAssertFalse(tabView.isMouseOver)

        try await waitUntil("preview is hidden") { !self.isTabPreviewShown }
    }


    /// The tab bar keeps the tab width unchanged after closing a tab while the cursor is inside it (so the next close button stays under the cursor)
    /// and releases it when the mouse exits. A tab covered by another window gets `mouseExited` while the cursor is still over it:
    /// the layout must not stay frozen.
    func testWhenTabReceivesMouseExitedWhileCursorIsStillOverItThenFrozenLayoutIsReleased() async throws {
        let tabViews = inactiveTabMouseOverViews()
        XCTAssertGreaterThan(tabViews.count, 2)
        let tabView = tabViews[2]
        let tabItem = try XCTUnwrap(tabView.delegate as? TabBarViewItem)
        placeWindow(sothat: tabView, isUnderCursor: true)
        tabView.updateTrackingAreas()
        XCTAssertTrue(tabView.isMouseOver)
        let initialWidth = tabItem.view.frame.width
        XCTAssertLessThan(initialWidth, TabBarViewItem.Width.maximum, "the tabs must have room to grow when a tab is closed")

        // close a tab to the right of the hovered one with the cursor inside the tab bar: the layout is frozen
        tabCollectionViewModel.remove(at: .unpinned(5))
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(tabItem.view.frame.width, initialWidth, accuracy: 1, "the tab width must be kept while the mouse is in the tab bar")

        try sendMouseExited(to: tabView)

        try await waitUntil("frozen layout is released") { tabItem.view.frame.width > initialWidth + 1 }
    }

    // MARK: - Helpers

    private var isTabPreviewShown: Bool {
        window.childWindows?.contains { $0.windowController is TabPreviewWindowController } == true
    }

    /// Hover views of the non-selected (non-pinned) tab items sorted left to right
    private func inactiveTabMouseOverViews() -> [MouseOverView] {
        let tabBarView = mainViewController.tabBarViewController.view
        return tabBarView.allDescendants(ofType: MouseOverView.self)
            .filter { ($0.delegate as? TabBarViewItem)?.isSelected == false }
            .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    private func inactiveTabMouseOverView() -> MouseOverView? {
        inactiveTabMouseOverViews().last
    }

    /// What an overlaying window taking the mouse causes: the tab receives `mouseExited` while the cursor coordinates are still over it
    private func sendMouseExited(to tabView: MouseOverView) throws {
        let trackingArea = try XCTUnwrap(tabView.trackingAreas.compactMap { $0 as? HoverTrackingArea }.first)
        let exitEvent = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited,
                                                              location: NSEvent.mouseLocation,
                                                              modifierFlags: [],
                                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: window.windowNumber,
                                                              context: nil,
                                                              eventNumber: 0,
                                                              trackingNumber: 0,
                                                              userData: nil))
        trackingArea.mouseExited(exitEvent)
    }

    private func placeWindow(sothat view: NSView, isUnderCursor: Bool) {
        let centerInWindow = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - centerInWindow.x, y: mouse.y - centerInWindow.y))
        window.makeKeyAndOrderFront(nil)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = TabPreviewWindowController.delay + 3, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "Timed out: \(description)")
    }

}

final class OverlayTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + $0.allDescendants(ofType: type) }
    }
}
