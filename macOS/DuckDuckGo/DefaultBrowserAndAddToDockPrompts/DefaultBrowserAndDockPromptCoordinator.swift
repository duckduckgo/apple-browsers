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

    /// Gets the prompt type based on the user's eligibility for the experiment.
    ///
    /// This function checks if the user is eligible for the "Popover vs Banner Experiment" by evaluating the following conditions:
    /// 1. The user has completed the onboarding process (`wasOnboardingCompleted`).
    /// 2. The user is not a new user, this means a week had passed since the first launch (`AppDelegate.isNewUser`).
    /// 3. The `evaluatePromptEligibility` closure is not `nil`, indicating that the user has not set the user as default or did not add the browser to the dock.
    ///
    /// If the user is eligible, the function resolves the user's cohort for the "Popover vs Banner Experiment" feature flag. Based on the user's cohort, the function will post a notification to display either a banner prompt or a popover prompt for the default browser setting.
    ///
    /// - Note: The `FeatureFlag.PopoverVSBannerExperimentCohort` enum represents the different cohorts for the experiment, with the `control` cohort not displaying any prompt.
    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType?

    func markPromptAsShown()
    func wasPromptShown() -> Bool
    func onPromptConfirmation()
}

final class DefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
    enum Constants {
        static let subfeatureID = FeatureFlag.popoverVsBannerExperiment.rawValue

        /// Metric identifiers for the user actions around the experiment
        static let userSetAsDefaultOrAddedToDock = "userSetAsDefaultOrAddedToDock"
        static let value = "1"

        static let conversionWindowDays = 0...28
    }

    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let featureFlagger: FeatureFlagger
    private let repository: DefaultBrowserAndDockPromptRepository

    private var cancellables: Set<AnyCancellable> = []

#if SPARKLE
    private let isSparkleBuild: Bool = true
#else
    private let isSparkleBuild: Bool = false
#endif

    init(dockCustomization: DockCustomization = DockCustomizer(),
         defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         repository: DefaultBrowserAndDockPromptRepository = DefaultBrowserAndDockPromptRepositoryImpl()) {
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.featureFlagger = featureFlagger
        self.repository = repository

        subscribeToLocalOverride()
    }

    private var isUserEligibleForExperiment: Bool {
        let wasOnboardingCompleted = Application.appDelegate.onboardingStateMachine.state == .onboardingCompleted
        return !AppDelegate.isNewUser && wasOnboardingCompleted && evaluatePromptEligibility != nil
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

    static func fireSetAsDefaultAddToDockExperimentPixel() {
        PixelKit.fireExperimentPixel(
            for: DefaultBrowserAndDockPromptCoordinator.Constants.subfeatureID,
            metric: DefaultBrowserAndDockPromptCoordinator.Constants.userSetAsDefaultOrAddedToDock,
            conversionWindowDays: DefaultBrowserAndDockPromptCoordinator.Constants.conversionWindowDays,
            value: DefaultBrowserAndDockPromptCoordinator.Constants.value
        )
    }

    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType? {
        guard isUserEligibleForExperiment else { return nil }

        guard let cohort = Application.appDelegate.featureFlagger.resolveCohort(for: FeatureFlag.popoverVsBannerExperiment) as? FeatureFlag.PopoverVSBannerExperimentCohort else { return nil }

        switch cohort {
        case .control: return nil
        case .banner: return .banner
        case .popover: return .popover
        }
    }

    func wasPromptShown() -> Bool {
        return repository.wasPromptShown()
    }

    func markPromptAsShown() {
        repository.setPromptShown(true)
    }

    func onPromptConfirmation() {
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

    // MARK: - Private

    private func setAsDefaultBrowserAction() {
        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    private func subscribeToLocalOverride() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.experimentFlagDidChangePublisher
            .filter { $0.0 == .popoverVsBannerExperiment }
            .sink { (_, cohort) in
                guard let _ = FeatureFlag.PopoverVSBannerExperimentCohort.cohort(for: cohort) else { return }

                NotificationCenter.default.post(name: .showPromptForSetAsDefaultBrowserAndAddToDock, object: nil)
            }
            .store(in: &cancellables)
    }
}
