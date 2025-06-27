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

import UIKit
import SetDefaultBrowserCore

@MainActor
public enum DefaultBrowserPromptFactory {

    public static func makeDefaultBrowserPromptPresenter(
        featureFlagProvider: DefaultBrowserPromptFeatureFlagProvider,
        featureFlagSettingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider,
        promptActivityStore: DefaultBrowserPromptStorage,
        userTypeProviding: DefaultBrowserPromptUserTypeProviding,
        userActivityStore: DefaultBrowsePromptUserActivityStorage,
        checkDefaultBrowserContextStorage: DefaultBrowserContextStorage,
        checkDefaultBrowserDebugEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserManagerDebugEvent>,
        promptUserInteractionEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>,
        isOnboardingCompletedProvider: @escaping () -> Bool,
        installDateProvider: @escaping () -> Date?
    ) -> DefaultBrowserPromptPresenting {

        let featureFlagger = DefaultBrowserPromptFeatureFlag(
            settingsProvider: featureFlagSettingsProvider,
            featureFlagProvider: featureFlagProvider
        )

        let userActivityMonitor = DefaultBrowsePromptUserActivityMonitor(
            store: userActivityStore,
        )

        let defaultBrowserManager = DefaultBrowserManager(
            defaultBrowserInfoStore: checkDefaultBrowserContextStorage,
            defaultBrowserEventMapper: checkDefaultBrowserDebugEventMapper
        )

        let promptTypeDecider = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlagger,
            store: promptActivityStore,
            userTypeProvider: userTypeProviding,
            userActivityProvider: userActivityMonitor,
            defaultBrowserManager: defaultBrowserManager,
            installDateProvider: installDateProvider
        )

        let coordinator = DefaultBrowserPromptCoordinator(
            isOnboardingCompleted: isOnboardingCompletedProvider,
            promptStore: promptActivityStore,
            userActivityManager: userActivityMonitor,
            promptTypeDecider: promptTypeDecider,
            urlOpener: UIApplication.shared,
            eventMapper: promptUserInteractionEventMapper
        )

        return DefaultBrowserModalPresenter(coordinator: coordinator)
    }

}
