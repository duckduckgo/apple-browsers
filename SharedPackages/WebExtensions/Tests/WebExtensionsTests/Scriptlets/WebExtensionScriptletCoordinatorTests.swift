//
//  WebExtensionScriptletCoordinatorTests.swift
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
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionScriptletCoordinatorTests: XCTestCase {

    var mockProvider: MockScriptletProvider!
    var mockStore: MockScriptletStore!
    var mockInstaller: MockScriptletInstaller!
    var mockPathResolver: MockInstallationPathResolver!
    var cacheRootDirectory: URL!
    var installationDirectory: URL!
    var coordinator: WebExtensionScriptletCoordinator!

    let testType: DuckDuckGoWebExtensionType = .adBlockingExtension
    let testScriptlets = [Scriptlet(path: "script.js", relativeCachedPath: "ext/1.0/script.js")]

    override func setUp() {
        super.setUp()
        mockProvider = MockScriptletProvider()
        mockStore = MockScriptletStore()
        mockInstaller = MockScriptletInstaller()
        mockPathResolver = MockInstallationPathResolver()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        cacheRootDirectory = tempDir.appendingPathComponent("cache")
        installationDirectory = tempDir.appendingPathComponent("install")

        mockPathResolver.paths[testType] = installationDirectory

        coordinator = WebExtensionScriptletCoordinator(
            scriptletProvider: mockProvider,
            installationTracker: mockStore,
            installer: mockInstaller,
            cacheRootDirectory: cacheRootDirectory,
            installationPathResolver: mockPathResolver
        )
    }

    override func tearDown() {
        coordinator = nil
        mockPathResolver = nil
        mockInstaller = nil
        mockStore = nil
        mockProvider = nil
        try? FileManager.default.removeItem(at: cacheRootDirectory.deletingLastPathComponent())
        cacheRootDirectory = nil
        installationDirectory = nil
        super.tearDown()
    }

    func testWhenExtensionEnabledThenProviderIsStartedAndSubscribed() async {
        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockProvider.startCallCount, 1)
        XCTAssertEqual(mockProvider.startedTypes, [testType])
    }

    func testWhenExtensionEnabledWithAvailableScriptletsThenInstallationIsTriggered() async {
        mockProvider.scriptletsMap[testType] = testScriptlets
        mockProvider.versionMap[testType] = "1.0"

        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockInstaller.installCallCount, 1)
        XCTAssertEqual(mockInstaller.lastInstalledScriptlets, testScriptlets)
        XCTAssertEqual(mockInstaller.lastInstallationDirectory, installationDirectory)
        XCTAssertEqual(mockStore.installedVersion(for: testType), "1.0")
    }

    func testWhenInstalledVersionMatchesThenInstallationIsSkipped() async {
        mockProvider.scriptletsMap[testType] = testScriptlets
        mockProvider.versionMap[testType] = "1.0"
        mockStore.setInstalledVersion("1.0", for: testType)

        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockInstaller.installCallCount, 0)
    }

    func testWhenAvailabilityUpdatesToAvailableThenNewInstallationIsTriggered() async {
        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockInstaller.installCallCount, 0)

        let newScriptlets = [Scriptlet(path: "new.js", relativeCachedPath: "ext/2.0/new.js")]
        mockProvider.scriptletsMap[testType] = newScriptlets
        mockProvider.versionMap[testType] = "2.0"
        mockProvider.availabilitySubjects[testType]?.send(.available(newScriptlets))

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockInstaller.installCallCount, 1)
        XCTAssertEqual(mockInstaller.lastInstalledScriptlets, newScriptlets)
        XCTAssertEqual(mockStore.installedVersion(for: testType), "2.0")
    }

    func testWhenExtensionDisabledThenProviderIsStoppedAndInstalledVersionCleared() async {
        mockProvider.scriptletsMap[testType] = testScriptlets
        mockProvider.versionMap[testType] = "1.0"

        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockStore.installedVersion(for: testType), "1.0")

        coordinator.onExtensionDisabled(for: testType)

        XCTAssertEqual(mockProvider.stopCallCount, 1)
        XCTAssertEqual(mockProvider.stoppedTypes, [testType])
        XCTAssertNil(mockStore.installedVersion(for: testType))
    }

    func testWhenInstallationPathResolverReturnsNilThenInstallationIsSkipped() async {
        mockPathResolver.paths.removeAll()
        mockProvider.scriptletsMap[testType] = testScriptlets
        mockProvider.versionMap[testType] = "1.0"

        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockInstaller.installCallCount, 0)
        XCTAssertNil(mockStore.installedVersion(for: testType))
    }

    func testWhenInstallationFailsThenInstalledVersionIsNotUpdated() async {
        mockProvider.scriptletsMap[testType] = testScriptlets
        mockProvider.versionMap[testType] = "1.0"
        mockInstaller.shouldThrowError = true

        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockInstaller.installCallCount, 1)
        XCTAssertNil(mockStore.installedVersion(for: testType))
    }

    func testWhenExtensionEnabledTwiceThenSecondCallIsIgnored() async {
        await coordinator.onExtensionEnabled(for: testType)
        await coordinator.onExtensionEnabled(for: testType)

        XCTAssertEqual(mockProvider.startCallCount, 1)
    }

    func testWhenProviderVersionChangesWhileQueuedThenCapturedVersionIsUsed() async throws {
        let v0Scriptlets = [Scriptlet(path: "v0.js", relativeCachedPath: "ext/0.1/v0.js")]
        let v1Scriptlets = [Scriptlet(path: "v1.js", relativeCachedPath: "ext/1.0/v1.js")]

        mockProvider.scriptletsMap[testType] = v0Scriptlets
        mockProvider.versionMap[testType] = "0.1"
        mockInstaller.blockNextInstall()

        let enableTask = Task { @MainActor in
            await self.coordinator.onExtensionEnabled(for: self.testType)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockInstaller.installCallCount, 1, "V0 install should have started")

        mockProvider.versionMap[testType] = "1.0"
        mockProvider.scriptletsMap[testType] = v1Scriptlets
        mockProvider.availabilitySubjects[testType]?.send(.available(v1Scriptlets))

        try await Task.sleep(nanoseconds: 50_000_000)

        mockProvider.versionMap[testType] = "999.0"

        mockInstaller.resumeInstall()

        await enableTask.value
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockInstaller.installCallCount, 2)
        XCTAssertEqual(mockInstaller.allInstalledScriptlets[0], v0Scriptlets)
        XCTAssertEqual(mockInstaller.allInstalledScriptlets[1], v1Scriptlets)
        XCTAssertEqual(mockStore.installedVersion(for: testType), "1.0",
                       "V1 should record version 1.0 (captured at publish time), not 999.0 (current provider version)")
    }
}
