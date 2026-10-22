//
//  FireWindowClosingTests.swift
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

import Combine
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Snapshot playback is skipped in test runs while presentation and completion remain observable.
final class FireWindowClosingTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    private var initialFireAnimationEnabled = true

    @MainActor
    override func setUp() {
        initialFireAnimationEnabled = Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = true
    }

    @MainActor
    override func tearDown() {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = initialFireAnimationEnabled
        cancellables = []
        autoreleasepool {
            WindowsManager.closeWindows()
            for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
                Application.appDelegate.windowControllersManager.unregister(controller)
            }
        }
        // Allow WebKit IPC to settle after closing windows
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        // AppKit retains the last event's window, including the fresh window's suggestions panel.
        // Process a windowless event before the harness verifies closed-view deallocation.
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        NSApp.postEvent(event, atStart: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    // MARK: - Tests

    func testOnlyClosingWholeWindowBurnsUseSnapshots() {
        XCTAssertTrue(Fire.BurningData.all.usesWindowSnapshot)
        XCTAssertTrue(Fire.BurningData.specificDomains([], closesTabs: true, scope: .window).usesWindowSnapshot)
        XCTAssertTrue(Fire.BurningData.specificDomains([], closesTabs: true, scope: .allWindows).usesWindowSnapshot)
        XCTAssertTrue(Fire.BurningData.specificDomains([], closesTabs: true, scope: .visits).usesWindowSnapshot)
        for scope: Fire.BurningScope in [.none, .tab, .window, .allWindows, .visits] {
            XCTAssertFalse(Fire.BurningData.specificDomains([], closesTabs: false, scope: scope).usesWindowSnapshot)
        }
        for scope: Fire.BurningScope in [.none, .tab] {
            XCTAssertFalse(Fire.BurningData.specificDomains([], closesTabs: true, scope: scope).usesWindowSnapshot)
        }
    }

    @MainActor
    func testClearingWithoutClosingPreservesOriginalAnimationAndDialogDelayRules() {
        let decider = MockVisualizeFireAnimationDecider()
        for enabled in [true, false] {
            decider.shouldShowFireAnimation = enabled
            for scope: Fire.BurningScope in [.none, .tab, .window, .allWindows, .visits] {
                let burn = Fire.BurningData.specificDomains([], closesTabs: false, scope: scope)
                XCTAssertFalse(burn.shouldPlayFireAnimation(decider: decider))
                XCTAssertEqual(burn.shouldDelayShowingDialog(decider: decider), enabled)
            }
            XCTAssertEqual(Fire.BurningData.specificDomains([], closesTabs: true, scope: .tab)
                .shouldPlayFireAnimation(decider: decider), enabled)
        }
    }

    @MainActor
    func testSnapshotBurnClosesSourceAndShowsIndependentProgressBeforeFreshWindow() async throws {
        try await assertSnapshotClosingLifecycle(historyVisits: false)
    }

    @MainActor
    func testTodayHistoryWithCloseWindowsUsesSnapshotAndIndependentProgress() async throws {
        try await assertSnapshotClosingLifecycle(historyVisits: true)
    }

    @MainActor
    private func assertSnapshotClosingLifecycle(historyVisits: Bool) async throws {
        let cache = HeldSnapshotCache()
        let app = Application.appDelegate!
        let fire = Fire(cacheManager: cache,
                        historyCoordinating: HistoryCoordinatingMock(),
                        permissionManager: PermissionManagerMock(),
                        windowControllersManager: app.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: app.tld,
                        visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                        isAppActiveProvider: { true })
        let coordinator = FireCoordinator(tld: app.tld,
                                          featureFlagger: MockFeatureFlagger(),
                                          historyCoordinating: app.historyCoordinator,
                                          visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                                          onboardingContextualDialogsManager: nil,
                                          fireproofDomains: fire.fireproofDomains,
                                          faviconManagement: app.faviconManager,
                                          windowControllersManager: app.windowControllersManager,
                                          dataClearingPreferences: app.dataClearingPreferences,
                                          pixelFiring: nil,
                                          historyProvider: MockHistoryViewDataProvider(),
                                          fireViewModel: FireViewModel(fire: fire))
        let tab = Tab(content: .contentFromURL(URL(string: "data:,Snapshot%20source")!, source: .ui), shouldLoadInBackground: true)
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]), burnerMode: .regular)
        let source = try XCTUnwrap(WindowsManager.openNewWindow(with: collection, fireCoordinator: coordinator, burnerMode: .regular))
        let sourceController = try XCTUnwrap(source.windowController as? MainWindowController)
        let sourceFire = sourceController.mainViewController.fireViewController
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: source)
        // Simulate a pending legacy presentation from the previous burn. A snapshot must clear it
        // immediately rather than carry the legacy minimum-display timer into the new window.
        sourceFire.fireIndicatorVisibilityManager.updateVisibility(true)
        let clearing = expectation(description: "Cache cleanup is pending")
        let sourceClosed = expectationForClosing(source)
        let finished = expectation(description: "Whole-window burn finishes")
        cache.onClear = { clearing.fulfill() }
        if historyVisits {
            fire.burnVisits([], except: fire.fireproofDomains, isToday: true, closeWindows: true,
                            clearSiteData: true, clearChatHistory: false, urlToOpenIfWindowsAreClosed: nil,
                            dataClearingWideEventService: nil, completion: { finished.fulfill() })
        } else {
            fire.burnAll(includeChatHistory: false) {
                finished.fulfill()
            }
        }
        await fulfillment(of: [clearing, sourceClosed], timeout: 5)
        defer { cache.finish() }
        XCTAssertFalse(app.windowControllersManager.mainWindowControllers.contains(sourceController), "The captured browser must close, not remain hidden for reuse")
        XCTAssertFalse(source.isVisible)
        XCTAssertEqual(sourceFire.view.superview?.isHidden, true)
        try await Task.sleep(nanoseconds: 500_000_000)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.windowController is FireProgressWindowController })
        XCTAssertTrue(panel is NSPanel)
        XCTAssertNil(panel.parent)
        XCTAssertNil(panel.sheetParent)
        XCTAssertTrue(app.windowControllersManager.mainWindowControllers.isEmpty)
        cache.finish()
        await fulfillment(of: [finished], timeout: 5)
        try await Task.sleep(nanoseconds: 150_000_000)
        let fresh = try XCTUnwrap(app.windowControllersManager.mainWindowControllers.first)
        XCTAssertFalse(fresh === sourceController)
        XCTAssertFalse(fresh.window === source)
        XCTAssertEqual(fresh.mainViewController.fireViewController.view.superview?.isHidden, true, "The fresh window must not show the legacy burn overlay")
        // Finish editing in the fresh NTP before teardown closes its address-bar suggestions window.
        fresh.window?.makeFirstResponder(fresh.mainViewController.view)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor
    func testSnapshotCanImmediatelyDismissLegacyOverlayWithoutChangingLegacyMinimumDuration() {
        let overlay = NSView()
        let visibility = FireIndicatorVisibilityManager { overlay }
        visibility.updateVisibility(true)
        visibility.updateVisibility(false)
        XCTAssertFalse(overlay.isHidden, "Legacy progress still keeps its minimum display duration")
        visibility.hideImmediately()
        XCTAssertTrue(overlay.isHidden, "Snapshot progress must never reuse the legacy overlay")
    }

    @MainActor
    func testSnapshotShadowFrameIsNotConstrainedToEachDisplayVisibleArea() {
        for screen in NSScreen.screens {
            for topGap: CGFloat in [0, 30, 150] {
                let source = NSRect(x: screen.visibleFrame.minX + 100,
                                    y: screen.visibleFrame.maxY - 400 - topGap,
                                    width: 700, height: 400)
                let frame = source.insetBy(dx: -80, dy: -80)
                let snapshot = FireWindowAnimationController.SnapshotWindow(contentRect: frame, styleMask: .borderless,
                                                                           backing: .buffered, defer: false)
                snapshot.isReleasedWhenClosed = false
                defer { snapshot.close() }
                XCTAssertEqual(snapshot.constrainFrameRect(frame, to: screen), frame,
                               "The captured shadow must not shift the image down on \(screen.localizedName)")
            }
        }
    }

    @MainActor
    func testWhenFirePopoverCloseButtonClicked_thenFireAnimationPlaysAndWindowCloses() async throws {
        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        // Not going through `FireCoordinator.showFirePopover`: it holds the popover for the app's lifetime,
        // so the popover's views would outlive the test and trip the harness' deallocation checks.
        let popoverViewController = FirePopoverViewController(
            fireViewModel: windowController.mainViewController.fireViewController.fireViewModel,
            tabCollectionViewModel: windowController.mainViewController.tabCollectionViewModel
        )

        let windowClosed = expectationForClosing(window)
        popoverViewController.closeBurnerWindowButtonAction(self)
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [true, false])
    }

    @MainActor
    func testWhenLastTabOfFireWindowClosed_thenFireAnimationPlaysAndWindowCloses() async throws {
        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        let windowClosed = expectationForClosing(window)
        windowController.mainViewController.tabCollectionViewModel.remove(at: .unpinned(0))
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [true, false])
    }

    @MainActor
    func testWhenFireAnimationDisabled_thenFireWindowClosesWithoutAnimating() async throws {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = false

        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        let windowClosed = expectationForClosing(window)
        windowController.burnAndClose(window)
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [])
    }

    // MARK: - Helpers

    private func expectationForClosing(_ window: NSWindow) -> XCTestExpectation {
        // Notification expectations retain their observed object. Avoid keeping the closed window
        // and its view hierarchy alive while the harness checks deallocation at teardown.
        expectation(forNotification: NSWindow.willCloseNotification, object: nil) { [weak window] notification in
            guard let window else { return false }
            return notification.object as? NSWindow === window
        }
    }

    @MainActor
    private func openFireWindow() throws -> MainWindowController {
        // `showWindow: false` would still open a window, but not activate it, which seems to upset CI
        _=WindowsManager.openNewWindow(with: URL(string: "data:,Hello%2C%20World%21")!, source: .ui, isBurner: true)
        let windowController = try XCTUnwrap(Application.appDelegate.windowControllersManager.mainWindowControllers.last)
        XCTAssertTrue(windowController.mainViewController.tabCollectionViewModel.isBurner)
        return windowController
    }

    @MainActor
    private func subscribeToAnimationStates(of windowController: MainWindowController, onChange: @escaping (Bool) -> Void) {
        windowController.mainViewController.fireViewController.fireViewModel.$isAnimationPlaying
            .dropFirst()
            .sink { onChange($0) }
            .store(in: &cancellables)
    }
}

private final class HeldSnapshotCache: WebCacheManager {
    @MainActor var onClear: (() -> Void)?
    @MainActor private var continuation: CheckedContinuation<Void, Never>?

    init() {
        super.init(fireproofDomains: MockFireproofDomains())
    }

    override func clear(baseDomains: Set<String>? = nil, dataClearingWideEventService: DataClearingWideEventService? = nil) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.continuation = continuation
                onClear?()
            }
        }
    }

    @MainActor
    func finish() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
