//
//  NewTabDaxDialogAbstractFactory.swift
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

import Foundation
import PrivacyConfig
import SwiftUI
import Onboarding
import Subscription
import Common

final class NewTabDaxDialogProvider: NewTabDaxDialogProviding {
    private let factory: any NewTabDaxDialogProviding

    init(
        featureFlagger: FeatureFlagger,
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = OnboardingSubscriptionPromotionHelper()
    ) {
        if featureFlagger.isFeatureOn(.onboardingRebranding) {
            factory = RebrandedNewTabDaxDialogFactory(
                delegate: delegate,
                daxDialogsFlowCoordinator: daxDialogsFlowCoordinator,
                onboardingPixelReporter: onboardingPixelReporter,
                onboardingSubscriptionPromotionHelper: onboardingSubscriptionPromotionHelper
            )
        } else {
            factory = NewTabDaxDialogFactory(
                delegate: delegate,
                daxDialogsFlowCoordinator: daxDialogsFlowCoordinator,
                onboardingPixelReporter: onboardingPixelReporter,
                onboardingSubscriptionPromotionHelper: onboardingSubscriptionPromotionHelper
            )
        }
    }


    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        AnyView(factory.createDaxDialog(for: homeDialog, onCompletion: onCompletion, onManualDismiss: onManualDismiss))
    }

}
