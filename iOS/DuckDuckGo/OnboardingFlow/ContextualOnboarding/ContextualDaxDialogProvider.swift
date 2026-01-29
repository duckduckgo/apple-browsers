//
//  ContextualDaxDialogProvider.swift
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

final class ContextualDaxDialogProvider: ContextualDaxDialogsFactory {
    private let featureFlagger: FeatureFlagger
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let contextualOnboardingPixelReporter: OnboardingPixelReporting

    init(
        featureFlagger: FeatureFlagger,
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingPixelReporter: OnboardingPixelReporting
    ) {
        self.featureFlagger = featureFlagger
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.contextualOnboardingPixelReporter = contextualOnboardingPixelReporter
    }

    private var factory: ContextualDaxDialogsFactory {
        if featureFlagger.isFeatureOn(.onboardingRebranding) {
            return RebrandedContextualDaxDialogFactory(
                contextualOnboardingLogic: contextualOnboardingLogic,
                contextualOnboardingPixelReporter: contextualOnboardingPixelReporter
            )
        } else {
            return DefaultContextualDaxDialogsFactory(
                contextualOnboardingLogic: contextualOnboardingLogic,
                contextualOnboardingPixelReporter: contextualOnboardingPixelReporter
            )
        }
    }

    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: any ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView> {
        factory.makeView(for: spec, delegate: delegate, onSizeUpdate: onSizeUpdate)
    }

}
