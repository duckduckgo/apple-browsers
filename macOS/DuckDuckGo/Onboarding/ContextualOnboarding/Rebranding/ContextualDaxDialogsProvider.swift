//
//  ContextualDaxDialogsProvider.swift
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

import SwiftUI
import Onboarding
import FeatureFlags
import PrivacyConfig

final class ContextualDaxDialogsProvider: ContextualDaxDialogsFactory {
    private let featureFlagger: FeatureFlagger
    private let legacyDaxDialogsFactory: ContextualDaxDialogsFactory
    private let rebrandedDaxDialogsFactory: ContextualDaxDialogsFactory

    convenience init(
        featureFlagger: FeatureFlagger,
        onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(),
        fireCoordinator: FireCoordinator
    ) {
        let legacyFactory = DefaultContextualDaxDialogViewFactory(
            onboardingPixelReporter: onboardingPixelReporter,
            fireCoordinator: fireCoordinator
        )
        let rebrandedFactory = RebrandedContextualDaxDialogsFactory(
            onboardingPixelReporter: onboardingPixelReporter,
            fireCoordinator: fireCoordinator
        )
        self.init(
            featureFlagger: featureFlagger,
            legacyDaxDialogsFactory: legacyFactory,
            rebrandedDaxDialogsFactory: rebrandedFactory
        )
    }

    init(
        featureFlagger: FeatureFlagger,
        legacyDaxDialogsFactory: ContextualDaxDialogsFactory,
        rebrandedDaxDialogsFactory: ContextualDaxDialogsFactory
    ) {
        self.featureFlagger = featureFlagger
        self.legacyDaxDialogsFactory = legacyDaxDialogsFactory
        self.rebrandedDaxDialogsFactory = rebrandedDaxDialogsFactory
    }

    private var factory: ContextualDaxDialogsFactory {
        if featureFlagger.isFeatureOn(.onboardingRebranding) {
            rebrandedDaxDialogsFactory
        } else {
            legacyDaxDialogsFactory
        }
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> AnyView {
        factory.makeView(for: type, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed, onSuggestionPressed: onSuggestionPressed)
    }

}
