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
    func testLoadAndSyncRunsLoadThenSyncAsOneUnit() async {
        let manager = RecordingWebExtensionManager()
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [.embedded] })

        await sut.loadAndSync().value

        XCTAssertEqual(manager.finished, [.load, .sync([.embedded])])
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
    func testCancelAllPreventsQueuedOperationsFromRunning() async {
        let manager = RecordingWebExtensionManager()
        manager.opDelay = .milliseconds(50)
        let sut = WebExtensionLifecycleCoordinator(manager: manager, enabledTypesProvider: { [] })

        let first = sut.load()
        let second = sut.reload()
        sut.cancelAll()
        await first.value
        await second.value

        XCTAssertTrue(manager.finished.isEmpty, "cancelAll must stop all queued operations before they run")
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
    func testCancelAllPreventsQueuedVerifyFromReporting() async {
        let manager = RecordingWebExtensionManager()
        manager.opDelay = .milliseconds(50)
        let spy = SpyWebExtensionPixelFiring()
        let sut = WebExtensionLifecycleCoordinator(
            manager: manager, enabledTypesProvider: { [.embedded] }, pixelFiring: spy
        )
        let first = sut.load()
        let queuedVerify = sut.verify()
        sut.cancelAll()
        await first.value
        await queuedVerify.value
        XCTAssertTrue(spy.firedEvents.isEmpty, "cancelAll must stop the queued check from firing")
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
        case sync(Set<DuckDuckGoWebExtensionType>)
        case reload
        case unload
    }

    private(set) var started: [Operation] = []
    private(set) var finished: [Operation] = []
    private(set) var maxConcurrent = 0
    private var active = 0

    /// Delay inside each async op so that, were ops NOT serialized, overlap would be observable.
    var opDelay: Duration = .milliseconds(10)

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
        begin(.load); try? await Task.sleep(for: opDelay); end(.load)
    }
    func reloadInstalledExtensions() async {
        begin(.reload); try? await Task.sleep(for: opDelay); end(.reload)
    }
    @MainActor func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        begin(.sync(enabledTypes)); try? await Task.sleep(for: opDelay); end(.sync(enabledTypes))
    }
    func unloadAllExtensions() {
        begin(.unload); end(.unload)
    }

    // Unused protocol requirements
    var loadedExtensions: Set<WKWebExtensionContext> { [] }
    var loadedEmbeddedExtensionTypes: Set<DuckDuckGoWebExtensionType> { stubbedLoadedTypes }
    var webExtensionIdentifiers: [String] { [] }
    var controller: WKWebExtensionController { WKWebExtensionController() }
    var eventsListener: WebExtensionEventsListening { RecordingEventsListener() }
    var extensionsDirectory: URL { URL(fileURLWithPath: "/tmp") }
    var extensionUpdates: AsyncStream<Void> { AsyncStream { _ in } }
    func installExtension(from sourceURL: URL) async throws {}
    @MainActor func uninstallExtension(identifier: String) throws {}
    @MainActor @discardableResult func uninstallAllExtensions() -> [Result<Void, Error>] { [] }
    @MainActor func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {}
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? { nil }
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? { nil }
    @MainActor func reloadExtension(identifier: String) async throws {}
    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
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
    var controller: WKWebExtensionController?
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
}
