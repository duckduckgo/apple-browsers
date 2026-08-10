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

/// Assembles the flow's root view. The caller builds the view model, so this holds no dependencies of its own.
@MainActor
enum SubscriptionOnboardingLauncher {

    /// - Parameter onFinish: fires when the customer leaves the flow. Supplied here rather than to the view
    ///   model because how the flow closes belongs to whoever presented it.
    static func launch(flow: SubscriptionOnboardingFlowViewModel,
                       onFinish: @escaping () -> Void) -> AnyView {
        flow.onFinish = onFinish
        return AnyView(
            SubscriptionOnboardingFlowView(flow: flow,
                                           factory: SubscriptionOnboardingViewFactory(flow: flow))
                .graphicLottieRenderer(SubscriptionOnboardingLottieRenderer.shared))
    }
}
