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
}
