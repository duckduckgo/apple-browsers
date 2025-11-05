//
//  ModalPromptCoordinationManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit

@MainActor
protocol ModalPromptCoordinationManaging {
    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter)
}

/// Manages the coordination and presentation of modal prompts based on priority and cooldown rules.
///
/// This manager is responsible for:
/// - Enforcing global cooldown periods between modal presentations.
/// - Presenting the first eligible modal.
/// - Track when modals were last presented.
///
/// The manager does NOT handle app-lifecycle level concerns like launch source checking. Those are handled by the `ModalPromptsCoordinationService`.
@MainActor
final class ModalPromptCoordinationManager: ModalPromptCoordinationManaging {
    private let providers: [any ModalPromptProvider]
    private let cooldownManager: PromptCooldownManaging
    private let scheduler: ModalPromptScheduling

    /// Creates a new modal prompts coordination manager.
    ///
    /// - Parameters:
    ///   - providers: Array of providers in priority order (first = highest priority).
    ///   - cooldownManager: Manager for the cooldown period between prompts.
    init(
        providers: [any ModalPromptProvider],
        cooldownManager: PromptCooldownManaging,
        modalPromptScheduling: ModalPromptScheduling = ModalPromptScheduler()
    ) {
        self.providers = providers
        self.cooldownManager = cooldownManager
        self.scheduler = modalPromptScheduling
    }

    /// Attempts to present a modal prompt if one is eligible.
    ///
    /// The manager will:
    /// 1. Check cooldown period and skip presenting if it is active.
    /// 2. Iterate through providers in priority order.
    /// 3. Check if provider has a modal to show.
    /// 4. Present the first eligible modal.
    /// 5. Save the modal presentation date.
    ///
    /// - Parameter presenter: The view controller to present from.
    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter) {
        guard !cooldownManager.isInCooldownPeriod else {
            let cooldownInfo = cooldownManager.cooldownInfo
            let lastPresentationDate = cooldownInfo.lastPresentationDate.flatMap(String.init) ?? "-"
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Is in cooldown period. Last presentation: \(lastPresentationDate, privacy: .public) Can Present modal again: \(cooldownInfo.nextPresentationDate, privacy: .public)")
            return
        }

        for provider in providers {
            guard let modalPromptConfiguration = provider.provideModalPrompt() else { continue }

            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: provider))")
            presentModalPrompt(modalPromptConfiguration: modalPromptConfiguration, from: presenter) { [weak self] in
                self?.saveModalPromptLastPresentationDate()
                provider.didPresentModal()
            }
            return
        }

        Logger.modalPrompt.debug("[Modal Prompt Coordination] - No provider is eligible to present a modal.")
    }
}

// MARK: - Private

private extension ModalPromptCoordinationManager {

    func presentModalPrompt(modalPromptConfiguration: ModalPromptConfiguration, from presenter: ModalPromptPresenter, completion: @escaping (() -> Void)) {
        scheduler.schedule(after: 0.1) {
            presenter.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
        }
    }

    func saveModalPromptLastPresentationDate() {
        cooldownManager.recordLastPromptPresentationTimestamp()
    }

}
