//
//  WebExtensionLifecycleCoordinatorTests.swift
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
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
private final class SpyWebExtensionPixelFiring: WebExtensionPixelFiring {
    private(set) var firedEvents: [WebExtensionPixelEvent] = []
    func fire(_ event: WebExtensionPixelEvent) { firedEvents.append(event) }

    var stateCheckedCount: Int {
        firedEvents.filter { if case .stateChecked = $0 { return true }; return false }.count
    }
    var notLoadedTypes: Set<DuckDuckGoWebExtensionType> {
        Set(firedEvents.compactMap { event in
            if case .expectedExtensionNotLoaded(let type) = event { return type } else { return nil }
        })
    }
    var scriptletNotFetchedFlags: [Bool] {
        firedEvents.compactMap { event in
            if case .adBlockingScriptletsNotFetched(let loaded) = event { return loaded } else { return nil }
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionLifecycleCoordinatorTests: XCTestCase {

    @MainActor
    func testOperationsRunSeriallyInSubmissionOrder() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [] })

        sut.load()
        sut.reload()
        let last = sut.unload()
        await last.value

        XCTAssertEqual(manager.maxConcurrent, 1, "operations must never overlap")
        XCTAssertEqual(manager.finished, [.load, .reload, .unload])
    }

    @MainActor
    func testLoadAndSyncPreparesOnlyCPMBeforeLoadAsOneUnit() async {
        let manager = RecordingWebExtensionManager()
        let types: Set<DuckDuckGoWebExtensionType> = [.embedded, .darkReader, .adBlockingExtension, .searchToken]
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { types })

