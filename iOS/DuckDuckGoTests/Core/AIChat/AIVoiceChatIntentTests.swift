//
//  AIVoiceChatIntentTests.swift
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

import XCTest
import AppIntents
@testable import Core
@testable import DuckDuckGo

@available(iOS 17.0, *)
final class AIVoiceChatIntentTests: XCTestCase {

    // MARK: - Intent Configuration

    func testAIVoiceChatIntentOpensApp() {
        XCTAssertTrue(AIVoiceChatIntent.openAppWhenRun)
    }

    func testAIVoiceChatIntentIsDiscoverable() {
        XCTAssertTrue(AIVoiceChatIntent.isDiscoverable)
    }

    func testAIVoiceChatIntentIsAlwaysAllowed() {
        XCTAssertEqual(AIVoiceChatIntent.authenticationPolicy, .alwaysAllowed)
    }

    // MARK: - Deep Link URL

    func testVoiceChatDeepLinkWithSiriSource() {
        let url = AppDeepLinkSchemes.openAIVoiceChat.url.appendingParameter(name: "source", value: "siri")

        XCTAssertEqual(url.getParameter(named: "source"), "siri")
        XCTAssertEqual(AppDeepLinkSchemes.fromURL(url), .openAIVoiceChat)
    }

    // MARK: - AppShortcut Registration

    func testVoiceChatShortcutIsRegistered() {
        let shortcuts = AppShortcuts.appShortcuts
        let voiceShortcut = shortcuts.last
        XCTAssertNotNil(voiceShortcut, "Voice chat shortcut should be registered in AppShortcuts")
    }
}
