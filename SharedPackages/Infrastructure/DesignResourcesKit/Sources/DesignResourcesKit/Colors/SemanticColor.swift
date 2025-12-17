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

#if os(iOS)

public enum DesignSystemColor {

    // Backgrounds
    case background

    case backgroundTertiary
    case backgroundSheets
    case panel

    // Surfaces
    case surface // T-surface/secondary
    case surfaceTertiary
    case surfaceCanvas

    case urlBar

    // Various
    case backdrop

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

    // Controls
    case controlsFillPrimary
    case controlsFillSecondary
    case controlsFillTertiary

    // Brand
    case accent
    case accentGlowSecondary
    case accentContentPrimary
    case accentTertiary

    // System
    case lines
    case border

    // Alert
    case alertGreen
    case alertYellow

    // Icons
    case icons
    case iconsSecondary
    case iconsTertiary

    // Destructive
    case destructivePrimary

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
    case buttonsWhite

    // Buttons/DeleteGhost
    case buttonsDeleteGhostPressedFill
    case buttonsDeleteGhostText
    case buttonsDeleteGhostTextPressed
    case buttonsDeleteGhostTextDisabled

    // Buttons/DestructivePrimary
    case buttonsDestructivePrimaryPressed

    // Decorations
    case decorationPrimary
    case decorationSecondary
    case decorationTertiary

}
#endif
