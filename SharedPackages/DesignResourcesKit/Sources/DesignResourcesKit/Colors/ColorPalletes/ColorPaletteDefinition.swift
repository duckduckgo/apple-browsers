//
//  ColorPaletteDefinition.swift
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

/// Color palette definition that logically collects all colors that work properly with each other.
protocol ColorPaletteDefinition {

    /// Gets dynamic color proxy for a specific semantic color.
    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor

    /// Gets dynamic color proxy for a single use semantic color.
    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor

    /// Returns a base color.
    static func color(for baseColor: BaseColor) -> Color

    // MARK: - Dynamic Color Properties

    // URL Bar
    static var urlBar: DynamicColor { get }

    // Surfaces
    static var surface: DynamicColor { get }
    static var surfaceTertiary: DynamicColor { get }
    static var surfaceBackdrop: DynamicColor { get }
    static var surfaceCanvas: DynamicColor { get }
    static var surfacePrimary: DynamicColor { get }
    static var surfaceSecondary: DynamicColor { get }

    // Backgrounds
    static var backdrop: DynamicColor { get }
    static var background: DynamicColor { get }
    static var backgroundTertiary: DynamicColor { get }
    static var backgroundSheets: DynamicColor { get }
    static var backgroundBlur: DynamicColor { get }

    // Shadow
    static var shadowPrimary: DynamicColor { get }
    static var shadowSecondary: DynamicColor { get }
    static var shadowTertiary: DynamicColor { get }

    // Controls
    static var controlsFillPrimary: DynamicColor { get }
    static var controlsFillSecondary: DynamicColor { get }
    static var controlsFillTertiary: DynamicColor { get }
    static var controlsDecorationPrimary: DynamicColor { get }
    static var controlsDecorationSecondary: DynamicColor { get }
    static var controlsDecorationTertiary: DynamicColor { get }

    // Icons
    static var icons: DynamicColor { get }
    static var iconsPrimary: DynamicColor { get }
    static var iconsSecondary: DynamicColor { get }
    static var iconsTertiary: DynamicColor { get }

    // Text
    static var textPrimary: DynamicColor { get }
    static var textSecondary: DynamicColor { get }
    static var textTertiary: DynamicColor { get }
    static var textPlaceholder: DynamicColor { get }
    static var textLink: DynamicColor { get }
    static var textSelectionFill: DynamicColor { get }

    // System
    static var lines: DynamicColor { get }
    static var border: DynamicColor { get }

    // Decorations
    static var decorationPrimary: DynamicColor { get }
    static var decorationSecondary: DynamicColor { get }
    static var decorationTertiary: DynamicColor { get }

    // Highlight
    static var highlightDecoration: DynamicColor { get }
    static var highlightPrimary: DynamicColor { get }

    // Brand/Accent
    static var accent: DynamicColor { get }
    static var accentGlowPrimary: DynamicColor { get }
    static var accentGlowSecondary: DynamicColor { get }
    static var accentPrimary: DynamicColor { get }
    static var accentSecondary: DynamicColor { get }
    static var accentTertiary: DynamicColor { get }
    static var accentTextPrimary: DynamicColor { get }
    static var accentTextSecondary: DynamicColor { get }
    static var accentTextTertiary: DynamicColor { get }
    static var accentContentPrimary: DynamicColor { get }
    static var accentContentSecondary: DynamicColor { get }
    static var accentContentTertiary: DynamicColor { get }

    // Accent Alt
    static var accentAltContentPrimary: DynamicColor { get }
    static var accentAltContentSecondary: DynamicColor { get }
    static var accentAltContentTertiary: DynamicColor { get }
    static var accentAltGlowPrimary: DynamicColor { get }
    static var accentAltPrimary: DynamicColor { get }
    static var accentAltSecondary: DynamicColor { get }
    static var accentAltTertiary: DynamicColor { get }
    static var accentAltTextPrimary: DynamicColor { get }
    static var accentAltTextSecondary: DynamicColor { get }
    static var accentAltTextTertiary: DynamicColor { get }

    // Alert
    static var alertGreen: DynamicColor { get }
    static var alertYellow: DynamicColor { get }

    // Buttons/Primary
    static var buttonsPrimaryDefault: DynamicColor { get }
    static var buttonsPrimaryPressed: DynamicColor { get }
    static var buttonsPrimaryDisabled: DynamicColor { get }
    static var buttonsPrimaryText: DynamicColor { get }
    static var buttonsPrimaryTextDisabled: DynamicColor { get }

    // Buttons/SecondaryFill
    static var buttonsSecondaryFillDefault: DynamicColor { get }
    static var buttonsSecondaryFillPressed: DynamicColor { get }
    static var buttonsSecondaryFillDisabled: DynamicColor { get }
    static var buttonsSecondaryFillText: DynamicColor { get }
    static var buttonsSecondaryFillTextDisabled: DynamicColor { get }

    // Buttons/SecondaryWire
    static var buttonsSecondaryWireDefault: DynamicColor { get }
    static var buttonsSecondaryWirePressedFill: DynamicColor { get }
    static var buttonsSecondaryWireDisabledStroke: DynamicColor { get }
    static var buttonsSecondaryWireText: DynamicColor { get }
    static var buttonsSecondaryWireTextPressed: DynamicColor { get }
    static var buttonsSecondaryWireTextDisabled: DynamicColor { get }

    // Buttons/Ghost
    static var buttonsGhostPressedFill: DynamicColor { get }
    static var buttonsGhostText: DynamicColor { get }
    static var buttonsGhostTextPressed: DynamicColor { get }
    static var buttonsGhostTextDisabled: DynamicColor { get }

    // Buttons/Color
    static var buttonsBlack: DynamicColor { get }
    static var buttonsWhite: DynamicColor { get }

    // Buttons/DeleteGhost
    static var buttonsDeleteGhostPressedFill: DynamicColor { get }
    static var buttonsDeleteGhostText: DynamicColor { get }
    static var buttonsDeleteGhostTextPressed: DynamicColor { get }
    static var buttonsDeleteGhostTextDisabled: DynamicColor { get }

    // Destructive
    static var destructiveContentPrimary: DynamicColor { get }
    static var destructiveContentSecondary: DynamicColor { get }
    static var destructiveContentTertiary: DynamicColor { get }
    static var destructiveGlow: DynamicColor { get }
    static var destructivePrimary: DynamicColor { get }
    static var destructiveSecondary: DynamicColor { get }
    static var destructiveTertiary: DynamicColor { get }
    static var destructiveTextPrimary: DynamicColor { get }
    static var destructiveTextSecondary: DynamicColor { get }
    static var destructiveTextTertiary: DynamicColor { get }

    // Tone
    static var toneShadePrimary: DynamicColor { get }
    static var toneTintPrimary: DynamicColor { get }

    // Various
    static var variousIPadTabs: DynamicColor { get }
    static var variousOutline: DynamicColor { get }
}
