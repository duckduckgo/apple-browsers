//
//  OnboardingTheme-macOS.swift
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

#if os(macOS)
import SwiftUI
import DesignResourcesKit

public extension OnboardingTheme {

    // Temporary values. To Replace when working on macOS project.
    static let macOSRebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5

        let typography = Typography.system

        let colorPalette = ColorPalette(
            background: Color(designSystemColor: .surfaceBackdrop),
            bubbleBorder: Color(designSystemColor: .accentAltPrimary),
            bubbleBackground: Color(designSystemColor: .surfaceTertiary),
            bubbleShadow: Color.shade(0.03),
            textPrimary: Color(designSystemColor: .textPrimary),
            textSecondary: Color(designSystemColor: .textSecondary),
            optionsListBorderColor: Color(designSystemColor: .accentPrimary),
            optionsListIconColor: Color(designSystemColor: .accentPrimary),
            optionsListTextColor: Color(designSystemColor: .textLink),
            primaryButtonBackgroundColor: Color(designSystemColor: .buttonsPrimaryDefault),
            primaryButtonTextColor: Color(designSystemColor: .buttonsPrimaryText)
        )

        let dismissButtonMetrics = DismissButtonMetrics(
            buttonSize: CGSize(width: 44, height: 44),
            offsetRelativeToBubble: CGPoint(x: 4, y: 4),
            contentPadding: 8.0
        )

        let contextualOptionsListMetrics = ContextualOnboardingMetrics.OptionsListMetrics(
            cornerRadius: 32,
            borderWidth: 1,
            borderInset: 0.5,
            iconSize: CGSize(width: 16, height: 16),
            itemMaxHeight: 40,
        )

        return OnboardingTheme(
            typography: .system,
            colorPalette: colorPalette,
            bubbleMetrics: BubbleMetrics(
                contentInsets: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
                cornerRadius: bubbleCornerRadius,
                borderWidth: borderWidth,
                shadowRadius: 6.0,
                shadowPosition: CGPoint(x: 0, y: 7)
            ),
            linearBubbleMetrics: LinearBubbleMetrics(
                contentInsets: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                arrowLength: 50,
                arrowWidth: 36
            ),
            dismissButtonMetrics: dismissButtonMetrics,
            contextualOnboardingMetrics: OnboardingTheme.ContextualOnboardingMetrics(
                contentSpacing: 20,
                titleBodyVerticalSpacing: 10,
                titleBodyInset: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
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
            linearOnboardingMetrics: LinearOnboardingMetrics(
                contentOuterSpacing: 16.0,
                contentInnerSpacing: 20,
                buttonSpacing: 12,
                bubbleMaxWidth: 340,
                bubbleTailOffset: 0.2,
                topMarginRatio: 0.18,
                minTopMargin: 32,
                maxTopMargin: 32,
                progressBarTrailingPadding: 16.0,
                progressBarTopPadding: 12.0,
                rebrandingBadgeLeadingPadding: 12.0,
                rebrandingBadgeTopPadding: 12.0
            ),
            linearTitleTextAlignment: .center,
            linearBodyTextAlignment: .center,
            primaryButtonStyle: OnboardingButtonStyle(
                id: .primary,
                style: AnyButtonStyle(OnboardingPrimaryButtonStyle())
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
