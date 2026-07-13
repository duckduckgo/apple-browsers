//
//  SingleUseColor.swift
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

/// Semantic colors used for single use case.
///
/// - Important: When used in multiple places, it should be proposed to promote the color to `DesignSystemColor`.
public enum SingleUseColor {

    // Fire View
    case fireModeAccent

#if os(iOS)
    case controlWidgetBackground
    case unifiedFeedbackFieldBackground
    case privacyDashboardBackground

    /// Color used for separator line between text input and content
    case inputContentSeparator

    /// Resting background fill for the floating address bar field (composites over the toolbar's Liquid Glass capsule)
    case floatingAddressBarBackground

    /// Color used for what's New background
    case whatsNewBackground

    /// Duck.ai contextual background color
    case duckAIContextualSheetBackground

    /// Duck.ai web view background color (#FFFFFF light / #111111 dark)
    case duckAIWebViewBackground

    /// Card background for the unified toggle input bar (white in light, #3D3D3D in dark)
    case unifiedToggleInputCardBackground
    case unifiedToggleInputAttachmentErrorBannerBackground
    case unifiedToggleInputAttachmentErrorText
    case unifiedToggleInputAttachmentErrorIcon

    /// Stop-generating button background in the unified toggle input bar: translucent overlay on the card (6% black in light, 12% white in dark).
    case unifiedToggleInputStopButtonBackground

    /// Tab switcher tracker count info panel background color
    case tabSwitcherTrackerCountBackground

    /// Color used for 2026 Rebranding. Currently used only in Onboarding, hence they're isolated to avoid bleeding in other parts of the App.
    /// DefaultColorPalette should be updated with new colors when the time comes.
    case rebranding(Rebranding)

    /// On iOS 26 toolbar buttons get some effect applied to them which affects the lightness of the color.  This is temporary
    /// until we move to a more Liquid Glass based look and feel there.
    case toolbarButton

    // Fire Mode
    case fireModeAccentDark
    case fireModeAccentTertiary
    case fireModeBackground
    case fireModeCardBackground

    // Duck.ai Grid Cell
    case duckAIVoiceCellBackground

#elseif os(macOS)

    case fireButtonGradientStart
    case fireButtonGradientEnd
    case fireButtonPressedGradientStart
    case fireButtonPressedGradientEnd

#endif

}

#if os(iOS)

// MARK: - Onboarding Rebranding 2026

public extension SingleUseColor {

    enum Rebranding {
        case textPrimary
        case textSecondary
        case textLink

        case accentPrimary
        case accentPrimaryPressed
        case accentPrimaryText
        case accentGlowPrimary

        case backdrop

        case buttonsPrimaryDefault
        case buttonsPrimaryPressed
        case buttonsPrimaryText
        case buttonsContentDisabled

        case buttonsSecondaryDefault
        case buttonsSecondaryPressed
        case buttonsSecondaryText
        case buttonsSecondaryDisabledBackground
        case buttonsSecondaryDisabledText

        case destructivePrimary
        case destructivePrimaryPressed
        case destructivePrimaryText
        case destructiveGlowPrimary

        case controlsFillPrimary
        case controlBorderTertiary

        case decorationPrimary
        case decorationSecondary

        case alertGreen
        case calendarStripYellow
    }

}

#endif