        await sut.loadAndSync().value

        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync(types)])
        XCTAssertEqual(manager.maxConcurrent, 1)
    }

    @MainActor
    func testDisabledCPMIsRemovedBeforeLoadWhileOtherTypesSyncAfterLoad() async {
        let manager = RecordingWebExtensionManager()
        let types: Set<DuckDuckGoWebExtensionType> = [.darkReader, .adBlockingExtension, .searchToken]
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { types })

        await sut.loadAndSync().value

        XCTAssertEqual(manager.finished, [.syncCPM(false), .load, .sync(types)])
    }

    @MainActor
    func testDisabledUpgradeBeforeLoadRestoresLoadThenSyncAsOneUnit() async {
        let manager = RecordingWebExtensionManager()
        manager.isCPMUpgradeBeforeLoadEnabled = false
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        await sut.loadAndSync().value

        XCTAssertEqual(manager.finished, [.load, .sync([.embedded])])
        XCTAssertEqual(manager.maxConcurrent, 1)
    }

    @MainActor
    func testLaunchRepairsInstallationsRemovedByFullLoad() async {
        let manager = RecordingWebExtensionManager()
        manager.webExtensionIdentifiers = ["broken"]
        manager.suspendLoad = true
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })
        let launch = sut.loadAndSync()
        while !manager.isLoadSuspended { await Task.yield() }
        manager.webExtensionIdentifiers = []
        manager.resumeLoad()

        await launch.value

        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded])])
        XCTAssertEqual(manager.maxConcurrent, 1)
    }

    @MainActor
    func testInitialLoadWaiterDoesNotCompleteBeforeLoadAndSync() async throws {
        let manager = RecordingWebExtensionManager()
        manager.suspendLoad = true
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        let loadAndSync = sut.loadAndSync()
        while !manager.isLoadSuspended {
            await Task.yield()
        }

        var waitCompleted = false
        let initialLoadWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        let waiter = Task { @MainActor in
            await initialLoadWaiter()
            waitCompleted = true
        }
        await Task.yield()

        XCTAssertFalse(waitCompleted)

        manager.resumeLoad()
        await loadAndSync.value
        await waiter.value

        XCTAssertTrue(waitCompleted)
        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded])])
        XCTAssertFalse(sut.isInitialLoadAndSyncPending)
    }

    @MainActor
    func testInitialLoadWaiterDoesNotCompleteBeforeBackgroundContentLoads() async throws {
        let manager = RecordingWebExtensionManager()
        manager.suspendBackgroundContentLoad = true
        manager.stubbedLoadedTypes = [.embedded]
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        let loadAndSync = sut.loadAndSync()
        while !manager.isBackgroundContentLoadSuspended {
            await Task.yield()
        }

        var waitCompleted = false
        let initialLoadWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        let waiter = Task { @MainActor in
            await initialLoadWaiter()
            waitCompleted = true
        }
        await Task.yield()

        XCTAssertFalse(waitCompleted)
        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded])])

        manager.resumeBackgroundContentLoad()
        await loadAndSync.value
        await waiter.value

        XCTAssertTrue(waitCompleted)
        XCTAssertFalse(sut.isInitialLoadAndSyncPending)
    }

    @MainActor
    func testWhenInitialLoadIsDeferredThenNavigationWaitsUntilItCompletes() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        let initialLoadWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        var waitCompleted = false
        let started = expectation(description: "Navigation starts waiting before load is scheduled")
        let waiter = Task { @MainActor in
            started.fulfill()
            await initialLoadWaiter()
            waitCompleted = true
        }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(waitCompleted)
        XCTAssertTrue(manager.started.isEmpty)

        await sut.loadAndSync().value
        await waiter.value

        XCTAssertTrue(waitCompleted)
        XCTAssertNil(sut.initialLoadWaiter)
    }

    @MainActor
    func testDisabledInitialLoadGateSkipsBackgroundLoadAndDoesNotExposeWaiter() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager,
                                                   initialLoadGateEnabledProvider: { false },
                                                   enabledTypesProvider: { [.embedded] })

        let loadAndSync = sut.loadAndSync()

        XCTAssertNil(sut.initialLoadWaiter)
        await loadAndSync.value
        XCTAssertEqual(manager.backgroundContentLoadCallCount, 0)
        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded])])
    }

    @MainActor
    func testLaunchTimeoutAlsoExpiresNavigationWaitForSameStartup() async throws {
        let manager = RecordingWebExtensionManager()
        manager.shareInitialBackgroundStartup = true
        var release: CheckedContinuation<Void, Never>?
        manager.navigationBackgroundWaiter = { await withCheckedContinuation { release = $0 } }
        let sut = WebExtensionLifecycleCoordinator(manager: manager, initialLoadTimeout: 1, enabledTypesProvider: { [.embedded] })
        let launch = sut.loadAndSync()
        try await XCTUnwrap(sut.initialLoadWaiter)()
        await launch.value
        XCTAssertNotNil(release)
        let released = expectation(description: "Launch already consumed the same startup deadline")
        let waiter = try XCTUnwrap(sut.initialLoadWaiter)
        let navigation = Task { @MainActor in await waiter(); released.fulfill() }
        await fulfillment(of: [released], timeout: 0.2)
        release?.resume()
        await navigation.value
    }

    @MainActor
    func testNavigationAfterLaunchWaitsForBackgroundWake() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        var release: CheckedContinuation<Void, Never>?
        manager.navigationBackgroundWaiter = { await withCheckedContinuation { release = $0 } }
        let backgroundWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        var completed = false
        let task = Task { @MainActor in await backgroundWaiter(); completed = true }
        while release == nil { await Task.yield() }
        XCTAssertFalse(completed)
        release?.resume()
        await task.value
        XCTAssertTrue(completed)
    }

    @MainActor
    func testBackgroundWakeWaitIsBoundedWhenWebKitIgnoresCancellation() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, initialLoadTimeout: 0.02, enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        var release: CheckedContinuation<Void, Never>?
        manager.navigationBackgroundWaiter = { await withCheckedContinuation { release = $0 } }
        let waiter = try XCTUnwrap(sut.initialLoadWaiter)
        let released = expectation(description: "Navigation released without the WebKit callback")
        let task = Task { @MainActor in await waiter(); released.fulfill() }
        await fulfillment(of: [released], timeout: 1)
        XCTAssertNotNil(release, "The background load remains pending after the navigation deadline")
        release?.resume()
        await task.value
    }

    @MainActor
    func testTimedOutBackgroundStartupDoesNotDelayLaterNavigations() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, initialLoadTimeout: 2, enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        var release: CheckedContinuation<Void, Never>?
        let startup = Task { @MainActor in await withCheckedContinuation { release = $0 } }
        manager.navigationBackgroundWaiter = { await startup.value }
        let firstWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        let alreadyPreparedWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        await firstWaiter()
        XCTAssertNotNil(release, "The shared WebKit startup is still pending after the first timeout")

        let laterNavigation = expectation(description: "Later navigation bypasses the expired startup wait")
        let preparedNavigation = expectation(description: "Already prepared navigation shares the expired deadline")
        let waiter = try XCTUnwrap(sut.initialLoadWaiter)
        let navigation = Task { @MainActor in await waiter(); laterNavigation.fulfill() }
        let prepared = Task { @MainActor in await alreadyPreparedWaiter(); preparedNavigation.fulfill() }
        await fulfillment(of: [laterNavigation, preparedNavigation], timeout: 0.5)
        release?.resume()
        await navigation.value
        await prepared.value
    }

    @MainActor
    func testNewBackgroundStartupCanWaitAfterEarlierStartupTimesOut() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, initialLoadTimeout: 0.02, enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        var release: CheckedContinuation<Void, Never>?
        let original = Task { @MainActor in await withCheckedContinuation { release = $0 } }
        manager.navigationBackgroundWaiter = { await original.value }
        try await XCTUnwrap(sut.initialLoadWaiter)()
        release?.resume()
        await original.value

        var releaseReplacement: CheckedContinuation<Void, Never>?
        manager.navigationBackgroundWaiter = { await withCheckedContinuation { releaseReplacement = $0 } }
        let waiter = try XCTUnwrap(sut.initialLoadWaiter)
        var completed = false
        let navigation = Task { @MainActor in await waiter(); completed = true }
        while releaseReplacement == nil { await Task.yield() }
        XCTAssertFalse(completed, "An earlier timeout must not disable protection for a new startup")
        releaseReplacement?.resume()
        await navigation.value
    }

    @MainActor
    func testCancellingNavigationDoesNotWaitForBackgroundCallback() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        var release: CheckedContinuation<Void, Never>?
        manager.navigationBackgroundWaiter = { await withCheckedContinuation { release = $0 } }
        let waiter = try XCTUnwrap(sut.initialLoadWaiter)
        let cancelled = expectation(description: "Cancelled navigation releases its waiter")
        let task = Task { @MainActor in await waiter(); cancelled.fulfill() }
        while release == nil { await Task.yield() }
        task.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        release?.resume()
        await task.value
    }

    @MainActor
    func testDisabledGateDoesNotPrepareIdleBackground() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager,
                                                   initialLoadGateEnabledProvider: { false },
                                                   enabledTypesProvider: { [.embedded] })
        await sut.loadAndSync().value
        manager.navigationBackgroundWaiter = { XCTFail("Disabled navigation protection must not wake background") }
        XCTAssertNil(sut.initialLoadWaiter)
    }

    @MainActor
    func testNavigationGateTimesOutWithoutCancellingInitialLoad() async throws {
        let manager = RecordingWebExtensionManager()
        manager.suspendLoad = true
        let sut = WebExtensionLifecycleCoordinator(manager: manager,
                                                   initialLoadTimeout: 0.01,
                                                   enabledTypesProvider: { [.embedded] })
        let loadAndSync = sut.loadAndSync()
        while !manager.isLoadSuspended {
            await Task.yield()
        }

        let gate = WebExtensionNavigationGate()
        await gate.waitIfNeeded(isMainFrame: true,
                                url: URL(string: "https://example.com")!,
                                initialLoadWaiter: sut.initialLoadWaiter)

        XCTAssertTrue(sut.isInitialLoadAndSyncPending)
        XCTAssertNil(sut.initialLoadWaiter, "A timeout must open the gate for every subsequent navigation")
        XCTAssertEqual(manager.started, [.syncCPM(true), .load])
        XCTAssertEqual(manager.finished, [.syncCPM(true)])

        manager.resumeLoad()
        await loadAndSync.value

        XCTAssertFalse(sut.isInitialLoadAndSyncPending)
        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded])])
    }

    @MainActor
    func testWhenBackgroundContentHangsThenLaterLifecycleOperationsStillComplete() async {
        let manager = RecordingWebExtensionManager()
        manager.suspendBackgroundContentLoad = true
        let sut = WebExtensionLifecycleCoordinator(manager: manager,
                                                   initialLoadTimeout: 0.01,
                                                   enabledTypesProvider: { [.embedded] })
        let completed = expectation(description: "Lifecycle chain completes without the WebKit callback")
        let loadAndSync = sut.loadAndSync()
        let unload = sut.unload()
        let reload = sut.reload()
        let sync = sut.sync()
        let verify = sut.verify()
        let completion = Task { @MainActor in
            await verify.value
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)

        XCTAssertTrue(manager.isBackgroundContentLoadSuspended)
        XCTAssertNil(sut.initialLoadWaiter)
        XCTAssertEqual(manager.finished, [.syncCPM(true), .load, .sync([.embedded]), .unload, .reload, .sync([.embedded])])
        manager.resumeBackgroundContentLoad()
        await loadAndSync.value
        await unload.value
        await reload.value
        await sync.value
        await completion.value
    }

    @MainActor
    func testWhenDeferredLoadTimesOutThenAllWaitersAndLaterNavigationsAreReleased() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager,
                                                   initialLoadTimeout: 0.05,
                                                   enabledTypesProvider: { [.embedded] })
        let initialLoadWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        let completed = expectation(description: "Both tabs are released without scheduling a load")
        completed.expectedFulfillmentCount = 2
        let waiters = (0..<2).map { _ in
            Task { @MainActor in
                await initialLoadWaiter()
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertNil(sut.initialLoadWaiter)
        XCTAssertTrue(manager.started.isEmpty)
        // Even a waiter captured before the timeout must not start a fresh wait.
        await initialLoadWaiter()
        for waiter in waiters {
            await waiter.value
        }
        await sut.loadAndSync().value
        XCTAssertNil(sut.initialLoadWaiter)
    }

    @MainActor
    func testWhenOneNavigationIsCancelledThenOtherNavigationsStillWait() async throws {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })
        let initialLoadWaiter = try XCTUnwrap(sut.initialLoadWaiter)
        let started = expectation(description: "Both navigations started")
        started.expectedFulfillmentCount = 2
        let cancelledWaiter = Task { @MainActor in
            started.fulfill()
            await initialLoadWaiter()
        }
        var secondWaitCompleted = false
        let secondWaiter = Task { @MainActor in
            started.fulfill()
            await initialLoadWaiter()
            secondWaitCompleted = true
        }
        await fulfillment(of: [started], timeout: 1)
        cancelledWaiter.cancel()
        await cancelledWaiter.value

        XCTAssertFalse(secondWaitCompleted)
        XCTAssertNotNil(sut.initialLoadWaiter)
        await sut.loadAndSync().value
        await secondWaiter.value
        XCTAssertTrue(secondWaitCompleted)
    }

    @MainActor
    func testWhenLoadAndSyncIsRepeatedThenBackgroundReadinessIsOnlyCheckedOnce() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        await sut.loadAndSync().value
        await sut.loadAndSync().value

        XCTAssertEqual(manager.backgroundContentLoadCallCount, 1)
        XCTAssertNil(sut.initialLoadWaiter)
    }

    @MainActor
    func testRapidSyncsCoalesceToSingleRun() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [] })

        sut.sync()
        sut.sync()
        sut.sync()
        let last = sut.sync()
        await last.value

        XCTAssertEqual(manager.finished, [.sync([])], "synchronous bursts of sync() must collapse to one run")
    }

    @MainActor
    func testSyncAfterPreviousCompletesRunsAgain() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [] })

        await sut.sync().value
        await sut.sync().value

        XCTAssertEqual(manager.finished, [.sync([]), .sync([])], "a sync requested after the prior one started must run")
    }

    @MainActor
    func testLoadAndSyncReportsStateCheckedAndMissingTypes() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = [.embedded]
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded, .darkReader] }, pixelFiring: spy
        )
        await sut.loadAndSync().value
        XCTAssertEqual(spy.stateCheckedCount, 1)
        XCTAssertEqual(spy.notLoadedTypes, [.darkReader])
    }

    @MainActor
    func testReportsOnlyStateCheckedWhenAllExpectedLoaded() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = [.embedded]
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertEqual(spy.stateCheckedCount, 1)
        XCTAssertTrue(spy.notLoadedTypes.isEmpty)
    }

    @MainActor
    func testLoadAndReloadEachReportAConsistencyCheck() async {
        let manager = RecordingWebExtensionManager()
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [] }, pixelFiring: spy
        )
        await sut.load().value
        await sut.reload().value
        XCTAssertEqual(spy.stateCheckedCount, 2)
    }

    @MainActor
    func testUnloadDoesNotReportConsistency() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = []
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded] }, pixelFiring: spy
        )
        await sut.unload().value
        XCTAssertTrue(spy.firedEvents.isEmpty, "unload's intentional empty state must not be reported")
    }

    @MainActor
    func testVerifyReportsOnDemand() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = []
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.adBlockingExtension] }, pixelFiring: spy
        )
        await sut.verify().value
        XCTAssertEqual(spy.stateCheckedCount, 1)
        XCTAssertEqual(spy.notLoadedTypes, [.adBlockingExtension])
    }

    @MainActor
    func testNoScriptletPixelWhenAdBlockingScriptletsFetched() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = [.adBlockingExtension]
        manager.stubbedAdBlockingScriptletsFetched = true
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.adBlockingExtension] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertTrue(spy.scriptletNotFetchedFlags.isEmpty)
    }

    @MainActor
    func testScriptletPixelExtensionLoadedTrueWhenLoadedButScriptletsMissing() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = [.adBlockingExtension]
        manager.stubbedAdBlockingScriptletsFetched = false
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.adBlockingExtension] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertEqual(spy.scriptletNotFetchedFlags, [true])
    }

    @MainActor
    func testScriptletPixelExtensionLoadedFalseWhenExtensionAlsoMissing() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = []
        manager.stubbedAdBlockingScriptletsFetched = false
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.adBlockingExtension] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertEqual(spy.scriptletNotFetchedFlags, [false])
    }

    @MainActor
    func testNoScriptletPixelWhenAdBlockingNotExpected() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedAdBlockingScriptletsFetched = false
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertTrue(spy.scriptletNotFetchedFlags.isEmpty)
    }

    @MainActor
    func testMultipleMissingTypesAllReported() async {
        let manager = RecordingWebExtensionManager()
        manager.stubbedLoadedTypes = []
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded, .darkReader] }, pixelFiring: spy
        )
        await sut.sync().value
        XCTAssertEqual(spy.stateCheckedCount, 1)
        XCTAssertEqual(spy.notLoadedTypes, [.embedded, .darkReader])
    }
}

