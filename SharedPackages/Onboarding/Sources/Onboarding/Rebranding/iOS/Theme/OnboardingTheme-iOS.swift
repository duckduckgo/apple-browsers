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
import UIKit
import DesignResourcesKit
import MetricBuilder

// MARK: - Factory Helpers

@MainActor
public extension OnboardingTheme {

    /// Rebranding 2026 default onboarding theme.
    static let iOSRebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5
        let bubbleBorderColor = OnboardingRebrandColor.bubbleBorder

        let typography: OnboardingTheme.Typography = .duckSans
        let colorPalette = ColorPalette(
            background: Color(singleUseColor: .rebranding(.backdrop)),
            bubbleBorder: bubbleBorderColor,
            bubbleBackground: OnboardingRebrandColor.surfaceTertiary,
            bubbleShadow: Color.shade(0.03),
            textPrimary: Color(singleUseColor: .rebranding(.textPrimary)),
            textSecondary: Color(singleUseColor: .rebranding(.textSecondary)),
            optionsListBorderColor: Color(singleUseColor: .rebranding(.accentPrimary)),
            optionsListIconColor: Color(singleUseColor: .rebranding(.accentPrimary)),
            optionsListTextColor: Color(singleUseColor: .rebranding(.textLink)),
            optionsListHoverColor: Color(singleUseColor: .rebranding(.accentPrimary)).opacity(0.1),
            optionsListPressedColor: Color(singleUseColor: .rebranding(.accentPrimary)).opacity(0.2),
            primaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.buttonsPrimaryDefault)),
            primaryButtonPressedColor: Color(singleUseColor: .rebranding(.buttonsPrimaryPressed)),
            primaryButtonTextColor: Color(singleUseColor: .rebranding(.buttonsPrimaryText)),
            secondaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.buttonsSecondaryDefault)),
            secondaryButtonPressedColor: Color(singleUseColor: .rebranding(.buttonsSecondaryPressed)),
            secondaryButtonTextColor: Color(singleUseColor: .rebranding(.buttonsSecondaryText)),
            backgroundAccent: OnboardingRebrandColor.backgroundAccent
        )
        let bubbleMetrics = BubbleMetrics(
            contentInsets: bubbleContentInsets,
            cornerRadius: bubbleCornerRadius,
            borderWidth: borderWidth,
            shadowRadius: 6.0,
            shadowPosition: CGPoint(x: 0, y: 7)
        )
        let linearBubbleMetrics = LinearBubbleMetrics(
            contentInsets: linearBubbleContentInsets,
            arrowLength: 40,
            arrowWidth: 29
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
            itemMinHeight: 44
        )

        let linearOnboardingMetrics = LinearOnboardingMetrics(
            contentOuterSpacing: 16.0,
            contentInnerSpacing: 20,
            buttonSpacing: 12,
            bubbleMaxWidth: 360,
            topMarginRatio: 0.18,
            minTopMargin: 16,
            maxTopMargin: 16,
            progressBarTrailingPadding: 16.0,
            progressBarTopPadding: 12.0,
            rebrandingBadgeLeadingPadding: 12.0,
            rebrandingBadgeTopPadding: 12.0,
            dialogVerticalOffsetPercentage: MetricBuilder<CGFloat>(default: 0.1).iPhoneSmallScreen(0.01),
            actionsSpacing: 12
        )

        return OnboardingTheme(
            typography: typography,
            colorPalette: colorPalette,
            bubbleMetrics: bubbleMetrics,
            linearBubbleMetrics: linearBubbleMetrics,
            dismissButtonMetrics: dismissButtonMetrics,
            contextualOnboardingMetrics: ContextualOnboardingMetrics(
                containerPadding: containerPadding,
                contentSpacing: 20,
                titleBodyVerticalSpacingVerticalLayout: 14,
                titleBodyVerticalSpacingHorizontalLayout: 10,
                titleBodyInset: contextualTitleBodyContentInsets,
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
                ),
                maxContainerWidth: 590
            ),
            linearOnboardingMetrics: linearOnboardingMetrics,
            linearTitleTextAlignment: .center,
            linearBodyTextAlignment: .center,
            primaryButtonStyle: OnboardingButtonStyle(
                id: .primary,
                style: AnyButtonStyle(OnboardingPrimaryButtonStyle(
                    typography: typography,
                    colorPalette: colorPalette
                ))
            ),
            secondaryButtonStyle: OnboardingButtonStyle(
                id: .secondary,
                style: AnyButtonStyle(OnboardingSecondaryButtonStyle(
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
                        borderColor: OnboardingRebrandColor.accentAltPrimary, // Dark mode bubble does not have a border color, hence reference the color directly.
                        borderWidth: borderWidth,
                        buttonSize: dismissButtonMetrics.buttonSize
                    )
                )
            )
        )
    }()

    private static let linearBubbleContentInsets: EdgeInsets = MetricBuilder<EdgeInsets>(
        iPhone: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
        iPad: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20)
    ).build()

    /// Insets for the onboarding bubble content, per device class.
    private static let bubbleContentInsets: EdgeInsets = MetricBuilder<EdgeInsets>(
        iPhone: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
        iPad: EdgeInsets(top: 24, leading: 40, bottom: 24, trailing: 40)
    ).build()

    /// Insets for the contextual title/body copy block, per device class.
    private static let contextualTitleBodyContentInsets: EdgeInsets = MetricBuilder<EdgeInsets>(
        iPhone: EdgeInsets(top: 0, leading: 8, bottom: 12, trailing: 8),
        iPad: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    ).build()

    /// Outer padding for contextual onboarding content, per device class.
    private static let containerPadding: EdgeInsets = MetricBuilder<EdgeInsets>(
        iPhone: EdgeInsets(top: 16, leading: 16, bottom: 58, trailing: 16),
        iPad: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    ).build()
}

#endif
