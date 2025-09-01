//
//  DefaultBrowserPromptFactory.swift
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
import SetDefaultBrowserCore

@MainActor
public enum DefaultBrowserPromptFactory {

    public static func makeDefaultBrowserPromptPresenter(
        featureFlagProvider: DefaultBrowserPromptFeatureFlagProvider,
        featureFlagSettingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider,
        promptActivityStore: DefaultBrowserPromptStorage,
        userTypeProviding: DefaultBrowserPromptUserTypeProviding,
        userActivityManager: DefaultBrowserPromptUserActivityManaging,
        checkDefaultBrowserContextStorage: DefaultBrowserContextStorage,
        defaultBrowserSettingsNavigator: DefaultBrowserPromptSettingsNavigating,
        checkDefaultBrowserDebugEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserManagerDebugEvent>,
        promptUserInteractionEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>,
        uiProvider: any DefaultBrowserPromptUIProviding,
        isOnboardingCompletedProvider: @escaping () -> Bool,
        installDateProvider: @escaping () -> Date?,
        currentDateProvider: @escaping () -> Date
    ) -> DefaultBrowserPromptPresenting {

        let featureFlagger = DefaultBrowserPromptFeatureFlag(
            settingsProvider: featureFlagSettingsProvider,
            featureFlagProvider: featureFlagProvider
        )

        let defaultBrowserManager = DefaultBrowserManager(
            defaultBrowserInfoStore: checkDefaultBrowserContextStorage,
            defaultBrowserEventMapper: checkDefaultBrowserDebugEventMapper
        )

        let promptTypeDecider = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlagger,
            store: promptActivityStore,
            userTypeProvider: userTypeProviding,
            userActivityProvider: userActivityManager,
            defaultBrowserManager: defaultBrowserManager,
            installDateProvider: installDateProvider,
            dateProvider: currentDateProvider
        )

        let coordinator = DefaultBrowserPromptCoordinator(
            isOnboardingCompleted: isOnboardingCompletedProvider,
            promptStore: promptActivityStore,
            userActivityManager: userActivityManager,
            promptTypeDecider: promptTypeDecider,
            defaultBrowserSettingsNavigator: defaultBrowserSettingsNavigator,
            eventMapper: promptUserInteractionEventMapper,
            dateProvider: currentDateProvider
        )

        return DefaultBrowserModalPresenter(coordinator: coordinator, uiProvider: uiProvider)
    }

}
