//
//  OnboardingDuckAIPathWindowRestorer.swift
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
import Combine
import Foundation
import PixelKit

/// The onboarding state the restorer reads and changes.
protocol DuckAIOnboardingResuming: AnyObject {
    var isWaitingForDuckAIChatDeletion: Bool { get }
    var duckAIPrompt: String? { get }
    func restartDuckAIChat()
    func fallBackToSearchPath()
}

extension ContextualDialogsManager: DuckAIOnboardingResuming {}

protocol DuckAIOnboardingWindow: AnyObject {
    /// Fire and pop-up windows can't hold the chat.
    @MainActor var canHoldDuckAIChat: Bool { get }
    @MainActor func replaceTabs(with tab: Tab)
}

extension MainWindowController: DuckAIOnboardingWindow {
    var canHoldDuckAIChat: Bool {
        !mainViewController.isBurner && !mainViewController.isInPopUpWindow
    }
}

/// Reopens the Duck.ai onboarding chat in a window opened before Fire: after a relaunch, or after the window was closed.
/// The chat starts over from the saved prompt, as the old one can't be reopened.
@MainActor
final class OnboardingDuckAIPathWindowRestorer {

    private let onboarding: DuckAIOnboardingResuming
    private let isDuckAIAvailable: () -> Bool
    private let clearDuckAIChats: () async -> Void
    private let aiChatURL: () -> URL
    private let pixelFiring: PixelFiring?
    private var cancellable: AnyCancellable?

    init(windowDidOpen: AnyPublisher<DuckAIOnboardingWindow, Never>,
         onboarding: DuckAIOnboardingResuming,
         isDuckAIAvailable: @escaping () -> Bool,
         clearDuckAIChats: @escaping () async -> Void,
         aiChatURL: @escaping () -> URL,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.onboarding = onboarding
        self.isDuckAIAvailable = isDuckAIAvailable
        self.clearDuckAIChats = clearDuckAIChats
        self.aiChatURL = aiChatURL
        self.pixelFiring = pixelFiring
        cancellable = windowDidOpen.sink { [weak self] window in
            self?.windowDidOpen(window)
        }
    }

    func windowDidOpen(_ window: DuckAIOnboardingWindow) {
        guard onboarding.isWaitingForDuckAIChatDeletion, window.canHoldDuckAIChat else { return }
        guard isDuckAIAvailable(), let prompt = onboarding.duckAIPrompt else {
            onboarding.fallBackToSearchPath()
            pixelFiring?.fire(DuckAIOnboardingPathPixel.searchFallback, frequency: .standard)
            window.replaceTabs(with: Tab(content: .newtab))
            return
        }
        // A blank tab stops a restored Duck.ai tab from sending the prompt again before the old chat is cleared.
        window.replaceTabs(with: Tab(content: .none))
        Task { [weak window] in
            await clearDuckAIChats()
            // Fire may have been used while the old chat was cleared.
            guard let window, onboarding.isWaitingForDuckAIChatDeletion else { return }
            onboarding.restartDuckAIChat()
            pixelFiring?.fire(DuckAIOnboardingPathPixel.chatReopened, frequency: .standard)
            let url = AIChatURLParameters.desktopOnboardingPromptURL(from: aiChatURL(), prompt: prompt)
            window.replaceTabs(with: Tab(content: .aiChat(url)))
        }
    }
}
