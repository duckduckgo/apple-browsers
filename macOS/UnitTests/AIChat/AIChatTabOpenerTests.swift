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
@_spi(Testing) import PixelKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class AIChatTabOpenerTests: XCTestCase {

    private var sourceHandler: AIChatConversationSourceHandler!
    private var pixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        sourceHandler = AIChatConversationSourceHandler()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        sourceHandler = nil
        pixelFiring = nil
        super.tearDown()
    }

    @MainActor
    func testWhenChatHistoryTriggerThenOpensDuckAIWithSidebarVisible() {
        let mockManager = WindowControllersManagerMock()
        let opener = AIChatTabOpener(promptHandler: AIChatPromptHandler.shared, aiChatTabManaging: mockManager)

        opener.openAIChatTab(with: .chatHistory, behavior: .newTab(selected: true))

        XCTAssertEqual(mockManager.openAIChatCalls, [
            .init(
                url: URL(string: "https://duck.ai?sidebar=open")!,
                behavior: .newTab(selected: true),
                hasPrompt: false
            )
        ])
    }

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

    // MARK: - Entry point pixel

    private func makeOpener(_ mockManager: WindowControllersManagerMock, pixelFiring: PixelKitMock? = nil) -> AIChatTabOpener {
        AIChatTabOpener(promptHandler: AIChatPromptHandler.shared,
                        aiChatTabManaging: mockManager,
                        entryPointReporter: AIChatEntryPointReporter(sourceHandler: sourceHandler, pixelFiring: pixelFiring ?? self.pixelFiring))
    }

    @MainActor
    func testWhenDuckAIOpensThenEntryPointReportsSourceAndTarget() {
        let mockManager = WindowControllersManagerMock()
        for target in AIChatEntryPointTarget.allCases {
            let pixelFiring = PixelKitMock()
            mockManager.aiChatEntryPointTargetToReturn = target
            sourceHandler.setData(.mainMenuNewChat)

            makeOpener(mockManager, pixelFiring: pixelFiring).openNewAIChat(in: .currentTab)

            XCTAssertEqual(pixelFiring.actualFireCalls, [
                .init(pixel: AIChatPixel.aiChatEntryPoint(source: .mainMenuNewChat, target: target), frequency: .dailyAndCount)
            ], "target \(target)")
        }
    }

    @MainActor
    func testWhenASubscriptionSurfaceOpensDuckAIThenEntryPointReportsSubscriptionPage() {
        let mockManager = WindowControllersManagerMock()
        sourceHandler.setData(.subscriptionPage)

        makeOpener(mockManager).openAIChatTab(with: .url(URL(string: "https://duck.ai/")!), behavior: .newTab(selected: true))

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            .init(pixel: AIChatPixel.aiChatEntryPoint(source: .subscriptionPage, target: .newTab), frequency: .dailyAndCount)
        ])
    }

    @MainActor
    func testWhenOpeningInANewWindowAtAPointThenEntryPointReportsIt() {
        let mockManager = WindowControllersManagerMock()
        mockManager.aiChatEntryPointTargetToReturn = .newWindow
        sourceHandler.setData(.promptBar)

        makeOpener(mockManager).openAIChatTab(withQuery: "Hello", inNewWindowAt: .zero)

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            .init(pixel: AIChatPixel.aiChatEntryPoint(source: .promptBar, target: .newWindow), frequency: .dailyAndCount)
        ])
    }

    @MainActor
    func testWhenNothingOpensThenNoEntryPointIsReportedAndNoneIsLeftPending() {
        let mockManager = WindowControllersManagerMock()
        mockManager.aiChatEntryPointTargetToReturn = nil
        sourceHandler.setData(.omnibarRecentChat)

        makeOpener(mockManager).openAIChatTab(with: .newChat, behavior: .currentTab)

        XCTAssertEqual(pixelFiring.actualFireCalls, [])
        XCTAssertNil(sourceHandler.takeUnreportedEntry())
    }

    @MainActor
    func testWhenVoiceFocusesAnExistingVoiceTabThenNothingIsReportedAndTheStampIsDropped() {
        let mockManager = WindowControllersManagerMock()
        mockManager.focusActiveVoiceSessionTabResult = true
        sourceHandler.setData(.mainMenuVoice)

        makeOpener(mockManager).openVoiceSession(inSourceCollection: nil, behavior: .newTab(selected: true))

        XCTAssertEqual(pixelFiring.actualFireCalls, [])
        XCTAssertNil(sourceHandler.takeUnreportedEntry())
        XCTAssertNil(sourceHandler.consumeData(), "A later chat must not inherit the voice menu's source")
    }

    @MainActor
    func testWhenNoSurfaceStampedTheOpenThenNoEntryPointIsReported() {
        makeOpener(WindowControllersManagerMock()).openAIChatTab(with: .newChat, behavior: .newTab(selected: true))

        XCTAssertEqual(pixelFiring.actualFireCalls, [])
    }
}
