//
//  BrowserWindowTests.swift
//  DuckDuckGoTests
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

import Core
import FeatureFlags_iOS
@_spi(Testing) import Persistence
import XCTest
import UIKit
@testable import DuckDuckGo

@MainActor
final class BrowserWindowTests: XCTestCase {
    func testFlagControlsMultiWindowAndRespondsToUpdates() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        XCTAssertFalse(BrowserWindowManager.isEnabled(using: flagger))
        flagger.enabledFeatureFlags = [.iPadMultiWindow]
        if #available(iOS 17, *) {
            XCTAssertTrue(BrowserWindowManager.isEnabled(using: flagger))
        } else {
            XCTAssertFalse(BrowserWindowManager.isEnabled(using: flagger))
        }
        flagger.enabledFeatureFlags = []
        XCTAssertFalse(BrowserWindowManager.isEnabled(using: flagger))
    }

    func testDisablingTheFlagPreservesSavedWindowsAndRejectsNewWindows() {
        XCTAssertTrue(BrowserWindowManager.canConnect(identifier: "saved", knownIdentifiers: ["saved"],
                                                      hasConnectedWindow: true, allowsAdditionalWindows: false))
        XCTAssertFalse(BrowserWindowManager.canConnect(identifier: "new", knownIdentifiers: ["saved"],
                                                       hasConnectedWindow: true, allowsAdditionalWindows: false))
        XCTAssertTrue(BrowserWindowManager.canConnect(identifier: "first", knownIdentifiers: [],
                                                      hasConnectedWindow: false, allowsAdditionalWindows: false))
        XCTAssertTrue(BrowserWindowManager.canConnect(identifier: "new", knownIdentifiers: [],
                                                      hasConnectedWindow: true, allowsAdditionalWindows: true))
    }

    func testClearAllPreparesEveryWindowBeforeBurningAndDeduplicatesOrigin() async throws {
        let coordinator = BrowserWindowFireCoordinator()
        let first = WindowFireMock()
        let second = WindowFireMock()
        var covered = false
        first.onBurn = {
            XCTAssertTrue(covered)
            XCTAssertEqual(first.prepareCount, 1)
            XCTAssertEqual(second.prepareCount, 1)
        }
        second.onBurn = { XCTAssertTrue(covered) }
        let request = FireRequest(options: [.tabs, .data], trigger: .manualFire, scope: .all, source: .settings)
        try await coordinator.burn(request: request, state: .active, origin: first, allWindows: { [first, second, second] },
                               willBurnAll: { covered = true }, didBurnAll: { covered = false })
        XCTAssertEqual(first.burnCount, 1)
        XCTAssertEqual(second.burnCount, 1)
        XCTAssertEqual(second.lastOptions, [.tabs, .data])
        XCTAssertFalse(covered)
        XCTAssertFalse(coordinator.isBurning)
    }

    func testClearAllDoesNotReportSuccessWhenAStoredWindowCannotBeLoaded() async {
        enum Failure: Error { case storage }
        let coordinator = BrowserWindowFireCoordinator()
        let first = WindowFireMock()
        do {
            try await coordinator.burn(request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings),
                                       state: .active, origin: first, allWindows: { throw Failure.storage })
            XCTFail("Expected the storage failure")
        } catch {
            XCTAssertEqual(first.burnCount, 0)
            XCTAssertFalse(coordinator.isBurning)
        }
    }

    func testFireModeClearOnlyBurnsItsWindow() async throws {
        let coordinator = BrowserWindowFireCoordinator()
        let first = WindowFireMock()
        let second = WindowFireMock()
        let request = FireRequest(options: .all, trigger: .fireModeAutoClear, scope: .fireMode, source: .browsing)
        try await coordinator.burn(request: request, state: .active, origin: first, allWindows: {
            XCTFail("Local burns must not ask for other windows")
            return [second]
        })
        XCTAssertEqual(first.burnCount, 1)
        XCTAssertEqual(second.burnCount, 0)
    }

    func testBurnsAndWindowCleanupCannotOverlap() async throws {
        let coordinator = BrowserWindowFireCoordinator()
        let first = WindowFireMock()
        let second = WindowFireMock()
        let started = expectation(description: "First burn suspended")
        let queued = expectation(description: "Second burn queued")
        var continuation: CheckedContinuation<Void, Never>?
        var events: [String] = []
        first.onBurn = { events.append("first started") }
        second.onBurn = { events.append("second started") }
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .fireMode, source: .browsing)
        let firstTask = Task {
            try await coordinator.burn(request: request, state: .active, origin: first, allWindows: { [] }, afterBurn: {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
                events.append("first finished")
            })
        }
        await fulfillment(of: [started], timeout: 2)
        let secondTask = Task {
            queued.fulfill()
            try await coordinator.burn(request: request, state: .active, origin: second, allWindows: { [] })
        }
        await fulfillment(of: [queued], timeout: 2)
        XCTAssertEqual(second.burnCount, 0)
        continuation?.resume()
        try await firstTask.value
        try await secondTask.value
        XCTAssertEqual(events, ["first started", "first finished", "second started"])
    }

    func testResizingOneWindowDoesNotChangeTheOtherWindowsChromeWidth() {
        let first = AppWidthObserver(usesWindowLayout: true)
        let second = AppWidthObserver(usesWindowLayout: true)
        first.isPad = true
        second.isPad = true
        _ = first.willResize(toWidth: 800)
        _ = second.willResize(toWidth: 600)
        XCTAssertTrue(first.isLargeWidth)
        XCTAssertFalse(second.isLargeWidth)
        _ = second.willResize(toWidth: 900)
        XCTAssertEqual(first.currentWidth, 800)
        XCTAssertTrue(second.isLargeWidth)
    }

    func testGlobalFireAnimatesAllWindowsAndLocalFireOnlyAnimatesTheOrigin() {
        let origin = UIWindow()
        let peer = UIWindow()
        let global = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing)
        let local = FireRequest(options: .all, trigger: .manualFire, scope: .fireMode, source: .browsing)
        XCTAssertEqual(BrowserWindowManager.animationWindows(for: global, origin: origin, windows: [peer, origin, peer]), [origin, peer])
        XCTAssertEqual(BrowserWindowManager.animationWindows(for: local, origin: origin, windows: [peer, origin]), [origin])
        XCTAssertTrue(BrowserWindowManager.animationWindows(for: local, origin: nil, windows: [peer]).isEmpty)
    }

    func testGlobalClearingCoverStaysBelowFireAnimationAndAboveBrowserContent() throws {
        let window = UIWindow()
        let content = UIView()
        let animation = UIView()
        animation.accessibilityIdentifier = FireButtonAnimator.overlayIdentifier
        window.addSubview(content)
        window.addSubview(animation)
        let cover = BrowserWindowManager.addClearingOverlay(to: window)
        XCTAssertEqual(window.subviews, [content, cover, animation])
    }

    func testFirstResponderLookupStaysInTheRequestedWindow() {
        let first = UIWindow(frame: .zero)
        let second = UIWindow(frame: .zero)
        let responder = WindowResponderMock()
        first.addSubview(responder)
        XCTAssertTrue(UIResponder.currentFirstResponder(in: first) === responder)
        XCTAssertNil(UIResponder.currentFirstResponder(in: second))
    }

    func testDeletionMessageUsesTheRequestedWindow() {
        let origin = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        let peer = UIWindow(frame: origin.frame)
        defer { origin.subviews.forEach { $0.removeFromSuperview() } }
        ActionMessageView.present(message: "Deleted", in: origin)
        XCTAssertTrue(origin.subviews.contains { $0 is ActionMessageView })
        XCTAssertFalse(peer.subviews.contains { $0 is ActionMessageView })
    }

    func testFireContainersSurviveRelaunchAndRotateIndependently() {
        let store = MockKeyValueStore()
        let primary = DataStoreIDManager(store: store)
        let first = DataStoreIDManager(store: store, windowIdentifier: "first")
        let second = DataStoreIDManager(store: store, windowIdentifier: "second")
        let primaryID = primary.currentFireModeID
        let firstID = first.currentFireModeID
        let secondID = second.currentFireModeID
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertNotEqual(primaryID, firstID)
        XCTAssertEqual(DataStoreIDManager(store: store, windowIdentifier: "first").currentFireModeID, firstID)
        first.invalidateCurrentFireModeID()
        XCTAssertNotEqual(first.currentFireModeID, firstID)
        XCTAssertEqual(first.pendingRemovalFireModeIDs, [firstID])
        XCTAssertEqual(second.currentFireModeID, secondID)
        XCTAssertEqual(primary.currentFireModeID, primaryID)
        XCTAssertTrue(second.pendingRemovalFireModeIDs.isEmpty)
    }

    func testWindowTabsRestoreIndependentlyAndClearingOneLeavesTheOtherOnDisk() throws {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let base = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        defer {
            try? FileManager.default.removeItem(at: BrowserWindowStorage.directory(in: base, windowIdentifier: firstID))
            try? FileManager.default.removeItem(at: BrowserWindowStorage.directory(in: base, windowIdentifier: secondID))
        }
        let firstTab = Tab(link: Link(title: "First", url: URL(string: "https://first.example")!))
        let secondTab = Tab(link: Link(title: "Second", url: URL(string: "https://second.example")!), fireTab: true)
        do {
            let first = try TabsModelPersistence(windowIdentifier: firstID)
            let second = try TabsModelPersistence(windowIdentifier: secondID)
            try first.saveSynchronously(model: TabsModel(tabs: [firstTab], desktop: true), for: .normal).get()
            try second.saveSynchronously(model: TabsModel(tabs: [secondTab], desktop: true, mode: .fire), for: .fire).get()
        }
        let first = try TabsModelPersistence(windowIdentifier: firstID)
        let second = try TabsModelPersistence(windowIdentifier: secondID)
        XCTAssertEqual(try first.getTabsModel(for: .normal)?.tabs.first?.uid, firstTab.uid)
        XCTAssertEqual(try second.getTabsModel(for: .fire)?.tabs.first?.uid, secondTab.uid)
        first.clearAll()
        XCTAssertNil(try first.getTabsModel(for: .normal))
        XCTAssertEqual(try second.getTabsModel(for: .fire)?.tabs.first?.uid, secondTab.uid)
    }

    func testScopedTabsNeverMigrateOrClearLegacyTabs() throws {
        let legacy = MockKeyValueStore()
        let normal = try MockKeyValueFileStore(throwOnInit: nil)
        let fire = try MockKeyValueFileStore(throwOnInit: nil)
        let model = TabsModel(desktop: false, mode: .normal)
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        legacy.set(data, forKey: "com.duckduckgo.opentabs")
        let persistence = TabsModelPersistence(normalStore: normal, fireStore: fire, legacyStore: legacy, migratesLegacyTabs: false)
        XCTAssertNil(try persistence.getTabsModel(for: .normal))
        persistence.clear(for: .normal)
        persistence.clearAll()
        XCTAssertEqual(legacy.object(forKey: "com.duckduckgo.opentabs") as? Data, data)
    }

    func testDelayedCleanupProtectsAllActiveFireContainersButNotInvalidatedOnes() throws {
        let suite = "BrowserWindowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = DataStoreIDManager(store: defaults)
        let first = DataStoreIDManager(store: defaults, windowIdentifier: "first")
        let second = DataStoreIDManager(store: defaults, windowIdentifier: "second")
        let primaryID = primary.currentFireModeID
        let firstID = first.currentFireModeID
        let secondID = second.currentFireModeID
        XCTAssertEqual(DataStoreIDManager.activeFireModeIDs(in: defaults), [primaryID, firstID, secondID])
        first.invalidateCurrentFireModeID()
        XCTAssertEqual(DataStoreIDManager.activeFireModeIDs(in: defaults), [primaryID, secondID])
    }
}

@MainActor
private final class WindowFireMock: BrowserWindowFireExecuting {
    var prepareCount = 0
    var burnCount = 0
    var lastOptions: FireRequest.Options?
    var onBurn: () async -> Void = {}

    func prepare(for request: FireRequest) { prepareCount += 1 }

    func burnInWindow(request: FireRequest, applicationState: DataStoreWarmup.ApplicationState) async {
        burnCount += 1
        lastOptions = request.options
        await onBurn()
    }
}

private final class WindowResponderMock: UIView {
    override var isFirstResponder: Bool { true }
}
