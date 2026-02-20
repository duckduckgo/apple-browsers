//
//  ContextualDaxDialogsProvider.swift
//  DuckDuckGo
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
import Core
import PrivacyConfig

final class ContextualDaxDialogsProvider: ContextualDaxDialogsFactory {
    private let featureFlagger: FeatureFlagger
    private let legacyDaxDialogsFactory: ContextualDaxDialogsFactory
    private let rebrandedDaxDialogsFactory: ContextualDaxDialogsFactory

    convenience init(
        featureFlagger: FeatureFlagger,
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingPixelReporter: OnboardingPixelReporting
    ) {

        let legacyDaxDialogsFactory = DefaultContextualDaxDialogsFactory(
            contextualOnboardingLogic: contextualOnboardingLogic,
            contextualOnboardingPixelReporter: contextualOnboardingPixelReporter
        )

        let rebrandedDaxDialogsFactory = RebrandedContextualDaxDialogFactory(
            contextualOnboardingLogic: contextualOnboardingLogic,
            contextualOnboardingPixelReporter: contextualOnboardingPixelReporter
        )

        self.init(featureFlagger: featureFlagger, legacyDaxDialogsFactory: legacyDaxDialogsFactory, rebrandedDaxDialogsFactory: rebrandedDaxDialogsFactory)
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

    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: any ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView> {
        factory.makeView(for: spec, delegate: delegate, onSizeUpdate: onSizeUpdate)
    }

}
