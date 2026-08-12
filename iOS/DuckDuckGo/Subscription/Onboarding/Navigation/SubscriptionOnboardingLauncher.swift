//
//  SubscriptionOnboardingLauncher.swift
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

@MainActor
enum SubscriptionOnboardingLauncher {

    static func launch(flow: SubscriptionOnboardingFlowViewModel) -> AnyView {
        AnyView(
            SubscriptionOnboardingFlowView(flow: flow,
                                           factory: SubscriptionOnboardingViewFactory(flow: flow))
                .graphicLottieRenderer(.app))
    }
}

// MARK: - Flows to launch

extension SubscriptionOnboardingFlowViewModel {

    /// Walks the whole flow from the order confirmation.
    ///
    /// - Parameter pirScreen: pushed when the customer taps the summary's PIR row, which both entry points
    ///   can reach — the summary closes every sequence.
    static func postCheckout<PIRScreen: View>(progress: SubscriptionOnboardingProgress,
                                              onFinish: @escaping () -> Void,
                                              @ViewBuilder pirScreen: @escaping () -> PIRScreen)
    -> SubscriptionOnboardingFlowViewModel {
        SubscriptionOnboardingFlowViewModel(entryPoint: .postCheckout,
                                           progress: progress,
                                           onFinish: onFinish,
                                           pirScreen: pirScreen)
    }

    /// Resumes at the first unfinished section, and closes on the summary.
    static func subscriptionSettings<PIRScreen: View>(progress: SubscriptionOnboardingProgress,
                                                      onFinish: @escaping () -> Void,
                                                      @ViewBuilder pirScreen: @escaping () -> PIRScreen)
    -> SubscriptionOnboardingFlowViewModel {
        SubscriptionOnboardingFlowViewModel(entryPoint: .subscriptionSettings,
                                           progress: progress,
                                           onFinish: onFinish,
                                           pirScreen: pirScreen)
    }
}
