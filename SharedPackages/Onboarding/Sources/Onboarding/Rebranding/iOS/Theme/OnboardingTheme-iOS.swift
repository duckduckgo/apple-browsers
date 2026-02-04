//
//  OnboardingTheme-iOS.swift
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

#if os(iOS)
import SwiftUI
import DesignResourcesKit

// MARK: - Factory Helpers

public extension OnboardingTheme {

    /// Rebranding 2026 default onboarding theme.
    static let iOSRebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5

        let typography: OnboardingTheme.Typography = .system
        let colorPalette = ColorPalette(
            bubbleBorder: Color(singleUseColor: .rebranding(.accentAltPrimary)),
            bubbleBackground: Color(singleUseColor: .rebranding(.surfaceTertiary)),
            bubbleShadow: Color.shade(0.03),
            textPrimary: Color(singleUseColor: .rebranding(.textPrimary)),
            textSecondary: Color(singleUseColor: .rebranding(.textSecondary)),
            optionsListBorderColor: Color(singleUseColor: .rebranding(.accentPrimary)),
            optionsListIconColor: Color(singleUseColor: .rebranding(.accentPrimary)),
            optionsListTextColor: Color(singleUseColor: .rebranding(.textLink)),
            primaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.buttonsPrimaryDefault)),
            primaryButtonTextColor: Color(singleUseColor: .rebranding(.buttonsPrimaryText))
        )
        let bubbleMetrics = BubbleMetrics(
            contentInsets: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
            cornerRadius: bubbleCornerRadius,
            borderWidth: borderWidth,
            shadowRadius: 6.0,
            shadowPosition: CGPoint(x: 0, y: 7)
        )
        let dismissButtonMetrics = DismissButtonMetrics(
            buttonSize: CGSize(width: 44, height: 44),
            offsetRelativeToBubble: CGPoint(x: 4, y: 4),
            contentPadding: 8
        )
        let contextualOptionsListMetrics = ContextualOnboardingMetrics.OptionsListMetrics(
            cornerRadius: 32,
            borderWidth: 1,
            borderInset: 0.5,
            iconSize: CGSize(width: 16, height: 16),
            itemMaxHeight: 40
        )

        return OnboardingTheme(
            typography: typography,
            colorPalette: colorPalette,
            bubbleMetrics: bubbleMetrics,
            dismissButtonMetrics: dismissButtonMetrics,
            contextualOnboardingMetrics: ContextualOnboardingMetrics(
                contextualTitleTextAlignment: .leading,
                contextualBodyTextAlignment: .leading,
                optionsListMetrics: contextualOptionsListMetrics,
                optionsListButtonStyle: OnboardingButtonStyle(
                    id: .list,
                    style: AnyButtonStyle(
                        OnboardingRebranding.OnboardingStyles.ListButtonStyle(
                            typography: typography,
                            colorPalette: colorPalette,
                            optionsListMetrics: contextualOptionsListMetrics
                        )
                    )
                )
            ),
            linearTitleTextAlignment: .center,
            linearBodyTextAlignment: .center,
            primaryButtonStyle: OnboardingButtonStyle(
                id: .primary,
                style: AnyButtonStyle(OnboardingPrimaryButtonStyle(
                    typography: typography,
                    colorPalette: colorPalette
                ))
            ),
            dismissButtonStyle: OnboardingButtonStyle(
                id: .dismiss,
                style: AnyButtonStyle(
                    OnboardingRebranding.OnboardingStyles.BubbleDismissButtonStyle(
                        contentPadding: dismissButtonMetrics.contentPadding,
                        backgroundColor: colorPalette.bubbleBackground,
                        borderColor: colorPalette.bubbleBorder,
                        borderWidth: borderWidth,
                        buttonSize: dismissButtonMetrics.buttonSize
                    )
                )
            )
        )
    }()

}
#endif
