//
//  WebExtensionUnloadGuardTests.swift
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
final class WebExtensionUnloadGuardTests: XCTestCase {

    private var recordedSleeps: [TimeInterval] = []
    private var currentDate = Date()
    private var createdTestExtensionDirs: [URL] = []

    override func setUp() {
        super.setUp()
        recordedSleeps = []
        currentDate = Date()
    }

    override func tearDown() {
        for dir in createdTestExtensionDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        createdTestExtensionDirs.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    @MainActor
    private func makeGuard(settleWindow: TimeInterval = 3) -> WebExtensionUnloadGuard {
        WebExtensionUnloadGuard(
            settleWindow: settleWindow,
            now: { [unowned self] in currentDate },
            sleeper: { [unowned self] in recordedSleeps.append($0) }
        )
    }

    @MainActor
    private func makeContext(identifier: String, permissions: [String]) async throws -> WKWebExtensionContext {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UnloadGuardTestExtension-\(UUID().uuidString)")
        let permissionsJSON = permissions.map { "\"\($0)\"" }.joined(separator: ", ")
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Unload Guard Test Extension",
            "version": "1.0.0",
            "description": "Minimal backgroundless test extension for unload guard unit tests",
            "permissions": [\(permissionsJSON)]
        }
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        createdTestExtensionDirs.append(dir)

        let webExtension = try await WKWebExtension(resourceBaseURL: dir)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        return context
    }

    // MARK: - Tests

    @MainActor
    func testWhenDNRExtensionWasLoadedWithinWindow_ThenAwaitSettledSleepsForRemainder() async throws {
        let unloadGuard = makeGuard()
        let context = try await makeContext(identifier: "dnr-extension", permissions: ["declarativeNetRequest"])
        unloadGuard.recordLoad(of: "dnr-extension")

        currentDate = currentDate.addingTimeInterval(1)
        await unloadGuard.awaitSettled(context)

        XCTAssertEqual(recordedSleeps.count, 1)
        XCTAssertEqual(recordedSleeps[0], 2.0, accuracy: 0.001)
    }

    @MainActor
    func testWhenDNRExtensionWasLoadedBeyondWindow_ThenAwaitSettledDoesNotSleep() async throws {
        let unloadGuard = makeGuard()
        let context = try await makeContext(identifier: "dnr-extension", permissions: ["declarativeNetRequest"])
        unloadGuard.recordLoad(of: "dnr-extension")

        currentDate = currentDate.addingTimeInterval(3.5)
        await unloadGuard.awaitSettled(context)

        XCTAssertTrue(recordedSleeps.isEmpty)
    }

    @MainActor
    func testWhenExtensionDoesNotRequestDNR_ThenAwaitSettledDoesNotSleep() async throws {
        let unloadGuard = makeGuard()
        let context = try await makeContext(identifier: "plain-extension", permissions: [])
        unloadGuard.recordLoad(of: "plain-extension")

        currentDate = currentDate.addingTimeInterval(1)
        await unloadGuard.awaitSettled(context)

        XCTAssertTrue(recordedSleeps.isEmpty)
    }

    @MainActor
    func testWhenExtensionRequestsDNRWithHostAccess_ThenAwaitSettledSleeps() async throws {
        let unloadGuard = makeGuard()
        let context = try await makeContext(identifier: "dnr-extension", permissions: ["declarativeNetRequestWithHostAccess"])
        unloadGuard.recordLoad(of: "dnr-extension")

        currentDate = currentDate.addingTimeInterval(1)
        await unloadGuard.awaitSettled(context)

        XCTAssertEqual(recordedSleeps.count, 1)
        XCTAssertEqual(recordedSleeps[0], 2.0, accuracy: 0.001)
    }

    @MainActor
    func testWhenNoLoadWasRecorded_ThenAwaitSettledDoesNotSleep() async throws {
        let unloadGuard = makeGuard()
        let context = try await makeContext(identifier: "dnr-extension", permissions: ["declarativeNetRequest"])

        await unloadGuard.awaitSettled(context)

        XCTAssertTrue(recordedSleeps.isEmpty)
    }

    @MainActor
    func testWhenContextIsNil_ThenAwaitSettledDoesNotSleep() async {
        let unloadGuard = makeGuard()
        unloadGuard.recordLoad(of: "dnr-extension")

        await unloadGuard.awaitSettled(nil)

        XCTAssertTrue(recordedSleeps.isEmpty)
    }

    /// Uses the real sleeper rather than the recording one: teardown cancels the tasks that unload,
    /// so a cancellable wait would skip the window exactly when it is needed.
    @MainActor
    func testWhenTaskIsCancelled_ThenAwaitSettledStillWaitsOutTheWindow() async throws {
        let settleWindow: TimeInterval = 0.3
        let unloadGuard = WebExtensionUnloadGuard(settleWindow: settleWindow)
        let context = try await makeContext(identifier: "dnr-extension", permissions: ["declarativeNetRequest"])
        unloadGuard.recordLoad(of: "dnr-extension")

        let task = Task { @MainActor in
            let start = Date()
            await unloadGuard.awaitSettled(context)
            return Date().timeIntervalSince(start)
        }
        task.cancel()

        let elapsed = await task.value
        XCTAssertGreaterThan(elapsed, settleWindow * 0.8)
    }
}
