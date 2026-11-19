//
//  AIChatUserScriptOriginPolicyTests.swift
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

final class AIChatUserScriptOriginPolicyTests: XCTestCase {

    private var script: AIChatUserScript!

    override func setUp() {
        super.setUp()
        script = AIChatUserScript(handler: MockAIChatUserScriptHandling(), debugSettings: MockAIChatDebugSettingsForTests())
    }

    override func tearDown() {
        script = nil
        super.tearDown()
    }

    func testWhenDuckDuckGoSendsAHomepageOrSearchHandoffMessageThenItIsAllowed() {
        for message in AIChatUserScriptMessages.duckDuckGoPageMessages {
            XCTAssertTrue(script.messageOriginPolicy(forMethodNamed: message.rawValue).isAllowed("duckduckgo.com"), message.rawValue)
        }
    }

    func testWhenDuckDuckGoSendsAnyOtherMessageThenItIsRefused() {
        for message in AIChatUserScriptMessages.allCases where !AIChatUserScriptMessages.duckDuckGoPageMessages.contains(message) {
            XCTAssertFalse(script.messageOriginPolicy(forMethodNamed: message.rawValue).isAllowed("duckduckgo.com"), message.rawValue)
        }
        XCTAssertFalse(script.messageOriginPolicy(forMethodNamed: "unknownMethod").isAllowed("duckduckgo.com"))
    }

    func testWhenDuckAISendsAnyMessageThenItIsAllowed() {
        for message in AIChatUserScriptMessages.allCases {
            XCTAssertTrue(script.messageOriginPolicy(forMethodNamed: message.rawValue).isAllowed("duck.ai"), message.rawValue)
        }
    }
}
