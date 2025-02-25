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
    var isUserEligibleForPrompt: Bool { get }
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType? { get }

    func onPromptConfirmation(for content: DefaultBrowserAndDockPromptContent)
    func onPromptDismissed(for content: DefaultBrowserAndDockPromptContent)
}

final class DefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
    enum Constants {
        static let subfeatureID = FeatureFlag.popoverVsBannerExperiment.rawValue

        /// Metric identifiers for the user actions around the experiment
        static let userDismissedBanner = "userDismissedBanner"
        static let userDismissedPopover = "userDismissedPopover"
        static let userActionedBanner = "userActionedBanner"
        static let userActionedPopover = "userActionedPopover"

        static let conversionWindowDays = 0...3
    }

    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let featureFlagger: FeatureFlagger

    private var cancellables: Set<AnyCancellable> = []

#if SPARKLE
    private let isSparkleBuild: Bool = true
#else
    private let isSparkleBuild: Bool = false
#endif

    init(dockCustomization: DockCustomization = DockCustomizer(),
         defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.featureFlagger = featureFlagger

        subscribeToExperiment()
    }

    var isUserEligibleForPrompt: Bool {
        let wasOnboardingCompleted = true // TODO: Swap for real value
        return AppDelegate.twoDaysPassedSinceFirstLaunch && wasOnboardingCompleted
    }

    private func subscribeToExperiment() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.experimentFlagDidChangePublisher
            .filter { $0.0 == .popoverVsBannerExperiment }
            .sink { (_, cohort) in
                guard let newCohort = FeatureFlag.PopoverVSBannerExperimentCohort.cohort(for: cohort) else { return }
                switch newCohort {
                case .control: print("No-op")
                case .popover:
                    NotificationCenter.default.post(name: .showPopoverPromptForDefaultBrowser, object: nil)
                case .banner:
                    NotificationCenter.default.post(name: .showBannerPromptForDefaultBrowser, object: nil)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

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

    func onPromptConfirmation(for content: DefaultBrowserAndDockPromptContent) {
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

        trackPromptConfirmation(for: content)
    }

    func onPromptDismissed(for content: DefaultBrowserAndDockPromptContent) {
        trackPromptDismissal(for: content)
        /// TODO: Save a flag in user defaults so we do not show the popover or banner again.
    }

    private func setAsDefaultBrowserAction() {
        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    private func trackPromptConfirmation(for content: DefaultBrowserAndDockPromptContent) {
        switch content {
        case .popover:
            PixelKit.fireExperimentPixel(
                for: Constants.subfeatureID,
                metric: Constants.userActionedPopover,
                conversionWindowDays: Constants.conversionWindowDays,
                value: ""
            )
        case .banner:
            PixelKit.fireExperimentPixel(
                for: FeatureFlag.popoverVsBannerExperiment.rawValue,
                metric: Constants.userActionedBanner,
                conversionWindowDays: Constants.conversionWindowDays,
                value: ""
            )
        }
    }

    private func trackPromptDismissal(for content: DefaultBrowserAndDockPromptContent) {
        switch content {
        case .popover:
            PixelKit.fireExperimentPixel(
                for: Constants.subfeatureID,
                metric: Constants.userDismissedPopover,
                conversionWindowDays: Constants.conversionWindowDays,
                value: ""
            )
        case .banner:
            PixelKit.fireExperimentPixel(
                for: FeatureFlag.popoverVsBannerExperiment.rawValue,
                metric: Constants.userDismissedBanner,
                conversionWindowDays: Constants.conversionWindowDays,
                value: ""
            )
        }
    }
}