// MARK: - Mock

@available(macOS 15.4, iOS 18.4, *)
private final class RecordingWebExtensionManager: WebExtensionManaging {

    enum Operation: Equatable {
        case load
        case syncCPM(Bool)
        case sync(Set<DuckDuckGoWebExtensionType>)
        case reload
        case unload
    }

    var isCPMUpgradeBeforeLoadEnabled = true
    private(set) var started: [Operation] = []
    private(set) var finished: [Operation] = []
    private(set) var maxConcurrent = 0
    private var active = 0

    /// Delay inside each async op so that, were ops NOT serialized, overlap would be observable.
    var opDelay: Duration = .milliseconds(10)
    var suspendLoad = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    var isLoadSuspended: Bool { loadContinuation != nil }
    var suspendBackgroundContentLoad = false
    private var backgroundContentLoadContinuation: CheckedContinuation<Void, Never>?
    var isBackgroundContentLoadSuspended: Bool { backgroundContentLoadContinuation != nil }
    private(set) var backgroundContentLoadCallCount = 0

    /// Stubbed loaded embedded types, representing controller state after an op.
    var stubbedLoadedTypes: Set<DuckDuckGoWebExtensionType> = []
    /// Whether ad-blocking scriptlets are stubbed as fetched (non-nil cached version).
    var stubbedAdBlockingScriptletsFetched = false

