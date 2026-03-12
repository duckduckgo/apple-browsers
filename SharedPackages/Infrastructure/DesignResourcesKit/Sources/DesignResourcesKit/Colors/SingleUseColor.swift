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
    case controlWidgetBackground
    case unifiedFeedbackFieldBackground
    case privacyDashboardBackground

    /// Color used for separator line between text input and content
    case inputContentSeparator

    /// Color used for what's New background
    case whatsNewBackground

    /// Duck.ai contextual background color
    case duckAIContextualSheetBackground

    /// Card background for the unified toggle input bar (white in light, #3D3D3D in dark)
    case unifiedToggleInputCardBackground

    /// Tab switcher tracker count info panel background color
    case tabSwitcherTrackerCountBackground

    /// Color used for 2026 Rebranding. Currently used only in Onboarding, hence they're isolated to avoid bleeding in other parts of the App.
    /// DefaultColorPalette should be updated with new colors when the time comes.
    case rebranding(Rebranding)

    /// On iOS 26 toolbar buttons get some effect applied to them which affects the lightness of the color.  This is temporary
    /// until we move to a more Liquid Glass based look and feel there.
    case toolbarButton

    // Fire Mode
    case fireModeAccent
    case fireModeAccentTertiary
    case fireModeBackground
}

// MARK: - Onboarding Rebranding 2026

public extension SingleUseColor {

    enum Rebranding {
        case textPrimary
        case textSecondary
        case textLink

        case accentPrimary

        case accentAltPrimary
        case accentAltGlowPrimary

        case backdrop

        case surfaceTertiary

        case buttonsPrimaryDefault
        case buttonsPrimaryPressed
        case buttonsPrimaryText

        case buttonsSecondaryDefault
        case buttonsSecondaryPressed
        case buttonsSecondaryText
        case backgroundAccent // This in Figma is accentAltGlowPrimary but in the components screen default value is different than onboarding value

        case controlsFillPrimary

        case decorationPrimary
        case decorationSecondary
    }

}
