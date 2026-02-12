//
//  RebrandedOnboardingView+Landing.swift
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

private enum LandingViewMetrics {
    static let logoSize: CGFloat = 80
    static let topPadding: CGFloat = 96
    static let welcomeBottomPadding: CGFloat = 20
    static let horizontalPadding: CGFloat = 40
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct LandingView: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        let animationNamespace: Namespace.ID

        var body: some View {
            VStack(spacing: 0) {
                welcomeView
                    .padding(.top, LandingViewMetrics.topPadding)

                Spacer()
            }
        }

        private var welcomeView: some View {
            VStack(alignment: .center, spacing: LandingViewMetrics.welcomeBottomPadding) {
                OnboardingRebrandingImages.Branding.duckDuckGoLogo
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: LandingViewMetrics.logoSize, height: LandingViewMetrics.logoSize)

                Text(UserText.onboardingWelcomeHeader)
                    .font(onboardingTheme.typography.largeTitle)
                    .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LandingViewMetrics.horizontalPadding)
        }

    }

}