    private func begin(_ op: Operation) {
        started.append(op)
        active += 1
        maxConcurrent = max(maxConcurrent, active)
    }

    private func end(_ op: Operation) {
        active -= 1
        finished.append(op)
    }

    // Recorded lifecycle methods
    func loadInstalledExtensions() async {
        begin(.load)
        if suspendLoad {
            await withCheckedContinuation { loadContinuation = $0 }
        } else {
            try? await Task.sleep(for: opDelay)
        }
        end(.load)
    }
    func reloadInstalledExtensions() async {
        begin(.reload); try? await Task.sleep(for: opDelay); end(.reload)
    }
    var shareInitialBackgroundStartup = false
    var pendingEmbeddedBackgroundStartup: Task<Void, Never>? { navigationBackgroundStartup }
    func loadEmbeddedExtensionBackgroundContent() async {
        if shareInitialBackgroundStartup { await prepareEmbeddedBackgroundForNavigation()?.value; return }
        backgroundContentLoadCallCount += 1
        guard suspendBackgroundContentLoad else { return }
        await withCheckedContinuation { backgroundContentLoadContinuation = $0 }
    }
    @MainActor func syncCPMExtensionBeforeLoad(isEnabled: Bool) async {
        begin(.syncCPM(isEnabled)); try? await Task.sleep(for: opDelay); end(.syncCPM(isEnabled))
    }
    @MainActor func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        begin(.sync(enabledTypes)); try? await Task.sleep(for: opDelay); end(.sync(enabledTypes))
    }
    func unloadAllExtensions() {
        begin(.unload); end(.unload)
    }

    func resumeLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func resumeBackgroundContentLoad() {
        backgroundContentLoadContinuation?.resume()
        backgroundContentLoadContinuation = nil
    }

    var navigationBackgroundWaiter: WebExtensionInitialLoadWaiter? {
        didSet { navigationBackgroundStartup = nil }
    }
    private var navigationBackgroundStartup: Task<Void, Never>?
    @MainActor func prepareEmbeddedBackgroundForNavigation() -> Task<Void, Never>? {
        if let startup = navigationBackgroundStartup { return startup }
        guard let waiter = navigationBackgroundWaiter else { return nil }
        let startup = Task { @MainActor in await waiter() }
        navigationBackgroundStartup = startup
        return startup
    }

    // Unused protocol requirements
    var loadedExtensions: Set<WKWebExtensionContext> { [] }
    var loadedEmbeddedExtensionTypes: Set<DuckDuckGoWebExtensionType> { stubbedLoadedTypes }
    var webExtensionIdentifiers: [String] = []
    var eventsListener: WebExtensionEventsListening { RecordingEventsListener() }
    func attachExtensions(to configuration: WKWebViewConfiguration) {}
    var extensionsDirectory: URL { URL(fileURLWithPath: "/tmp") }
    var extensionUpdates: AsyncStream<Void> { AsyncStream { _ in } }
    var lifecycleEvents: AsyncStream<WebExtensionLifecycleEvent> { AsyncStream { _ in } }
    var cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring { NoOpCPMMessagingHealthMonitor() }
    func installExtension(from sourceURL: URL) async throws {}
    func installExtension(from sourceURL: URL, storeIdentity: WebExtensionStoreIdentity?, replacing oldIdentifier: String?) async throws {}
    @MainActor func uninstallExtension(identifier: String) throws {}
    @MainActor @discardableResult func uninstallAllExtensions() -> [Result<Void, Error>] { [] }
    @MainActor func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {}
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? { nil }
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? { nil }
    @MainActor func reloadExtension(identifier: String) async throws {}
    @MainActor func disableExtension(identifier: String) async throws {}
    @MainActor func enableExtension(identifier: String) async throws {}
    func installedExtension(identifier: String) -> InstalledWebExtension? { nil }
    func isRemotelyDisabled(identifier: String) -> Bool { false }
    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
    func extensionPermissions(for identifier: String) -> [String] { [] }
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
    @MainActor func clearCachedScriptlets() {}
    @MainActor func scriptletDebugInfo() -> [ScriptletDebugInfo] {
        stubbedAdBlockingScriptletsFetched
            ? [ScriptletDebugInfo(extensionType: .adBlockingExtension, cachedVersion: "1.0", installedVersion: nil, scriptletPaths: [])]
            : []
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class RecordingEventsListener: WebExtensionEventsListening {
    var droppedCallbacksCount = 0
    var onBrowsingActivity: (() -> Void)?
    func didOpenWindow(_ window: WKWebExtensionWindow) {}
    func didCloseWindow(_ window: WKWebExtensionWindow) {}
    func didFocusWindow(_ window: WKWebExtensionWindow) {}
    func didOpenTab(_ tab: WKWebExtensionTab) {}
    func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool) {}
    func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?) {}
    func didSelectTabs(_ tabs: [WKWebExtensionTab]) {}
    func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {}
    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {}
    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {}
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {}
    func withTabLifecycleEventsSuppressed(_ body: () -> Void) { body() }
}
