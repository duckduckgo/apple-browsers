//
//  AIChatTabOpenerTests.swift
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
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class AIChatTabOpenerTests: XCTestCase {

    @MainActor
    func testOpenSettingsTriggerRequestsOpenSettingsTab() {
        let mockManager = WindowControllersManagerMock()
        let opener = AIChatTabOpener(promptHandler: AIChatPromptHandler.shared, aiChatTabManaging: mockManager)

        opener.openAIChatTab(with: .openSettings, behavior: .newTab(selected: true))

        XCTAssertEqual(mockManager.insertAIChatTabRequestingOpenSettingsCalls,
                       [opener.aiChatRemoteSettings.aiChatURL],
                       "openSettings trigger must insert exactly one tab armed with requestOpenSettings, using the canonical Duck.ai URL")
        XCTAssertTrue(mockManager.insertAIChatTabCalls.isEmpty,
                      "openSettings must not go through the payload/restoration insert paths")
    }

    @MainActor
    func testOpenSettingsTriggerIgnoresBehavior() {
        // The behavior argument is intentionally a no-op for .openSettings (same as .payload /
        // .restoration). This pins down that contract: passing any behavior still results in
        // exactly one armed insert.
        let mockManager = WindowControllersManagerMock()
        let opener = AIChatTabOpener(promptHandler: AIChatPromptHandler.shared, aiChatTabManaging: mockManager)

        opener.openAIChatTab(with: .openSettings, behavior: .currentTab)

        XCTAssertEqual(mockManager.insertAIChatTabRequestingOpenSettingsCalls.count, 1)
    }

    // MARK: - duck_ai_new_chat metric

    @MainActor
    private func makeOpener(_ mockManager: WindowControllersManagerMock, newChatFired: @escaping () -> Void) -> AIChatTabOpener {
        AIChatTabOpener(promptHandler: AIChatPromptHandler.shared,
                        aiChatTabManaging: mockManager,
                        fireNewChatExperimentPixels: newChatFired)
    }

    @MainActor
    func testNewChatTriggerFiresNewChatExperimentPixel() {
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .newChat, behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 1, "Starting a new chat must fire duck_ai_new_chat exactly once")
    }

    @MainActor
    func testQueryTriggerFiresNewChatExperimentPixel() {
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .query("hello"), behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 1)
    }

    @MainActor
    func testModeTriggerFiresNewChatExperimentPixel() {
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .mode(AIChatNativePrompt.voiceMode), behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 1)
    }

    @MainActor
    func testNewChatNoOpDoesNotFireNewChatExperimentPixel() {
        // The manager reports it did not open a surface (e.g. already on an empty Duck.ai tab): no metric.
        let mockManager = WindowControllersManagerMock()
        mockManager.openAIChatDidOpen = false
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .newChat, behavior: .currentTab)

        XCTAssertEqual(fireCount, 0, "A no-op New Chat must not fire duck_ai_new_chat")
    }

    @MainActor
    func testExistingChatTriggerDoesNotFireNewChatExperimentPixel() {
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .existingChat(chatId: "abc"), behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 0, "Resuming an existing chat is not a new chat")
    }

    @MainActor
    func testPlainURLTriggerDoesNotFireNewChatExperimentPixel() {
        // A .url without a mode param (e.g. the customize-responses modal or a sidebar handoff URL)
        // is not a new chat.
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }

        opener.openAIChatTab(with: .url(opener.aiChatRemoteSettings.aiChatURL), behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 0)
    }

    @MainActor
    func testImageModeURLTriggerFiresNewChatExperimentPixel() {
        let mockManager = WindowControllersManagerMock()
        var fireCount = 0
        let opener = makeOpener(mockManager) { fireCount += 1 }
        let imageModeURL = AIChatURLParameters.imageModeURL(from: opener.aiChatRemoteSettings.aiChatURL)

        opener.openAIChatTab(with: .url(imageModeURL), behavior: .newTab(selected: true))

        XCTAssertEqual(fireCount, 1, "A mode-driven fresh chat (e.g. image generation) must count as a new chat")
    }
}
