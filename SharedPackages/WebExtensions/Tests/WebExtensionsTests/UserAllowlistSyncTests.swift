//
//  UserAllowlistSyncTests.swift
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

@available(iOS 18.4, macOS 15.4, *)
final class UserAllowlistWebExtensionMessageHandlerTests: XCTestCase {

    private func message(_ method: String, version: String? = nil) -> WebExtensionMessage {
        WebExtensionMessage(featureName: "userAllowlist", method: method, id: nil,
                            params: version.map { ["version": $0] }, context: nil, extensionIdentifier: "test")
    }

    private func payload(_ result: WebExtensionMessageResult, file: StaticString = #filePath, line: UInt = #line) -> [String: Any]? {
        guard case .success(let payload) = result, let dict = payload as? [String: Any] else {
            XCTFail("expected .success with a dictionary payload", file: file, line: line)
            return nil
        }
        return dict
    }

    func testHandledFeatureNameMatchesExtension() {
        XCTAssertEqual(UserAllowlistWebExtensionMessageHandler(allowlist: { [] }).handledFeatureName, "userAllowlist")
    }

    func testWithoutVersionReturnsSortedList() async {
        let handler = UserAllowlistWebExtensionMessageHandler(allowlist: { ["b.com", "a.com", "b.com"] })
        let dict = payload(await handler.handleMessage(message("getAllowlistIfNew")))

        XCTAssertEqual(dict?["updated"] as? Bool, true)
        XCTAssertEqual(dict?["domains"] as? [String], ["a.com", "b.com"])
        XCTAssertEqual(dict?["version"] as? String, UserAllowlistSnapshot(domains: ["a.com", "b.com"]).version)
    }

    func testCurrentVersionReturnsNotUpdated() async {
        let handler = UserAllowlistWebExtensionMessageHandler(allowlist: { ["a.com"] })
        let version = UserAllowlistSnapshot(domains: ["a.com"]).version
        let dict = payload(await handler.handleMessage(message("getAllowlistIfNew", version: version)))

        XCTAssertEqual(dict?["updated"] as? Bool, false)
        XCTAssertNil(dict?["domains"])
    }

    func testStaleVersionReturnsNewList() async {
        var domains = ["a.com"]
        let handler = UserAllowlistWebExtensionMessageHandler(allowlist: { domains })
        let oldVersion = UserAllowlistSnapshot(domains: domains).version
        domains = []
        let dict = payload(await handler.handleMessage(message("getAllowlistIfNew", version: oldVersion)))

        XCTAssertEqual(dict?["updated"] as? Bool, true)
        XCTAssertEqual(dict?["domains"] as? [String], [])
    }

    func testUnknownMethodFails() async {
        let handler = UserAllowlistWebExtensionMessageHandler(allowlist: { [] })
        guard case .failure = await handler.handleMessage(message("nope")) else { return XCTFail("expected .failure for an unknown method") }
    }

    func testVersionIgnoresOrderAndDuplicates() {
        XCTAssertEqual(UserAllowlistSnapshot(domains: ["a.com", "b.com"]).version,
                       UserAllowlistSnapshot(domains: ["b.com", "a.com", "a.com"]).version)
        XCTAssertNotEqual(UserAllowlistSnapshot(domains: ["a.com"]).version,
                          UserAllowlistSnapshot(domains: ["a.com", "b.com"]).version)
    }
}

@MainActor
final class UserAllowlistChangeNotifierTests: XCTestCase {

    func testNotifiesOnlyWhenTheAllowlistChanges() {
        let changes = PassthroughSubject<Void, Never>()
        var domains = ["a.com"]
        var notifications = 0
        var lastSnapshot: UserAllowlistSnapshot?
        let notifier = UserAllowlistChangeNotifier(changes: changes.eraseToAnyPublisher(), allowlist: { domains }) {
            notifications += 1
            lastSnapshot = $0
        }

        changes.send()
        XCTAssertEqual(notifications, 0, "an update that leaves the list unchanged is not a change")

        domains.append("b.com")
        changes.send()
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(lastSnapshot, UserAllowlistSnapshot(domains: ["a.com", "b.com"]))

        changes.send()
        XCTAssertEqual(notifications, 1)

        domains.removeAll()
        changes.send()
        XCTAssertEqual(notifications, 2)
        withExtendedLifetime(notifier) {}
    }
}
