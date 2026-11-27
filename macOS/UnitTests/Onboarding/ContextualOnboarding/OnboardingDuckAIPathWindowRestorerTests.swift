//
//  OnboardingDuckAIPathWindowRestorerTests.swift
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
import Foundation
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo_Privacy_Browser

/// How a window opened before Fire on the Duck.ai path gets its chat back.
@MainActor
struct OnboardingDuckAIPathWindowRestorerTests {

    private let onboarding = FakeDuckAIOnboarding()
    private let window = CapturingDuckAIOnboardingWindow()
    let windowDidOpen = PassthroughSubject<DuckAIOnboardingWindow, Never>()
    private let pixelFiring = PixelKitMock()

    private var firedPixelNames: [String] {
        pixelFiring.actualFireCalls.map(\.pixel.name)
    }

    private func makeRestorer(isDuckAIAvailable: Bool = true,
                              clearDuckAIChats: @escaping () async -> Void = {}) -> OnboardingDuckAIPathWindowRestorer {
        OnboardingDuckAIPathWindowRestorer(windowDidOpen: windowDidOpen.eraseToAnyPublisher(),
                                           onboarding: onboarding,
                                           isDuckAIAvailable: { isDuckAIAvailable },
                                           clearDuckAIChats: clearDuckAIChats,
                                           aiChatURL: { URL(string: "https://duck.ai")! },
                                           pixelFiring: pixelFiring)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A window opened when the path isn't waiting for Fire is left alone", .timeLimit(.minutes(1)))
    func notWaitingLeavesTheWindowAlone() {
        onboarding.isWaitingForDuckAIChatDeletion = false
        let restorer = makeRestorer()

        windowDidOpen.send(window)

        #expect(window.contents.isEmpty)
        #expect(onboarding.fallBackCount == 0)
        #expect(firedPixelNames.isEmpty)
        withExtendedLifetime(restorer) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("With Duck.ai off, the window gets a New Tab and the search path takes over", .timeLimit(.minutes(1)))
    func duckAIOffFallsBackToSearch() {
        let restorer = makeRestorer(isDuckAIAvailable: false)

        windowDidOpen.send(window)

        #expect(window.contents == [.newtab])
        #expect(onboarding.fallBackCount == 1)
        #expect(onboarding.restartCount == 0)
        #expect(firedPixelNames == ["onboarding_duckai-path_search-fallback_macos"])
        withExtendedLifetime(restorer) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without a saved prompt, the search path takes over", .timeLimit(.minutes(1)))
    func missingPromptFallsBackToSearch() {
        onboarding.duckAIPrompt = nil
        let restorer = makeRestorer()

        windowDidOpen.send(window)

        #expect(window.contents == [.newtab])
        #expect(onboarding.fallBackCount == 1)
        #expect(firedPixelNames == ["onboarding_duckai-path_search-fallback_macos"])
        withExtendedLifetime(restorer) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("The old chat is cleared behind a blank tab, then Duck.ai sends the saved prompt again", .timeLimit(.minutes(1)))
    func reopensDuckAIWithTheSavedPrompt() async throws {
        var contentsWhenCleared: [Tab.TabContent]?
        let restorer = makeRestorer(clearDuckAIChats: { [window] in contentsWhenCleared = window.contents })

        let reopened = await withCheckedContinuation { continuation in
            window.onReplace = { content in
                if case .aiChat = content { continuation.resume(returning: content) }
            }
            windowDidOpen.send(window)
        }

        #expect(contentsWhenCleared == [Tab.TabContent.none])
        #expect(onboarding.restartCount == 1)
        #expect(onboarding.fallBackCount == 0)
        #expect(firedPixelNames == ["onboarding_duckai-chat_reopened_macos"])
        guard case .aiChat(let url, _) = reopened else {
            Issue.record("Expected a Duck.ai tab")
            return
        }
        let queryItems = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "q", value: "Plan a day in London")))
        #expect(queryItems.contains(URLQueryItem(name: "flow", value: "desktop-app-onboarding")))
        withExtendedLifetime(restorer) {}
    }
}

private final class FakeDuckAIOnboarding: DuckAIOnboardingResuming {
    var isWaitingForDuckAIChatDeletion = true
    var duckAIPrompt: String? = "Plan a day in London"
    private(set) var restartCount = 0
    private(set) var fallBackCount = 0

    func restartDuckAIChat() {
        restartCount += 1
    }

    func fallBackToSearchPath() {
        fallBackCount += 1
    }
}

private final class CapturingDuckAIOnboardingWindow: DuckAIOnboardingWindow {
    let canHoldDuckAIChat = true
    private(set) var contents: [Tab.TabContent] = []
    var onReplace: ((Tab.TabContent) -> Void)?

    func replaceTabs(with tab: Tab) {
        contents.append(tab.content)
        onReplace?(tab.content)
    }
}
