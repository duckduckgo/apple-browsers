//
//  OnboardingViewModifiers.swift
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

// MARK: - Dismiss Button

private struct OnboardingDismissButtonViewModifier: ViewModifier {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            content
                .overlay(alignment: .topTrailing) {
                    dismissButton
                }
        } else {
            ZStack(alignment: .topTrailing) {
                content
                dismissButton
            }
        }
    }

    private var dismissButton: some View {
        OnboardingBubbleDismissButton(action: onDismiss)
            .alignmentGuide(VerticalAlignment.top) { _ in onboardingTheme.dismissButtonMetrics.contentPadding + onboardingTheme.dismissButtonMetrics.offsetRelativeToBubble.y }
            .alignmentGuide(HorizontalAlignment.trailing) { $0.width - onboardingTheme.dismissButtonMetrics.contentPadding - onboardingTheme.dismissButtonMetrics.offsetRelativeToBubble.x }
    }
}

public extension View {

    /// Adds a dismiss button to the top-trailing corner of the view to dismiss the onboarding dialog.
    ///
    /// - Parameter onDismiss: A closure that's called when the dismiss button is tapped.
    /// - Returns: A view with a dismiss button overlay.
    func onboardingDismissable(_ onDismiss: @escaping () -> Void) -> some View {
        self.modifier(OnboardingDismissButtonViewModifier(onDismiss: onDismiss))
    }

}

// MARK: - Shadow

private struct OnboardingShadowViewModifier: ViewModifier {
    @Environment(\.onboardingTheme) private var onboardingTheme

    func body(content: Content) -> some View {
        let shadowPosition = onboardingTheme.bubbleMetrics.shadowPosition

        content.shadow(
            color: onboardingTheme.colorPalette.bubbleShadow,
            radius: onboardingTheme.bubbleMetrics.shadowRadius,
            x: shadowPosition.x, y: shadowPosition.y
        )
    }
}

public extension View {

    /// Applies the onboarding shadow style defined by the active theme.
    ///
    /// - Returns: A view with onboarding shadow parameters applied.
    func applyOnboardingShadow() -> some View {
        self.modifier(OnboardingShadowViewModifier())
    }

}
