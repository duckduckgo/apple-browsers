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

// Represent the type of the modal to display for active/inactive user. Currently only active.
// More info for inactive users: https://app.asana.com/1/137249556945/project/492600419927320/task/1210568683672934?focus=true
package enum DefaultBrowserPromptPresentationType {
    case activeUserModal
    case inactiveUserModal

    init(_ prompt: DefaultBrowserPromptType) {
        switch prompt {
        case .firstModal, .secondModal, .subsequentModal:
            self = .activeUserModal
        }
    }
}

@MainActor
package protocol DefaultBrowserPromptCoordinating: AnyObject {
    func getPrompt() -> DefaultBrowserPromptPresentationType?

    func setDefaultBrowserAction()
    func dismissAction(shouldDismissPromptPermanently: Bool)
}

@MainActor
package final class DefaultBrowserPromptCoordinator {
    private let isOnboardingCompleted: () -> Bool
    private let promptStore: DefaultBrowserPromptStorage
    private let userActivityManager: DefaultBrowserPromptUserActivityManaging
    private let promptTypeDecider: DefaultBrowserPromptTypeDeciding
    private let urlOpener: URLOpener
    private let eventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>
    private let dateProvider: () -> Date

    package init(
        isOnboardingCompleted: @escaping () -> Bool,
        promptStore: DefaultBrowserPromptStorage,
        userActivityManager: DefaultBrowserPromptUserActivityManaging,
        promptTypeDecider: DefaultBrowserPromptTypeDeciding,
        urlOpener: URLOpener,
        eventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.isOnboardingCompleted = isOnboardingCompleted
        self.promptStore = promptStore
        self.userActivityManager = userActivityManager
        self.promptTypeDecider = promptTypeDecider
        self.urlOpener = urlOpener
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

        setPromptSeen()
        resetUserActivity()

        return DefaultBrowserPromptPresentationType(prompt)
    }

    package func setDefaultBrowserAction() {
        // Open Settings
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }

        urlOpener.open(url)

        // Send event
        fireSetUserDefaultEvent()
    }
    
    package func dismissAction(shouldDismissPromptPermanently: Bool) {
        promptStore.isPromptPermanentlyDismissed = shouldDismissPromptPermanently
        fireDismissedPromptEvent(shouldDismissPromptPermanently: shouldDismissPromptPermanently)
    }
}


// MARK: - Private

private extension DefaultBrowserPromptCoordinator {

    func setPromptSeen() {
        let now = dateProvider()
        promptStore.lastModalShownDate = now.timeIntervalSince1970
        promptStore.modalShownOccurrences += 1
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Set Prompt Seen \(now).")
        firePromptSeenEvent()
    }

    func resetUserActivity() {
        userActivityManager.resetNumberOfActiveDays()
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - User Activity Reset.")
    }

    func firePromptSeenEvent() {
        eventMapper.fire(.modalShown(numberOfModalShown: promptStore.modalShownOccurrences))
    }

    func fireDismissedPromptEvent(shouldDismissPromptPermanently: Bool) {
        if shouldDismissPromptPermanently {
            eventMapper.fire(.modalDismissedPermanently)
        } else {
            eventMapper.fire(.modalDismissed)
        }
    }

    func fireSetUserDefaultEvent() {
        eventMapper.fire(.modalActioned(numberOfModalShown: promptStore.modalShownOccurrences))
    }
}
