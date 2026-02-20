//
//  RebrandedAddToDockPromoView.swift
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

import Lottie
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoView: View {
        @State private var isAnimating = false

        var body: some View {
            ZStack(alignment: .center) {
                OnboardingRebrandingImages.AddToDock.promoBorder
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, -11)
                LottieView(
                    lottieFile: "add-to-dock-promo",
                    isAnimating: $isAnimating
                )
                .tempPlaceholder()
                .onFirstAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isAnimating = true
                    }
                }
            }
        }
    }

}
