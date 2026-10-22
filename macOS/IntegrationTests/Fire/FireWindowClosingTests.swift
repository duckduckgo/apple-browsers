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
import SharedTestUtilities
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Test runs skip visual playback while preserving animation state and presentation routing.
final class FireWindowClosingTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    private var initialFireAnimationEnabled = true
    private var initialOpenFireWindowByDefault = false

    @MainActor
    override func setUp() {
        initialFireAnimationEnabled = Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled
        initialOpenFireWindowByDefault = Application.appDelegate.dataClearingPreferences.shouldOpenFireWindowByDefault
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = true
        Application.appDelegate.dataClearingPreferences.shouldOpenFireWindowByDefault = false
    }

    @MainActor
    override func tearDown() {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = initialFireAnimationEnabled
        Application.appDelegate.dataClearingPreferences.shouldOpenFireWindowByDefault = initialOpenFireWindowByDefault
        cancellables = []
        autoreleasepool {
            WindowsManager.closeWindows()
            for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
                Application.appDelegate.windowControllersManager.unregister(controller)
            }
        }
        // Allow WebKit IPC to settle after closing windows
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        let progressDeadline = Date(timeIntervalSinceNow: 3)
        while hasVisibleProgressWindow(), Date() < progressDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertFalse(hasVisibleProgressWindow(), "The independent progress window must close after cleanup")
        // AppKit retains the last event's window. Process a windowless event before checking deallocation.
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        NSApp.postEvent(event, atStart: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    // MARK: - Tests

    @MainActor
    func testWhenWindowMovesBetweenDisplays_thenSnapshotPreservesPositionIncludingShadow() throws {
        let controller = try openWindow(isBurner: false)
        let window = try XCTUnwrap(controller.window)
        window.animationBehavior = .none

        // Show the same window on every attached display, including displays with negative origins.
        // Near the menu bar, the shadow padding extends outside the visible area and must not
        // cause AppKit to move the captured window's contents down when ordering the snapshot in.
        for screen in NSScreen.screens {
            for topGap: CGFloat in [0, 30, 150] {
                let frame = NSRect(x: screen.visibleFrame.minX + 100,
                                   y: screen.visibleFrame.maxY - 400 - topGap,
                                   width: 700, height: 400)
                window.setFrame(frame, display: true)
                window.orderFront(nil)
                window.displayIfNeeded()
                let expectedSnapshotFrame = window.frame.insetBy(dx: -80, dy: -80)
                let presentation = try XCTUnwrap(FireWindowAnimationController(sourceWindow: window))
                defer { presentation.start {} }
                let snapshot = try XCTUnwrap(presentation.window)

                XCTAssertEqual(snapshot.frame, expectedSnapshotFrame, "Display: \(screen.localizedName), top gap: \(topGap)")
                XCTAssertEqual(snapshot.constrainFrameRect(expectedSnapshotFrame, to: screen), expectedSnapshotFrame)
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

    @MainActor
    func testWhenOneOfTwoTabsBurned_thenOriginalAnimationKeepsWindowVisible() async throws {
        let controller = try openWindow(isBurner: false)
        let collection = controller.mainViewController.tabCollectionViewModel
        collection.append(tab: Tab(content: .newtab, burnerMode: collection.burnerMode), selected: true)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: true, windowRemainsOpen: true)
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    @MainActor
    func testWhenLastRegularTabIsReplaced_thenOriginalAnimationKeepsWindowVisible() async throws {
        let controller = try openWindow(isBurner: false)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: true, windowRemainsOpen: true)
        XCTAssertEqual(controller.mainViewController.tabCollectionViewModel.tabCollection.tabs.first?.content, .newtab)
    }

    @MainActor
    func testWhenLastTabOfFireWindowBurned_thenSnapshotAnimationClosesWindow() async throws {
        let controller = try openFireWindow()
        try await assertTabBurnPresentation(in: controller, animatesInPlace: false, windowRemainsOpen: false)
    }

    @MainActor
    func testWhenLastRegularTabBurnedAndAnotherWindowExists_thenSnapshotAnimationClosesWindow() async throws {
        _ = try openWindow(isBurner: false)
        let controller = try openWindow(isBurner: false)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: false, windowRemainsOpen: false)
    }

    @MainActor
    func testWhenTabBurnDoesNotCloseTabs_thenOriginalAnimationKeepsTabAndWindowVisible() async throws {
        let controller = try openWindow(isBurner: false)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: true, windowRemainsOpen: true, close: false)
    }

    @MainActor
    func testWhenWindowBurnDoesNotCloseTabs_thenOriginalAnimationKeepsTabsAndWindowVisible() async throws {
        let controller = try openWindow(isBurner: false)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: true, windowRemainsOpen: true, close: false, scope: .window)
    }

    @MainActor
    func testWhenAllWindowsBurnDoesNotCloseTabs_thenOriginalAnimationKeepsTabsAndWindowVisible() async throws {
        let controller = try openWindow(isBurner: false)
        try await assertTabBurnPresentation(in: controller, animatesInPlace: true, windowRemainsOpen: true, close: false, scope: .allWindows)
    }

    @MainActor
    func testWhenAnimationFinishesBeforeCleanup_thenPresentationIsClaimedUntilTheNextBurn() {
        let fire = FireMock()
        let model = FireViewModel(fire: fire)
        fire.publishBurningData(.all)
        XCTAssertTrue(model.claimFirePresentation())
        model.setAnimationPlaying(true, isFireWindow: false)
        model.setAnimationPlaying(false, isFireWindow: false)
        XCTAssertFalse(model.claimFirePresentation(), "Changing key windows must not restart this burn's animation")
        fire.publishBurningData(nil)
        fire.publishBurningData(.all)
        XCTAssertTrue(model.claimFirePresentation(), "The following burn must be able to present its own animation")
        fire.publishBurningData(nil)
    }

    @MainActor
    func testWhenHiddenWindowsShareFireModel_thenOnlyOneAnimationPlaysAndEmptyWindowCloses() async throws {
        let app = Application.appDelegate!
        let preparer = ControlledTabCleanupPreparer()
        let fire = Fire(cacheManager: WebCacheManagerMock(), windowControllersManager: app.windowControllersManager,
                        tld: app.tld, visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                        isAppActiveProvider: { true }, tabCleanupPreparer: preparer)
        let model = FireViewModel(fire: fire)
        let first = try openWindow(isBurner: false, testFireViewModel: model)
        let second = try openWindow(isBurner: false, testFireViewModel: model)
        let firstWindow = try XCTUnwrap(first.window)
        let secondWindow = try XCTUnwrap(second.window)
        firstWindow.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: firstWindow)
        // Ordering out a snapshot source cancels the browser's visible-view subscriptions.
        first.mainViewController.browserTabViewController.viewWillDisappear()
        var animationStarts = 0
        model.$isAnimationPlaying.dropFirst().sink { playing in
            if playing {
                animationStarts += 1
            } else {
                // Test playback completes synchronously while burningData is still being broadcast.
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: secondWindow)
            }
        }.store(in: &cancellables)
        let preparing = expectation(description: "The shared burn is preparing its tab")
        let completed = expectation(description: "The shared burn completes")
        preparer.onPrepare = { preparing.fulfill() }
        let collection = first.mainViewController.tabCollectionViewModel
        let target = try XCTUnwrap(collection.selectedTabViewModel)
        fire.burnEntity(.tab(tabViewModel: target, selectedDomains: [], parentTabCollectionViewModel: collection, close: true),
                        includingHistory: false, includeCookiesAndSiteData: false, includeChatHistory: false,
                        dataClearingWideEventService: nil, completion: { completed.fulfill() })
        await fulfillment(of: [preparing], timeout: 5)
        defer { preparer.finish() }
        XCTAssertEqual(animationStarts, 1)
        XCTAssertFalse(model.claimFirePresentation())
        preparer.finish()
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(animationStarts, 1)
        XCTAssertFalse(app.windowControllersManager.mainWindowControllers.contains(first))
        XCTAssertTrue(secondWindow.isVisible)
    }

    @MainActor
    func testWhenFireWindowAnimationIsPlaying_thenAnotherWindowStillPresentsItsBurn() async throws {
        let app = Application.appDelegate!
        let fire = Fire(cacheManager: WebCacheManagerMock(), windowControllersManager: app.windowControllersManager,
                        tld: app.tld, visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                        isAppActiveProvider: { true })
        let model = FireViewModel(fire: fire)
        let controller = try openWindow(isBurner: false, testFireViewModel: model)
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        let collection = controller.mainViewController.tabCollectionViewModel
        let target = try XCTUnwrap(collection.selectedTabViewModel)
        var inPlaceStates = [Bool]()
        controller.mainViewController.fireViewController.$isAnimatingInPlace.dropFirst()
            .sink { inPlaceStates.append($0) }.store(in: &cancellables)
        // A closed Fire Window's snapshot keeps playing while the other window is usable.
        model.setAnimationPlaying(true, isFireWindow: true)
        defer { model.setAnimationPlaying(false, isFireWindow: true) }
        XCTAssertTrue(controller.mainViewController.tabBarViewController.fireButton.isEnabled)
        let completed = expectation(description: "The overlapping data burn completes")
        fire.burnEntity(.tab(tabViewModel: target, selectedDomains: [], parentTabCollectionViewModel: collection, close: false),
                        includingHistory: false, includeCookiesAndSiteData: false, includeChatHistory: false,
                        dataClearingWideEventService: nil, completion: { completed.fulfill() })
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(inPlaceStates, [true, false], "A closing Fire Window must not suppress another window's fire")
        XCTAssertTrue(model.isAnimationPlaying, "The independent closing snapshot is still playing")
    }

    @MainActor
    func testWhenFireWindowAnimationsOverlap_thenEachCompletionPreservesOtherAnimations() {
        let fire = FireMock()
        fire.publishBurningData(nil)
        let model = FireViewModel(fire: fire)
        var states = [Bool]()
        model.$isAnimationPlaying.dropFirst().sink { states.append($0) }.store(in: &cancellables)
        model.setAnimationPlaying(true, isFireWindow: true)
        model.setAnimationPlaying(true, isFireWindow: true)
        model.setAnimationPlaying(false, isFireWindow: true)
        XCTAssertTrue(model.isAnimationPlaying, "The second closing snapshot is still playing")
        model.setAnimationPlaying(true, isFireWindow: false)
        model.setAnimationPlaying(false, isFireWindow: true)
        XCTAssertTrue(model.isAnimationPlaying, "The data-clearing animation is still playing")
        XCTAssertTrue(model.isDataClearingAnimationPlaying)
        model.setAnimationPlaying(false, isFireWindow: false)
        XCTAssertFalse(model.isAnimationPlaying)
        XCTAssertFalse(model.isDataClearingAnimationPlaying)
        XCTAssertEqual(states, [true, false])
    }

    @MainActor
    func testWhenAnotherWindowIsClosing_thenProgressForANonAnimatedBurnStillAppears() async throws {
        let controller = try openWindow(isBurner: false)
        let source = try XCTUnwrap(controller.window)
        let fire = FireMock()
        let model = FireViewModel(fire: fire)
        fire.publishBurningData(.specificDomains([], closesTabs: false, scope: .none))
        model.setAnimationPlaying(true, isFireWindow: true)
        defer {
            model.setAnimationPlaying(false, isFireWindow: true)
            fire.publishBurningData(nil)
        }
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "Cleanup", sourceWindow: source, delay: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(progress.window?.isVisible == true, "An independent closing snapshot must not suppress this burn's progress")
    }

    @MainActor
    func testWhenBadgeFadeIsCancelled_thenContainerIsReleasedBeforeDelayedCompletion() {
        let animator = NavigationBarBadgeAnimator()
        let buttons = NSView()
        weak var releasedBadge: NavigationBarBadgeAnimationView?
        autoreleasepool {
            let badge = NavigationBarBadgeAnimationView()
            releasedBadge = badge
            animator.showNotification(withType: .cookiePopupManaged, buttonsContainer: buttons,
                                      notificationBadgeContainer: badge)
            animator.cancelPendingAnimations()
        }
        XCTAssertNil(releasedBadge, "A queued completion must not keep a closed window's badge alive")
    }

    @MainActor
    func testWhenWindowOpensDuringBurn_thenItsContentIsBlockedUntilBurnEnds() throws {
        let fire = FireMock()
        fire.publishBurningData(.all)
        let controller = try openWindow(isBurner: false, testFire: fire)
        let main = controller.mainViewController
        XCTAssertFalse(main.allowsUserInteraction)
        XCTAssertFalse(main.tabCollectionViewModel.changesEnabled)
        XCTAssertEqual(main.fireViewController.view.superview?.isHidden, false)
        fire.publishBurningData(nil)
        XCTAssertTrue(main.allowsUserInteraction)
        XCTAssertTrue(main.tabCollectionViewModel.changesEnabled)
        XCTAssertEqual(main.fireViewController.view.superview?.isHidden, true)
    }

    @MainActor
    func testWhenExternalSelectionChangesDuringBurn_thenAllContentLocksAreRestored() throws {
        let fire = FireMock()
        let controller = try openWindow(isBurner: false, testFire: fire)
        let collection = controller.mainViewController.tabCollectionViewModel
        let first = try XCTUnwrap(collection.selectedTabViewModel?.tab)
        collection.append(tab: Tab(content: .newtab, burnerMode: collection.burnerMode), selected: true)
        let second = try XCTUnwrap(collection.selectedTabViewModel?.tab)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: controller.window)
        fire.publishBurningData(.specificDomains([], closesTabs: false, scope: .tab))
        XCTAssertFalse(second.contentChangeEnabled)
        collection.select(at: .unpinned(0), forceChange: true)
        XCTAssertFalse(first.contentChangeEnabled)
        controller.userInteraction(prevented: true)
        fire.publishBurningData(nil)
        XCTAssertFalse(controller.mainViewController.allowsUserInteraction)
        controller.userInteraction(prevented: false)
        XCTAssertTrue(first.contentChangeEnabled)
        XCTAssertTrue(second.contentChangeEnabled)
        XCTAssertTrue(collection.changesEnabled)
    }

    @MainActor
    func testWhenWindowWasNotClosableBeforeBurn_thenItsOriginalStateIsPreserved() throws {
        let fire = FireMock()
        let controller = try openWindow(isBurner: false, testFire: fire)
        let window = try XCTUnwrap(controller.window)
        let tab = try XCTUnwrap(controller.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab)
        window.styleMask.remove(.closable)
        tab.contentChangeEnabled = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        fire.publishBurningData(.specificDomains([], closesTabs: false, scope: .tab))
        fire.publishBurningData(nil)
        XCTAssertFalse(window.styleMask.contains(.closable))
        XCTAssertFalse(tab.contentChangeEnabled)
    }

    @MainActor
    func testWhenPreparationOutlastsAnimation_thenInputStaysBlockedAndOriginalTabIsBurned() async throws {
        try await assertSlowTabBurn(animationEnabled: true, targetRemoved: false)
    }

    @MainActor
    func testWhenAnimationDisabled_thenInputStaysBlockedUntilCleanupCompletes() async throws {
        try await assertSlowTabBurn(animationEnabled: false, targetRemoved: false)
    }

    @MainActor
    func testWhenBurnedTabIsRemovedDuringPreparation_thenAnotherTabIsNotClosed() async throws {
        try await assertSlowTabBurn(animationEnabled: true, targetRemoved: true)
    }

    @MainActor
    func testWhenAnotherBurnStarts_thenOldProgressCannotRestoreItsWindow() async throws {
        let controller = try openWindow(isBurner: false)
        let source = try XCTUnwrap(controller.window)
        let fire = FireMock()
        let model = FireViewModel(fire: fire)
        fire.publishBurningData(.all)
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "Cleanup", sourceWindow: source, delay: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(progress.window?.isVisible == true)
        fire.publishBurningData(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        fire.publishBurningData(.all)
        source.orderOut(nil)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertFalse(source.isVisible, "A previous burn's delayed dismissal must not reveal the current burn's source")
        XCTAssertNil(progress.window)
        fire.publishBurningData(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(source.isVisible, "Following the new burn must not leave its source hidden forever")
    }

    @MainActor
    func testWhenProgressIsReplaced_thenHiddenSourcesAreRestoredWithoutStealingWindowOrder() async throws {
        let firstController = try openWindow(isBurner: false)
        let first = try XCTUnwrap(firstController.window)
        let secondController = try openWindow(isBurner: false)
        let second = try XCTUnwrap(secondController.window)
        let otherController = try openWindow(isBurner: false)
        let other = try XCTUnwrap(otherController.window)
        let fire = FireMock()
        let model = FireViewModel(fire: fire)
        fire.publishBurningData(.all)
        let old = FireProgressWindowController.present(fireViewModel: model, message: "First", sourceWindow: first, delay: 0)
        first.orderOut(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        fire.publishBurningData(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        fire.publishBurningData(.all)
        let current = FireProgressWindowController.present(fireViewModel: model, message: "Second", sourceWindow: second, delay: 0)
        second.orderOut(nil)
        other.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertNil(old.window)
        XCTAssertFalse(first.isVisible)
        XCTAssertFalse(second.isVisible)
        let keyBefore = NSApp.keyWindow
        fire.publishBurningData(nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(current.window)
        XCTAssertTrue(first.isVisible)
        XCTAssertTrue(second.isVisible)
        if keyBefore === other {
            XCTAssertTrue(NSApp.keyWindow === other, "Restoration must not take focus from another window")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func assertSlowTabBurn(animationEnabled: Bool, targetRemoved: Bool) async throws {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = animationEnabled
        let preparer = ControlledTabCleanupPreparer()
        let controller = try openWindow(isBurner: false, tabCleanupPreparer: preparer)
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        let collection = controller.mainViewController.tabCollectionViewModel
        let retained = try XCTUnwrap(collection.selectedTabViewModel?.tab)
        collection.append(tab: Tab(content: .newtab, burnerMode: collection.burnerMode), selected: true)
        let target = try XCTUnwrap(collection.selectedTabViewModel)
        let preparing = expectation(description: "Preparation is suspended")
        let completed = expectation(description: "Cleanup completes")
        preparer.onPrepare = { preparing.fulfill() }
        let fireController = controller.mainViewController.fireViewController
        fireController.fireViewModel.fire.burnEntity(
            .tab(tabViewModel: target, selectedDomains: [], parentTabCollectionViewModel: collection, close: true),
            includingHistory: false, includeCookiesAndSiteData: false, includeChatHistory: false,
            dataClearingWideEventService: nil, completion: { completed.fulfill() }
        )
        await fulfillment(of: [preparing], timeout: 5)
        defer { preparer.finish() }
        XCTAssertFalse(fireController.fireViewModel.isAnimationPlaying, "Test playback has finished but preparation is still suspended")
        XCTAssertFalse(controller.mainViewController.allowsUserInteraction)
        XCTAssertFalse(collection.changesEnabled)
        XCTAssertFalse(window.styleMask.contains(.closable))
        XCTAssertEqual(fireController.view.superview?.isHidden, false)
        collection.select(at: .unpinned(0))
        XCTAssertTrue(collection.selectedTabViewModel === target)
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(MainViewController.newTab(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.mainViewController.validateMenuItem(newTabItem))
        // External requests can force a selection or remove the target even while user input is locked.
        if targetRemoved {
            collection.close(at: .unpinned(1), forceChange: true)
        } else {
            collection.select(at: .unpinned(0), forceChange: true)
        }
        controller.userInteraction(prevented: true)
        preparer.finish()
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
        XCTAssertTrue(collection.selectedTabViewModel?.tab === retained)
        XCTAssertFalse(controller.mainViewController.allowsUserInteraction, "Burn completion must preserve an independent interaction lock")
        controller.userInteraction(prevented: false)
        XCTAssertTrue(controller.mainViewController.allowsUserInteraction)
        XCTAssertTrue(collection.changesEnabled)
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertEqual(fireController.view.superview?.isHidden, true)
    }

    @MainActor
    private func hasVisibleProgressWindow() -> Bool {
        autoreleasepool {
            NSApp.windows.contains { $0.isVisible && $0.windowController is FireProgressWindowController }
        }
    }

    @MainActor
    private func assertTabBurnPresentation(in controller: MainWindowController,
                                           animatesInPlace: Bool,
                                           windowRemainsOpen: Bool,
                                           close: Bool = true,
                                           scope: Fire.BurningScope = .tab) async throws {
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        // The background XCTest host may not receive native key-window events.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertTrue(Application.appDelegate.windowControllersManager.lastKeyMainWindowController === controller)
        let fireController = controller.mainViewController.fireViewController
        let collection = controller.mainViewController.tabCollectionViewModel
        let tab = try XCTUnwrap(collection.selectedTabViewModel)
        let burned = expectation(description: "Tab burn completes")
        var presentations = [Bool]()
        var windowVisibility = [Bool]()
        fireController.fireViewModel.$isAnimationPlaying.dropFirst().sink { [weak window, weak fireController] playing in
            guard playing, let window, let fireController else { return }
            presentations.append(fireController.isAnimatingInPlace)
            windowVisibility.append(window.isVisible)
        }.store(in: &cancellables)

        let entity: Fire.BurningEntity
        switch scope {
        case .window:
            entity = .window(tabCollectionViewModel: collection, selectedDomains: [], close: close)
        case .allWindows:
            entity = .allWindows(mainWindowControllers: [controller], selectedDomains: [], customURLToOpen: nil, close: close)
        default:
            entity = .tab(tabViewModel: tab, selectedDomains: [], parentTabCollectionViewModel: collection, close: close)
        }
        fireController.fireViewModel.fire.burnEntity(
            entity,
            includingHistory: false,
            includeCookiesAndSiteData: false,
            includeChatHistory: false,
            dataClearingWideEventService: nil,
            completion: { burned.fulfill() }
        )
        await fulfillment(of: [burned], timeout: 10)
        XCTAssertEqual(presentations, [animatesInPlace])
        if animatesInPlace {
            XCTAssertEqual(windowVisibility, [true], "The original window must stay visible throughout an in-place animation")
        }
        XCTAssertFalse(fireController.isAnimatingInPlace)
        XCTAssertFalse(fireController.fireViewModel.isAnimationPlaying)
        if !close {
            XCTAssertTrue(collection.selectedTabViewModel === tab, "Clearing data without closing tabs must preserve the original tab")
            XCTAssertTrue(window.isVisible)
        }
        XCTAssertEqual(Application.appDelegate.windowControllersManager.mainWindowControllers.contains(controller), windowRemainsOpen)
    }

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
        try openWindow(isBurner: true)
    }

    @MainActor
    private func openWindow(isBurner: Bool,
                            tabCleanupPreparer: TabCleanupPreparing = TabCleanupPreparer(),
                            testFire: FireProtocol? = nil,
                            testFireViewModel: FireViewModel? = nil) throws -> MainWindowController {
        let app = Application.appDelegate!
        let fire = testFire ?? testFireViewModel?.fire ?? Fire(cacheManager: WebCacheManagerMock(),
                        windowControllersManager: app.windowControllersManager,
                        tld: app.tld,
                        visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                        isAppActiveProvider: { true },
                        tabCleanupPreparer: tabCleanupPreparer)
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
                                          fireViewModel: testFireViewModel ?? FireViewModel(fire: fire))
        let mode = BurnerMode(isBurner: isBurner)
        let tab = Tab(content: .contentFromURL(URL(string: "data:,Hello%2C%20World%21")!, source: .ui),
                      shouldLoadInBackground: true, burnerMode: mode)
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]), burnerMode: mode)
        _=WindowsManager.openNewWindow(with: collection, fireCoordinator: coordinator, burnerMode: mode)
        let controller = try XCTUnwrap(Application.appDelegate.windowControllersManager.mainWindowControllers.last)
        XCTAssertEqual(controller.mainViewController.tabCollectionViewModel.isBurner, isBurner)
        return controller
    }

    @MainActor
    private func subscribeToAnimationStates(of windowController: MainWindowController, onChange: @escaping (Bool) -> Void) {
        windowController.mainViewController.fireViewController.fireViewModel.$isAnimationPlaying
            .dropFirst()
            .sink { onChange($0) }
            .store(in: &cancellables)
    }
}

@MainActor
private final class ControlledTabCleanupPreparer: TabCleanupPreparing {
    var onPrepare: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func prepareTabsForCleanup(_ tabs: [any TabDataClearing]) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onPrepare?()
        }
    }

    func finish() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
