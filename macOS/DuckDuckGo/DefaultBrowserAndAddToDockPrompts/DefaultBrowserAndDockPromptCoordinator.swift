//
//  DefaultBrowserAndDockPromptCoordinator.swift
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

import Combine
import SwiftUI
import SwiftUIExtensions
import BrowserServicesKit
import FeatureFlags
import PixelKit

enum DefaultBrowserAndDockPromptDismissAction: Equatable {
    case userInput(prompt: DefaultBrowserAndDockPromptPresentationType, shouldHidePermanently: Bool)
    case statusUpdate(prompt: DefaultBrowserAndDockPromptPresentationType)
}

protocol DefaultBrowserAndDockPrompt {
    /// Evaluates the user's eligibility for the default browser and dock prompt, and returns the appropriate
    /// `DefaultBrowserAndDockPromptType` value based on the user's current state (default browser status, dock status, and whether it's a Sparkle build).
    ///
    /// The implementation checks the following conditions:
    /// - If this is a Sparkle build:
    ///   - If the user has both set DuckDuckGo as the default browser and added it to the dock, they are not eligible for any prompt (returns `nil`).
    ///   - If the user has set DuckDuckGo as the default browser but hasn't added it to the dock, it returns `.addToDockPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser but has added it to the dock, it returns `.setAsDefaultPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser and hasn't added it to the dock, it returns `.bothDefaultBrowserAndDockPrompt`.
    /// - If this is not a Sparkle build, it only returns `.setAsDefaultPrompt` if the user hasn't already set DuckDuckGo as the default browser (otherwise, it returns `nil`).
    ///
    /// - Returns: The appropriate `DefaultBrowserAndDockPromptType` value, or `nil` if the user is not eligible for any prompt.
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType? { get }

    /// Gets the prompt type based on the prompts scheduling time.
    ///
    /// This function checks the type of prompt to return by evaluating the following conditions:
    /// 1. The user has completed the onboarding process (`wasOnboardingCompleted`).
    /// 2. The `evaluatePromptEligibility` is not `nil`, indicating that the user has not set the user as default or did not add the browser to the dock.
    ///
    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType?

    /// Called when the prompt CTA is clicked.
    /// - Parameter prompt: The type of prompt the user interacted with.
    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType)

    /// Called when the cancel CTA is clicked
    /// - Parameters:
    ///   - prompt: The type of prompt the user interacted with.
    ///   - shouldHidePermanently: A boolean flag indicating whether the user has decided not to see the prompt again.
    func dismissAction(_ action: DefaultBrowserAndDockPromptDismissAction)
}

final class DefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {

    private let promptTypeDecider: DefaultBrowserAndDockPromptTypeDeciding
    private let store: DefaultBrowserAndDockPromptStorageWriting
    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let isSparkleBuild: Bool
    private let isOnboardingCompleted: Bool
    private let dateProvider: () -> Date

    init(
        promptTypeDecider: DefaultBrowserAndDockPromptTypeDeciding,
        store: DefaultBrowserAndDockPromptStorageWriting,
        isOnboardingCompleted: Bool,
        dockCustomization: DockCustomization = DockCustomizer(),
        defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
        applicationBuildType: ApplicationBuildType = StandardApplicationBuildType(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.promptTypeDecider = promptTypeDecider
        self.store = store
        self.isOnboardingCompleted = isOnboardingCompleted
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.isSparkleBuild = applicationBuildType.isSparkleBuild
        self.dateProvider = dateProvider
    }

    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType? {
        let isDefaultBrowser = defaultBrowserProvider.isDefault
        let isAddedToDock = dockCustomization.isAddedToDock

        if isSparkleBuild {
            if isDefaultBrowser && isAddedToDock {
                return nil
            } else if isDefaultBrowser && !isAddedToDock {
                return .addToDockPrompt
            } else if !isDefaultBrowser && isAddedToDock {
                return .setAsDefaultPrompt
            } else {
                return .bothDefaultBrowserAndDockPrompt
            }
        } else {
            return isDefaultBrowser ? nil : .setAsDefaultPrompt
        }
    }

    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType? {
        // If user has not completed the onboarding do not show any prompts.
        guard isOnboardingCompleted else { return nil }

        // If user has set browser as default and app is added to the dock do not show any prompts.
        guard evaluatePromptEligibility != nil else { return nil }

        let prompt = promptTypeDecider.promptType()

        // For the popover we mark it as shown when it appears on screen as we don't want to show in every windows.
        if prompt == .popover {
            setPopoverSeen()
        }

        return prompt
    }

    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {

        func setDefaultBrowserAndAddToDockIfNeeded() {
            guard let type = evaluatePromptEligibility else { return }

            switch type {
            case .bothDefaultBrowserAndDockPrompt:
                dockCustomization.addToDock()
                setAsDefaultBrowserAction()
            case .addToDockPrompt:
                dockCustomization.addToDock()
            case .setAsDefaultPrompt:
                setAsDefaultBrowserAction()
            }
        }

        func fireActionPixel() {

        }

        func setPromptSeen() {
            // Do not set popover seen when user interacting with it. Popover is intrusive and we don't want to show in every windows. We set seen when we show it on screen.
            guard prompt == .banner else { return }
            // Set the banner seen only when the user interact with it because we want to show it in every windows.
            setBannerSeen(shouldHidePermanently: false)
        }

        setDefaultBrowserAndAddToDockIfNeeded()
        setPromptSeen()
        fireActionPixel()
    }

    func dismissAction(_ action: DefaultBrowserAndDockPromptDismissAction) {
        switch action {
        case let .userInput(prompt, shouldHidePermanently):
            handleUserInputDismissAction(for: prompt, shouldHidePermanently: shouldHidePermanently)
        case let .statusUpdate(prompt: prompt):
            handleSystemUpdateDismissAction(for: prompt)
        }
    }

}

// MARK: - Private

private extension DefaultBrowserAndDockPromptCoordinator {

    func setAsDefaultBrowserAction() {
        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    func setPopoverSeen() {
        store.popoverShownDate = dateProvider().timeIntervalSince1970
    }

    func setBannerSeen(shouldHidePermanently: Bool) {
        store.bannerShownDate = dateProvider().timeIntervalSince1970
        if shouldHidePermanently {
            store.isBannerPermanentlyDismissed = true
        }
    }

    func handleUserInputDismissAction(for prompt: DefaultBrowserAndDockPromptPresentationType, shouldHidePermanently: Bool) {
        switch prompt {
        case .popover:
            // Send Pixel
            break
        case .banner:
            // Send Pixel
            // Set the banner seen only when the user interact with it because we want to show it in every windows.
            setBannerSeen(shouldHidePermanently: shouldHidePermanently)
        }
    }

    func handleSystemUpdateDismissAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {
        // The popover is set seen when is presented as we don't want to show it in every windows.
        guard prompt == .banner else { return }
        setBannerSeen(shouldHidePermanently: false)
    }
}
