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

    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case backgroundTertiary
    case surface
    case surfaceTertiary
    case backgroundSheets
    case panel

    @available(*, deprecated, message: "Use controlsFillPrimary or consult designers")
    case container

    case urlBar

    // Various
    @available(*, deprecated, message: "Use backdrop or consult designers")
    case variousIPadTabs

    case variousOutline
    case backdrop
    case backgroundBlur

    // Shadows
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case shadowPrimary
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case shadowSecondary
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case shadowTertiary
    case highlightDecoration

    // Text
    case textPrimary
    case textSecondary
    case textLink
    case textSelectionFill
    case textPlaceholder

    // Controls
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case controlsFillPrimary
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case controlsFillSecondary
    /// - warning: This color should be used in experimental palette only until it's fully adopted.
    /// Using it with default palette fires assertion.
    case controlsFillTertiary

    // Brand
    case accent
    case accentContentPrimary

    // System
    case lines
    case border

    // Alert
    case alertGreen
    case alertYellow

    // Icons
    case icons
    case iconsSecondary

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

}
