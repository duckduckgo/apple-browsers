//
//  OnboardingBubbleView.swift
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

#if DEBUG
import SwiftUI
import Onboarding

// MARK: - Preview

#Preview("Onboarding Speech Bubble") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: .bottom(offset: 0.4, direction: .leading)) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Progress Indicator") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withStepProgressIndicator(
            tailPosition: .bottom(offset: 0, direction: .leading),
            currentStep: 1, totalSteps: 5
        ) {
                VStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .center, spacing: 28) {
                        Text(verbatim: "Hi there.")
                            .font(.system(size: 24, weight: .bold))

                        Text(verbatim: "Ready for a better, more private internet?")
                            .font(.system(size: 18))
                    }
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                    Button(action: { }) {
                        Text(verbatim: "Let's do it!")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.black)
                            .padding()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                    .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                    .cornerRadius(64)
                }
            }
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Dismiss Button") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withDismissButton(
            tailPosition: .bottom(offset: 0, direction: .leading),
            onDismiss: {}
        ) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble No Tail") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: nil) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
