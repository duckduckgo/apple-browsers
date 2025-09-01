//
//  DefaultBrowserPromptCoordinator.swift
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

import Foundation
import class UIKit.UIApplication

// Represent the type of the modal to display for active/inactive user.
package enum DefaultBrowserPromptPresentationType {
    case activeUserModal
    case inactiveUserModal

    init(_ prompt: DefaultBrowserPromptType) {
        switch prompt {
        case .inactive:
            self = .inactiveUserModal
        case .active:
            self = .activeUserModal
        }
    }
}

@MainActor
package protocol DefaultBrowserPromptCoordinating: AnyObject {
    func getPrompt() -> DefaultBrowserPromptPresentationType?

    func setDefaultBrowserAction(forPrompt prompt: DefaultBrowserPromptPresentationType)
    func dismissAction(forPrompt prompt: DefaultBrowserPromptPresentationType, shouldDismissPromptPermanently: Bool)
    func moreProtectionsAction()
}

@MainActor
package final class DefaultBrowserPromptCoordinator {
    private let isOnboardingCompleted: () -> Bool
    private let promptStore: DefaultBrowserPromptStorage
    private let userActivityManager: DefaultBrowserPromptUserActivityManaging
    private let promptTypeDecider: DefaultBrowserPromptTypeDeciding
    private let defaultBrowserSettingsNavigator: DefaultBrowserPromptSettingsNavigating
    private let eventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>
    private let dateProvider: () -> Date

    package init(
        isOnboardingCompleted: @escaping () -> Bool,
        promptStore: DefaultBrowserPromptStorage,
        userActivityManager: DefaultBrowserPromptUserActivityManaging,
        promptTypeDecider: DefaultBrowserPromptTypeDeciding,
        defaultBrowserSettingsNavigator: DefaultBrowserPromptSettingsNavigating,
        eventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.isOnboardingCompleted = isOnboardingCompleted
        self.promptStore = promptStore
        self.userActivityManager = userActivityManager
        self.promptTypeDecider = promptTypeDecider
        self.defaultBrowserSettingsNavigator = defaultBrowserSettingsNavigator
        self.eventMapper = eventMapper
        self.dateProvider = dateProvider
    }
}

// MARK: - DefaultBrowserPromptCoordinating

extension DefaultBrowserPromptCoordinator: DefaultBrowserPromptCoordinating {

    package func getPrompt() -> DefaultBrowserPromptPresentationType? {
        // If user has not completed the onboarding do not show any prompts.
        guard isOnboardingCompleted() else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Onboarding not completed, not showing prompt.")
            return nil
        }

        // Set prompt seen
        guard let prompt = promptTypeDecider.promptType() else { return nil }

        setPromptSeen(prompt: prompt)
        resetUserActivity()

        return DefaultBrowserPromptPresentationType(prompt)
    }

    package func setDefaultBrowserAction(forPrompt prompt: DefaultBrowserPromptPresentationType) {
        // Navigate To Settings
        defaultBrowserSettingsNavigator.navigateToSetDefaultBrowserSettings()

        // Send event
        fireSetUserDefaultEvent(prompt: prompt)
    }
    
    package func dismissAction(forPrompt prompt: DefaultBrowserPromptPresentationType, shouldDismissPromptPermanently: Bool) {
        if case .activeUserModal = prompt, shouldDismissPromptPermanently {
            promptStore.isPromptPermanentlyDismissed = shouldDismissPromptPermanently
        }
        fireDismissedPromptEvent(prompt: prompt, shouldDismissPromptPermanently: shouldDismissPromptPermanently)
    }

    package func moreProtectionsAction() {
        eventMapper.fire(.inactiveModalMoreProtectionsAction)
    }
}


// MARK: - Private

private extension DefaultBrowserPromptCoordinator {

    func setPromptSeen(prompt: DefaultBrowserPromptType) {
        let now = dateProvider()
        // The last shown date is stored regardless of the prompt type.
        // When displaying a prompt, we calculate the number of active days to determine if an active user prompt should be shown based on the last prompt (active/inactive) the user has seen.
        // We increment the prompt counter only for active prompts, as this counter helps decide whether to show the first or second prompt.
        // For inactive prompts, we set a flag instead, since they are only displayed once.
        promptStore.lastModalShownDate = now.timeIntervalSince1970
        if prompt == .inactive {
            promptStore.hasInactiveModalShown = true
        } else {
            promptStore.modalShownOccurrences += 1
        }
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Set Prompt Seen \(now).")
        firePromptSeenEvent(prompt: prompt)
    }

    func resetUserActivity() {
        userActivityManager.resetNumberOfActiveDays()
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - User Activity Reset.")
    }

    func firePromptSeenEvent(prompt: DefaultBrowserPromptType) {
        switch prompt {
        case .active:
            eventMapper.fire(.activeModalShown(numberOfModalShown: promptStore.modalShownOccurrences))
        case .inactive:
            eventMapper.fire(.inactiveModalShown)
        }
    }

    func fireDismissedPromptEvent(prompt: DefaultBrowserPromptPresentationType, shouldDismissPromptPermanently: Bool) {
        switch prompt {
        case .activeUserModal:
            if shouldDismissPromptPermanently {
                eventMapper.fire(.activeModalDismissedPermanently)
            } else {
                eventMapper.fire(.activeModalDismissed)
            }
        case .inactiveUserModal:
            eventMapper.fire(.inactiveModalDismissed)
        }
    }

    func fireSetUserDefaultEvent(prompt: DefaultBrowserPromptPresentationType) {
        switch prompt {
        case .activeUserModal:
            eventMapper.fire(.activeModalActioned(numberOfModalShown: promptStore.modalShownOccurrences))
        case .inactiveUserModal:
            eventMapper.fire(.inactiveModalActioned)
        }
    }
}
