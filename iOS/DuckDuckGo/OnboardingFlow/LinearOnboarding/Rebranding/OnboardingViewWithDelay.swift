//
//  OnboardingViewWithDelay.swift
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

import Onboarding
import SwiftUI

extension OnboardingRebranding {

    /// A view modifier that delays the appearance of content with a delay.
    struct OnboardingViewWithDelay: ViewModifier {

        @State private var showContent = false

        let delay: TimeInterval

        func body(content: Content) -> some View {
            content
                .visibility(showContent ? .visible : .invisible)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation {
                            showContent = true
                        }
                    }
                }
        }
    }

}

extension View {

    /// Delays the visibility of a view with a fade-in animation.
    ///
    /// - Parameter delay: The time interval to wait before showing the content.
    ///                    Should match the parent container's animation duration.
    /// - Returns: A view that fades in after the specified delay.
    func onboardingViewVisibleAfterDelay(_ delay: TimeInterval) -> some View {
        modifier(OnboardingRebranding.OnboardingViewWithDelay(delay: delay))
    }

}
