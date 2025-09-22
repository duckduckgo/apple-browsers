//
//  SemanticColor.swift
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

public enum DesignSystemColor {

    // Backgrounds
    case background
    case backgroundTertiary
    case surface
    case surfaceTertiary
    case backgroundSheets
    case panel
    case urlBar

    // Various
    case variousOutline
    case backdrop
    case backgroundBlur

    // Shadows
    case shadowPrimary
    case shadowSecondary
    case shadowTertiary
    case highlightDecoration

    // Text
    case textPrimary
    case textSecondary
    case textLink
    case textSelectionFill
    case textPlaceholder
    case textTertiary

    // Controls
    case controlsFillPrimary
    case controlsFillSecondary
    case controlsFillTertiary
    case controlsDecorationPrimary
    case controlsDecorationSecondary
    case controlsDecorationTertiary

    // Brand / Accent
    case accent
    case accentGlowSecondary
    case accentContentPrimary
    case accentContentSecondary
    case accentContentTertiary
    case accentGlowPrimary
    case accentPrimary
    case accentSecondary
    case accentTertiary
    case accentTextPrimary
    case accentTextSecondary
    case accentTextTertiary

    // Accent Alt
    case accentAltContentPrimary
    case accentAltContentSecondary
    case accentAltContentTertiary
    case accentAltGlowPrimary
    case accentAltPrimary
    case accentAltSecondary
    case accentAltTertiary
    case accentAltTextPrimary
    case accentAltTextSecondary
    case accentAltTextTertiary

    // System
    case lines
    case border

    // Alert
    case alertGreen
    case alertYellow

    // Icons
    case icons
    case iconsPrimary
    case iconsSecondary
    case iconsTertiary

    // Buttons/Primary
    case buttonsPrimaryDefault
    case buttonsPrimaryPressed
    case buttonsPrimaryDisabled
    case buttonsPrimaryText
    case buttonsPrimaryTextDisabled

    // Buttons/SecondaryFill
    case buttonsSecondaryFillDefault
    case buttonsSecondaryFillPressed
    case buttonsSecondaryFillDisabled
    case buttonsSecondaryFillText
    case buttonsSecondaryFillTextDisabled

    // Buttons/SecondaryWire
    case buttonsSecondaryWireDefault
    case buttonsSecondaryWirePressedFill
    case buttonsSecondaryWireDisabledStroke
    case buttonsSecondaryWireText
    case buttonsSecondaryWireTextPressed
    case buttonsSecondaryWireTextDisabled

    // Buttons/Ghost
    case buttonsGhostPressedFill
    case buttonsGhostText
    case buttonsGhostTextPressed
    case buttonsGhostTextDisabled

    // Buttons/Color
    case buttonsBlack
    case buttonsWhite

    // Buttons/DeleteGhost
    case buttonsDeleteGhostPressedFill
    case buttonsDeleteGhostText
    case buttonsDeleteGhostTextPressed
    case buttonsDeleteGhostTextDisabled

    // Decorations
    case decorationPrimary
    case decorationSecondary
    case decorationTertiary

    // Destructive
    case destructiveContentPrimary
    case destructiveContentSecondary
    case destructiveContentTertiary
    case destructiveGlow
    case destructivePrimary
    case destructiveSecondary
    case destructiveTertiary
    case destructiveTextPrimary
    case destructiveTextSecondary
    case destructiveTextTertiary

    // Highlight
    case highlightPrimary

    // Surfaces
    case surfaceBackdrop
    case surfaceCanvas
    case surfacePrimary
    case surfaceSecondary

    // Tone
    case toneShadePrimary
    case toneTintPrimary
}
