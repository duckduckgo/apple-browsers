//
//  RebrandedOnboardingView_Previews.swift
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
import SystemSettingsPiPTutorial
import UIKit

struct RebrandedOnboardingView_Previews: PreviewProvider {
    class MockDaxDialogDisabling: ContextualDaxDialogDisabling {
        func disableContextualDaxDialogs() {}
    }

    static var previews: some View {
        ForEach(ColorScheme.allCases, id: \.self) {
            RebrandedOnboardingView(
                model: .init(
                    pixelReporter: OnboardingPixelReporter(),
                    systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManager(
                        playerView: UIView(),
                        videoPlayer: VideoPlayerCoordinator(configuration: VideoPlayerConfiguration()),
                        eventMapper: SystemSettingsPiPTutorialPixelHandler()
                    ),
                    daxDialogsManager: MockDaxDialogDisabling()
                )
            )
            .preferredColorScheme($0)
        }
    }
}

#Preview("Rebranded Landing Light") {
    RebrandedOnboardingView.LandingView(animationNamespace: Namespace().wrappedValue)
        .preferredColorScheme(.light)
}

#Preview("Rebranded Landing Dark") {
    RebrandedOnboardingView.LandingView(animationNamespace: Namespace().wrappedValue)
        .preferredColorScheme(.dark)
}

#Preview("Rebranded Address Bar Position") {
    RebrandedOnboardingView.AddressBarPositionContent(isSkipped: .constant(false), action: {})
}

#Preview("Rebranded Search Experience") {
    RebrandedOnboardingView.SearchExperienceContent(isSkipped: .constant(false), action: {})
}

#Preview("Rebranded App Icon Picker") {
    RebrandedOnboardingView.AppIconPicker()
}

#Preview("Rebranded Add To Dock Promo") {
    RebrandedOnboardingView.AddToDockPromoView()
}

#Preview("Rebranded Add To Dock Tutorial") {
    RebrandedOnboardingView.AddToDockTutorialView(
        title: UserText.AddToDockOnboarding.Tutorial.title,
        message: UserText.AddToDockOnboarding.Tutorial.message,
        cta: UserText.AddToDockOnboarding.Buttons.startBrowsing,
        isSkipped: .constant(false),
        action: {}
    )
    .padding()
}

#Preview("Rebranded Progress Indicator") {
    struct PreviewWrapper: View {
        @State var stepInfo = LegacyOnboardingViewState.Intro.StepInfo(currentStep: 1, totalSteps: 3)

        var body: some View {
            VStack(spacing: 100) {
                RebrandedOnboardingView.OnboardingProgressIndicator(stepInfo: stepInfo)

                Button(action: {
                    let nextStep = stepInfo.currentStep < stepInfo.totalSteps ? stepInfo.currentStep + 1 : 1
                    stepInfo = LegacyOnboardingViewState.Intro.StepInfo(currentStep: nextStep, totalSteps: stepInfo.totalSteps)
                }, label: {
                    Text(verbatim: "Update Progress")
                })
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Rebranded Progress Bar") {
    RebrandedOnboardingView.ProgressBarView(progress: 80)
        .frame(width: 200, height: 8)
}
