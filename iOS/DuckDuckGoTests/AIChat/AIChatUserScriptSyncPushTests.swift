//
//  AIChatUserScriptSyncPushTests.swift
//  DuckDuckGo
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

import AIChat
import UserScript
import XCTest
@testable import DuckDuckGo

/// Regression test for #3661: sync-status push messages must only be delivered to allowed DuckDuckGo
/// destinations, never to arbitrary pages. The fix introduced a dedicated `messageDestinationPolicy`
/// (used by `submitSyncStatusChanged`'s guard) that is deliberately narrower than the message-origin
/// policy — notably it allows duck.ai but NOT duckduckgo.com.
///
/// This asserts the destination policy's scope directly. Reverting `buildMessageDestinationRules`
/// (e.g. widening it to arbitrary hosts, or reusing the origin policy which includes duckduckgo.com)
/// fails these assertions; removing the policy entirely fails to compile.
@MainActor
final class AIChatUserScriptSyncPushTests: XCTestCase {

    func testSyncPushDestinationPolicyAllowsDuckAiButNotArbitraryOrDuckDuckGoHosts() throws {
        let userScript = AIChatUserScript(handler: MockAIChatUserScriptHandling(),
                                          debugSettings: MockAIChatDebugSettingsForTests())
        let policy = userScript.messageDestinationPolicy

        let duckAiHost = try XCTUnwrap(URL.duckAi.host)
        let duckDuckGoHost = try XCTUnwrap(URL.ddg.host)

        XCTAssertTrue(policy.isAllowed(duckAiHost),
                      "duck.ai must be an allowed sync-status push destination")
        XCTAssertFalse(policy.isAllowed("example.com"),
                       "arbitrary pages must not receive sync-status push messages")
        XCTAssertFalse(policy.isAllowed(duckDuckGoHost),
                       "duckduckgo.com is an allowed message origin but must NOT be a sync-status push destination")
    }
}
