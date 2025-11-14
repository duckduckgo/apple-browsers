//
//  OnboardingView+SearchExperienceContent.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DuckUI
import Onboarding

extension OnboardingView {
    struct SearchExperienceContent: View {
        private var animateTitle: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let action: () -> Void
        
        @State private var animateMessage = false
        @State private var showContent = false

        init(animateTitle: Binding<Bool> = .constant(true),
             isSkipped: Binding<Bool>,
             action: @escaping () -> Void) {
            self.animateTitle = animateTitle
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(UserText.Onboarding.SearchExperience.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    animateMessage = true
                }
                .foregroundColor(.primary)
                .font(Metrics.titleFont)

                AnimatableTypingText(UserText.Onboarding.SearchExperience.subtitleAttributed(), startAnimating: $animateMessage, skipAnimation: isSkipped) {
                    withAnimation {
                        showContent = true
                    }
                }
                .foregroundColor(.primary)
                .font(Metrics.messageFont)

                VStack(spacing: 24.0) {
                    OnboardingSearchExperiencePicker()
                    
                    Text(AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()))
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: action) {
                        Text(UserText.Onboarding.SearchExperience.cta)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 8)
                .visibility(showContent ? .visible : .invisible)
            }
        }
    }
}

private enum Metrics {
    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let messageFont = Font.system(size: 16)
}

// MARK: - Preview

#Preview {
    OnboardingView.SearchExperienceContent(isSkipped: .constant(false), action: {})
}
