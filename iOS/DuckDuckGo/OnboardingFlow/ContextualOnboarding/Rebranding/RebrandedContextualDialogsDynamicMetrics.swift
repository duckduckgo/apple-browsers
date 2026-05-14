//
//  RebrandedContextualDialogsDynamicMetrics.swift
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
import MetricBuilder

extension OnboardingRebranding {

    enum ContextualDynamicMetrics {
        /// Builds a device-specific dialog orientation, using `horizontalAlignment` only when the layout is horizontal.
        /// - Parameter horizontalAlignment: Alignment for the horizontal stack (used on iPhone landscape and iPad).
        static func dialogOrientation(
            horizontalAlignment: VerticalAlignment = .top
        ) -> MetricBuilder<OnboardingRebranding.ContextualDaxDialogOrientation> {
            MetricBuilder<OnboardingRebranding.ContextualDaxDialogOrientation>(default: .verticalStack)
                .iPhone(portrait: .verticalStack, landscape: .horizontalStack(alignment: horizontalAlignment))
                .iPad(.horizontalStack(alignment: horizontalAlignment))
        }
    }

}
