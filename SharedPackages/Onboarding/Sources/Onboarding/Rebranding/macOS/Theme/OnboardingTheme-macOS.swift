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

        let typography = Typography(
            contextualTitle: .system(size: 20, weight: .bold),
            contextualBody: .system(size: 16, weight: .regular),
            contextualControlSmall: .system(size: 13, weight: .regular)
        )

        let accentPrimary = Color(0x2F95EE)

        // Primary CTA button — adaptive palette.
        // Light: existing orange scheme (default → pressed, hover falls back to pressed).
        // Dark: cream/yellow scheme per Figma (#FFD986 default, #FFC95D hover, #FFC95D pressed).
        let ctaButtonBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0xFF/255.0, green: 0xD9/255.0, blue: 0x86/255.0, alpha: 1)
                : NSColor(red: 0xF0/255.0, green: 0x5F/255.0, blue: 0x2B/255.0, alpha: 1)
        }))
        let ctaButtonHover = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0xFF/255.0, green: 0xC9/255.0, blue: 0x5D/255.0, alpha: 1)
                : NSColor(red: 0xCC/255.0, green: 0x3B/255.0, blue: 0x0A/255.0, alpha: 1)
        }))
        let ctaButtonPressed = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0xFF/255.0, green: 0xC9/255.0, blue: 0x5D/255.0, alpha: 1)
                : NSColor(red: 0xCC/255.0, green: 0x3B/255.0, blue: 0x0A/255.0, alpha: 1)
        }))
        // Disabled: 40% opacity of default (no explicit Figma value yet).
        let ctaButtonDisabled = ctaButtonBackground.opacity(0.4)
        // Text on CTA — white on orange (light), dark navy on yellow (dark).
        let ctaButtonText = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0x01/255.0, green: 0x1D/255.0, blue: 0x34/255.0, alpha: 1)
                : .white
        }))

        // Panel/banner background behind the bubble (where the illustration sits).
        // Light: white. Dark: rebranding dark navy (#133E7C).
        let adaptiveBanner = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0x13/255.0, green: 0x3E/255.0, blue: 0x7C/255.0, alpha: 1)
                : .white
        }))
        // Bubble fill. Light: white. Dark: deeper navy (#011D34).
        let adaptiveBubbleBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0x01/255.0, green: 0x1D/255.0, blue: 0x34/255.0, alpha: 1)
                : .white
        }))
        // Bubble border. Light: pale blue. Dark: pure black (per Figma).
        let adaptiveBubbleBorder = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .black
                : NSColor(red: 0xCB/255.0, green: 0xEA/255.0, blue: 0xFF/255.0, alpha: 1)
        }))

        let colorPalette = ColorPalette(
            background: adaptiveBanner,
            bubbleBorder: adaptiveBubbleBorder,
            bubbleBackground: adaptiveBubbleBackground,
            bubbleShadow: Color.shade(0.03),
            textPrimary: Color(designSystemColor: .textPrimary),
            textSecondary: Color(designSystemColor: .textSecondary),
            optionsListBorderColor: accentPrimary,
            optionsListIconColor: accentPrimary,
            optionsListTextColor: accentPrimary,
            optionsListHoverColor: Color(red: 0x72/255.0, green: 0x95/255.0, blue: 0xF6/255.0).opacity(0.2),
            optionsListPressedColor: Color(red: 0x72/255.0, green: 0x95/255.0, blue: 0xF6/255.0).opacity(0.2),
            primaryButtonBackgroundColor: ctaButtonBackground,
            primaryButtonPressedColor: ctaButtonPressed,
            primaryButtonTextColor: ctaButtonText,
            secondaryButtonBackgroundColor: Color(designSystemColor: .buttonsPrimaryDefault),
            secondaryButtonPressedColor: Color(designSystemColor: .buttonsPrimaryPressed),
            secondaryButtonTextColor: Color(designSystemColor: .buttonsPrimaryText),
            backgroundAccent: accentPrimary
        )

        let dismissButtonMetrics = DismissButtonMetrics(
            buttonSize: CGSize(width: 44, height: 44),
            offsetRelativeToBubble: CGPoint(x: 4, y: 4),
            contentPadding: 8.0
        )

        let contextualOptionsListMetrics = ContextualOnboardingMetrics.OptionsListMetrics(
            cornerRadius: 999,
            borderWidth: 1,
            borderInset: 0.5,
            iconSize: CGSize(width: 16, height: 16),
            itemMinHeight: 32,
            verticalPadding: 6,
            horizontalPadding: 12
        )

        return OnboardingTheme(
            typography: typography,
            colorPalette: colorPalette,
            bubbleMetrics: BubbleMetrics(
                contentInsets: EdgeInsets(top: 24, leading: 32, bottom: 24, trailing: 32),
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
                containerPadding: EdgeInsets(top: 16, leading: 16, bottom: 58, trailing: 16),
                contentSpacing: 12,
                titleBodyVerticalSpacingVerticalLayout: 8,
                titleBodyVerticalSpacingHorizontalLayout: 8,
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
                style: AnyButtonStyle(
                    OnboardingRebranding.OnboardingStyles.CTAButtonStyle(
                        backgroundColor: ctaButtonBackground,
                        hoverBackgroundColor: ctaButtonHover,
                        pressedBackgroundColor: ctaButtonPressed,
                        disabledBackgroundColor: ctaButtonDisabled,
                        foregroundColor: ctaButtonText,
                        font: typography.contextual.body
                    )
                )
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
