//
//  AITabChromeDecisionTests.swift
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
@testable import DuckDuckGo

final class AITabChromeDecisionTests: XCTestCase {

    // MARK: - AI chat input hidden (FE-driven) — gated on being on an AI tab

    func test_hidesInputBar_onlyWhenOnAITabAndFrontendHides() {
        XCTAssertTrue(decide(isOnAITab: true, isAIChatInputHiddenByFrontend: true).hidesInputBar)
        XCTAssertFalse(decide(isOnAITab: false, isAIChatInputHiddenByFrontend: true).hidesInputBar)
        XCTAssertFalse(decide(isOnAITab: true, isAIChatInputHiddenByFrontend: false).hidesInputBar)
    }

    // MARK: - Voice session chrome — gated on being on an AI tab

    func test_voiceChromeActive_onlyOnAITab() {
        XCTAssertTrue(decide(isOnAITab: true, isVoiceSessionActive: true).voiceChromeActive)
        XCTAssertFalse(decide(isOnAITab: false, isVoiceSessionActive: true).voiceChromeActive)
    }

    // MARK: - Helper

    private func decide(
        isOnAITab: Bool = false,
        isAIChatInputHiddenByFrontend: Bool = false,
        isVoiceSessionActive: Bool = false
    ) -> AITabChromeDecision {
        AITabChromeDecision.resolve(.init(
            isOnAITab: isOnAITab,
            isAIChatInputHiddenByFrontend: isAIChatInputHiddenByFrontend,
            isVoiceSessionActive: isVoiceSessionActive
        ))
    }
}
