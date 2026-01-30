//
//  RebrandedNewTabDaxDialogFactory.swift
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
import SwiftUI
import Onboarding
import Subscription
import Common

final class RebrandedNewTabDaxDialogFactory: NewTabDaxDialogProviding {
    private var delegate: OnboardingNavigationDelegate?
    private var daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping

    init(
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = OnboardingSubscriptionPromotionHelper()
    ) {
        self.delegate = delegate
        self.daxDialogsFlowCoordinator = daxDialogsFlowCoordinator
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingSubscriptionPromotionHelper = onboardingSubscriptionPromotionHelper
    }

    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        let button: Button<Text>
        switch homeDialog {
        case .initial:
            button = Button(action: { self.delegate?.searchFromOnboarding(for: "Baby Ducklings") }) {
                Text(verbatim: "Try A Search!!!")
            }
        case .addFavorite:
            button = Button(action: onManualDismiss) {
                Text(verbatim: "Add Favourite!!!")
            }
        case .subsequent:
            button = Button(action: onManualDismiss) {
                Text(verbatim: "Try Visiting A Site!!!")
            }
        case .final:
            button = Button(action: { onCompletion(true) }) {
                Text(verbatim: "End Of Joruney Dialog!!!")
            }
        case .subscriptionPromotion:
            button = Button(action: { onCompletion(true) }) {
                Text(verbatim: "Add Favourite!!!")
            }
        }

        return VStack {
            button
        }
        .padding(50)
    }
}
