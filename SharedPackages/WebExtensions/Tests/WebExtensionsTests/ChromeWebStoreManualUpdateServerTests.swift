//
//  ChromeWebStoreManualUpdateServerTests.swift
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

#if DEBUG && os(macOS)
import AppKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class ChromeWebStoreManualUpdateServerTests: XCTestCase {
    private var profileDirectory: URL!
    private var testing: ChromeWebStoreManualUpdateTesting!

    override func setUpWithError() throws {
        profileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: profileDirectory.appendingPathComponent("profile-marker"))
        testing = ChromeWebStoreManualUpdateTesting(directory: profileDirectory)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: profileDirectory)
    }

    func testStartReusesItsProcessAndStopRemovesOnlyServerFiles() async throws {
        let server = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        defer { server.stop() }
        let firstURL = try await server.start()
        let directory = try XCTUnwrap(server.directory)
        let firstStatus = try await testing.serverStatus()
        let secondURL = try await server.start()
        let secondStatus = try await testing.serverStatus()

        XCTAssertEqual(firstURL, secondURL)
        XCTAssertEqual(firstStatus.processIdentifier, secondStatus.processIdentifier)
        XCTAssertEqual(server.directory, directory)
        server.stop()
        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("profile-marker").path))
        server.stop()
    }

    func testDeallocationStopsTheProcessAndRemovesServerFiles() async throws {
        var server: ChromeWebStoreManualUpdateServer? = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        weak var weakServer = server
        _ = try await server?.start()
        let directory = try XCTUnwrap(server?.directory)
        server = nil

        XCTAssertNil(weakServer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let status = try? await testing.serverStatus()
        XCTAssertNil(status)
    }

    func testAppQuitStopsTheOwnedServer() async throws {
        let notifications = NotificationCenter()
        let server = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: notifications)
        defer { server.stop() }
        _ = try await server.start()
        let directory = try XCTUnwrap(server.directory)

        notifications.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("profile-marker").path))
    }

    func testAnOccupiedPortDoesNotStopAnotherOwnersServer() async throws {
        let first = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        defer { first.stop() }
        _ = try await first.start()
        let firstStatus = try await testing.serverStatus()
        let second = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        defer { second.stop() }

        do {
            _ = try await second.start()
            XCTFail("A second owner must not reuse the first owner's server")
        } catch {
            XCTAssertFalse(second.isRunning)
            XCTAssertNil(second.directory)
        }

        let remainingStatus = try await testing.serverStatus()
        XCTAssertTrue(first.isRunning)
        XCTAssertEqual(remainingStatus.processIdentifier, firstStatus.processIdentifier)
    }
}
#endif
