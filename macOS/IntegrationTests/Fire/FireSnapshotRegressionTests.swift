//
//  FireSnapshotRegressionTests.swift
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
import FeatureFlags_macOS
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FireSnapshotRegressionTests: XCTestCase {
    private var originalFlag: Bool?
    private var originalPinnedMode: PinnedTabsMode!
    private var originalAnimationEnabled = true

    @MainActor private var app: AppDelegate { Application.appDelegate }
    @MainActor private var flagger: MockFeatureFlagger { app.featureFlagger as! MockFeatureFlagger }

    @MainActor
    override func setUp() {
        originalFlag = flagger.featuresStub[FeatureFlag.fireWindowSnapshotAnimation.rawValue]
        originalPinnedMode = app.tabsPreferences.pinnedTabsMode
        originalAnimationEnabled = app.dataClearingPreferences.isFireAnimationEnabled
        app.dataClearingPreferences.isFireAnimationEnabled = true
        app.tabsPreferences.pinnedTabsMode = .separate
    }

    @MainActor
    override func tearDown() {
        for manager in app.pinnedTabsManagerProvider.currentPinnedTabManagers {
            manager.tabCollection.removeAll()
        }
        WindowsManager.closeWindows()
        for controller in app.windowControllersManager.mainWindowControllers {
            app.windowControllersManager.unregister(controller)
        }
        app.tabsPreferences.pinnedTabsMode = originalPinnedMode
        app.dataClearingPreferences.isFireAnimationEnabled = originalAnimationEnabled
        flagger.featuresStub[FeatureFlag.fireWindowSnapshotAnimation.rawValue] = originalFlag
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        NSApp.postEvent(event, atStart: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    @MainActor
    func testBurnAllPreservesSeparatePinnedWindowsWithSnapshotEnabled() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: true, currentWindowOnly: false)
    }

    @MainActor
    func testBurnAllPreservesSeparatePinnedWindowsWithSnapshotDisabled() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: false, currentWindowOnly: false)
    }

    @MainActor
    func testCurrentWindowBurnPreservesSeparatePinnedTabsWithSnapshotEnabled() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: true, currentWindowOnly: true)
    }

    @MainActor
    func testCurrentWindowBurnPreservesSeparatePinnedTabsWithSnapshotDisabled() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: false, currentWindowOnly: true)
    }

    @MainActor
    func testSinglePinnedWindowSurvivesSnapshotBurnAll() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: true, currentWindowOnly: false, windowCount: 1)
    }

    @MainActor
    func testSinglePinnedWindowSurvivesLegacyBurnAll() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: false, currentWindowOnly: false, windowCount: 1)
    }

    @MainActor
    func testSinglePinnedWindowSurvivesSnapshotWindowBurn() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: true, currentWindowOnly: true, windowCount: 1)
    }

    @MainActor
    func testSinglePinnedWindowSurvivesLegacyWindowBurn() async throws {
        try await assertPinnedWindowsSurvive(snapshotEnabled: false, currentWindowOnly: true, windowCount: 1)
    }

    @MainActor
    func testSharedPinnedTabsSurviveSnapshotBurn() async throws {
        try await assertSharedPinsSurvive(snapshotEnabled: true)
    }

    @MainActor
    func testSharedPinnedTabsSurviveLegacyBurn() async throws {
        try await assertSharedPinsSurvive(snapshotEnabled: false)
    }

    @MainActor
    private func assertSharedPinsSurvive(snapshotEnabled: Bool) async throws {
        app.tabsPreferences.pinnedTabsMode = .shared
        let fixture = makeFixture(snapshotEnabled: snapshotEnabled)
        let first = try openWindow(coordinator: fixture.coordinator, title: "First shared window")
        let source = try openWindow(coordinator: fixture.coordinator, title: "Second shared window")
        let url = URL(string: "data:,SharedPinned")!
        let pin = Tab(content: .contentFromURL(url, source: .ui), shouldLoadInBackground: true)
        XCTAssertTrue(try XCTUnwrap(first.mainViewController.tabCollectionViewModel.pinnedTabsManager).pinTab(pin, from: nil, firePixel: false))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: source.window!)
        let clearing = expectation(description: "Shared-pin cleanup is held")
        let finished = expectation(description: "Shared-pin burn finishes")
        fixture.cache.onClear = { clearing.fulfill() }
        fixture.fire.burnAll(includeChatHistory: false) { finished.fulfill() }
        await fulfillment(of: [clearing], timeout: 5)
        fixture.cache.finish()
        await fulfillment(of: [finished], timeout: 5)
        try await Task.sleep(nanoseconds: 150_000_000)
        for controller in app.windowControllersManager.mainWindowControllers {
            controller.window?.makeFirstResponder(controller.mainViewController.view)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let managers = app.pinnedTabsManagerProvider.currentPinnedTabManagers
        XCTAssertEqual(managers.count, 1)
        XCTAssertEqual(managers.first?.tabCollection.tabs.map(\.content.userEditableUrl), [url])
        XCTAssertFalse(app.windowControllersManager.mainWindowControllers.isEmpty)
    }

    @MainActor
    private func assertPinnedWindowsSurvive(snapshotEnabled: Bool, currentWindowOnly: Bool, windowCount: Int = 2) async throws {
        let fixture = makeFixture(snapshotEnabled: snapshotEnabled)
        let controllers = try (0..<windowCount).map { try openWindow(coordinator: fixture.coordinator, title: "Window \($0)") }
        let source = try XCTUnwrap(controllers.last)
        let urls = (0..<windowCount).map { URL(string: "data:,Pinned\($0)")! }
        for (controller, url) in zip(controllers, urls) {
            let tab = Tab(content: .contentFromURL(url, source: .ui), shouldLoadInBackground: true)
            XCTAssertTrue(try XCTUnwrap(controller.mainViewController.tabCollectionViewModel.pinnedTabsManager)
                .pinTab(tab, from: nil, firePixel: false))
        }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: source.window!)
        let clearing = expectation(description: "Cleanup is held")
        let finished = expectation(description: "Burn finishes")
        fixture.cache.onClear = { clearing.fulfill() }
        if currentWindowOnly {
            fixture.fire.burnEntity(.window(tabCollectionViewModel: source.mainViewController.tabCollectionViewModel,
                                            selectedDomains: [], close: true),
                                    includingHistory: false, includeCookiesAndSiteData: true, includeChatHistory: false,
                                    dataClearingWideEventService: nil) { finished.fulfill() }
        } else {
            fixture.fire.burnAll(includeChatHistory: false) { finished.fulfill() }
        }
        await fulfillment(of: [clearing], timeout: 5)
        fixture.cache.finish()
        await fulfillment(of: [finished], timeout: 5)
        try await Task.sleep(nanoseconds: 150_000_000)
        for controller in app.windowControllersManager.mainWindowControllers {
            controller.window?.makeFirstResponder(controller.mainViewController.view)
        }
        for (controller, url) in zip(controllers, urls) {
            XCTAssertTrue(app.windowControllersManager.mainWindowControllers.contains(controller),
                          "Per-window pinned tabs must retain their owning window")
            XCTAssertTrue(controller.window?.isVisible == true)
            XCTAssertEqual(controller.mainViewController.tabCollectionViewModel.pinnedTabs.map(\.content.userEditableUrl), [url])
            XCTAssertEqual(controller.mainViewController.tabCollectionViewModel.tabCollection.tabs.isEmpty,
                           !currentWindowOnly || controller === source)
        }
    }

    @MainActor
    func testSurvivingWindowBlocksInputWhileSnapshotCleanupIsPending() async throws {
        try await assertSurvivingWindowBlocksInput(snapshotEnabled: true)
    }

    @MainActor
    func testSurvivingWindowBlocksInputWhileLegacyCleanupIsPending() async throws {
        try await assertSurvivingWindowBlocksInput(snapshotEnabled: false)
    }

    @MainActor
    private func assertSurvivingWindowBlocksInput(snapshotEnabled: Bool) async throws {
        let fixture = makeFixture(snapshotEnabled: snapshotEnabled)
        let survivor = try openWindow(coordinator: fixture.coordinator, title: "Survivor")
        let source = try openWindow(coordinator: fixture.coordinator, title: "Source")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: source.window!)
        let clearing = expectation(description: "Cleanup is held")
        let finished = expectation(description: "Burn finishes")
        fixture.cache.onClear = { clearing.fulfill() }
        fixture.fire.burnEntity(.window(tabCollectionViewModel: source.mainViewController.tabCollectionViewModel,
                                        selectedDomains: [], close: true),
                                includingHistory: false, includeCookiesAndSiteData: true, includeChatHistory: false,
                                dataClearingWideEventService: nil) { finished.fulfill() }
        await fulfillment(of: [clearing], timeout: 5)
        defer { fixture.cache.finish() }
        try await Task.sleep(nanoseconds: 250_000_000)
        let blocker = try XCTUnwrap(survivor.mainViewController.fireViewController.view.superview)
        XCTAssertFalse(blocker.isHidden, "A surviving window must intercept clicks throughout cleanup")
        fixture.cache.finish()
        await fulfillment(of: [finished], timeout: 5)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(blocker.isHidden, "Input must be restored when cleanup finishes")
    }

    @MainActor
    func testTabBurnKeepsOtherTabsAndUsesNoSnapshotForBothFlagStates() async throws {
        for enabled in [false, true] {
            let fixture = makeFixture(snapshotEnabled: enabled)
            let source = try openWindow(coordinator: fixture.coordinator, title: "Tab source")
            let collection = source.mainViewController.tabCollectionViewModel
            let other = Tab(content: .contentFromURL(URL(string: "data:,Other")!, source: .ui), shouldLoadInBackground: true)
            collection.append(tab: other, selected: false, forceChange: true)
            let selected = try XCTUnwrap(collection.selectedTabViewModel)
            let clearing = expectation(description: "Tab cleanup is held")
            let finished = expectation(description: "Tab burn finishes")
            fixture.cache.onClear = { clearing.fulfill() }
            fixture.fire.burnEntity(.tab(tabViewModel: selected, selectedDomains: [], parentTabCollectionViewModel: collection, close: true),
                                    includingHistory: false, includeCookiesAndSiteData: true, includeChatHistory: false,
                                    dataClearingWideEventService: nil) { finished.fulfill() }
            await fulfillment(of: [clearing], timeout: 5)
            XCTAssertFalse(fixture.fire.shouldUseWindowSnapshot(for: try XCTUnwrap(fixture.fire.burningData)))
            XCTAssertTrue(source.window?.isVisible == true)
            XCTAssertEqual(collection.tabCollection.tabs.map(\.uuid), [other.uuid])
            fixture.cache.finish()
            await fulfillment(of: [finished], timeout: 5)
            source.close()
        }
    }

    @MainActor
    func testNonClosingBurnKeepsSourceAndInWindowProgressForBothFlagStates() async throws {
        for enabled in [false, true] {
            let fixture = makeFixture(snapshotEnabled: enabled)
            let source = try openWindow(coordinator: fixture.coordinator, title: "Retained source")
            let collection = source.mainViewController.tabCollectionViewModel
            let ids = collection.tabCollection.tabs.map(\.uuid)
            let clearing = expectation(description: "Non-closing cleanup is held")
            let finished = expectation(description: "Non-closing burn finishes")
            fixture.cache.onClear = { clearing.fulfill() }
            fixture.fire.burnEntity(.window(tabCollectionViewModel: collection, selectedDomains: [], close: false),
                                    includingHistory: false, includeCookiesAndSiteData: true, includeChatHistory: false,
                                    dataClearingWideEventService: nil) { finished.fulfill() }
            await fulfillment(of: [clearing], timeout: 5)
            XCTAssertFalse(fixture.fire.shouldUseWindowSnapshot(for: try XCTUnwrap(fixture.fire.burningData)))
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertTrue(source.window?.isVisible == true)
            XCTAssertEqual(collection.tabCollection.tabs.map(\.uuid), ids)
            XCTAssertFalse(try XCTUnwrap(source.mainViewController.fireViewController.view.superview).isHidden)
            XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.windowController is FireProgressWindowController })
            fixture.cache.finish()
            await fulfillment(of: [finished], timeout: 5)
            source.close()
        }
    }

    @MainActor
    private func makeFixture(snapshotEnabled: Bool) -> (fire: Fire, coordinator: FireCoordinator, cache: HeldSnapshotCache) {
        flagger.featuresStub[FeatureFlag.fireWindowSnapshotAnimation.rawValue] = snapshotEnabled
        let cache = HeldSnapshotCache()
        let fire = Fire(cacheManager: cache, historyCoordinating: HistoryCoordinatingMock(), permissionManager: PermissionManagerMock(),
                        windowControllersManager: app.windowControllersManager, faviconManagement: FaviconManagerMock(),
                        tld: app.tld, visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                        featureFlagger: flagger, isAppActiveProvider: { true })
        let coordinator = FireCoordinator(tld: app.tld, featureFlagger: flagger, historyCoordinating: app.historyCoordinator,
                                          visualizeFireAnimationDecider: app.visualizeFireSettingsDecider,
                                          onboardingContextualDialogsManager: nil, fireproofDomains: fire.fireproofDomains,
                                          faviconManagement: app.faviconManager, windowControllersManager: app.windowControllersManager,
                                          dataClearingPreferences: app.dataClearingPreferences, pixelFiring: nil,
                                          historyProvider: MockHistoryViewDataProvider(), fireViewModel: FireViewModel(fire: fire))
        return (fire, coordinator, cache)
    }

    @MainActor
    private func openWindow(coordinator: FireCoordinator, title: String) throws -> MainWindowController {
        let tab = Tab(content: .contentFromURL(URL(string: "data:,\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!,
                                              source: .ui), shouldLoadInBackground: true)
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]), burnerMode: .regular)
        collection.pinnedTabsManager?.tabCollection.removeAll()
        let window = try XCTUnwrap(WindowsManager.openNewWindow(with: collection, fireCoordinator: coordinator, burnerMode: .regular))
        window.makeFirstResponder(window.contentView)
        return try XCTUnwrap(window.windowController as? MainWindowController)
    }
}
