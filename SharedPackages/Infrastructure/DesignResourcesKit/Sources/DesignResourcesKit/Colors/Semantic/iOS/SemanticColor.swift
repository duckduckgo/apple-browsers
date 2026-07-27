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

public enum DesignSystemColor: CaseIterable {

    // Backgrounds
    case surfacePrimary

    case backgroundTertiary
    case backgroundSheets
    case backgroundPromptMessage

    // Surfaces
    case surfaceSecondary
    case surfaceTertiary
    case surfaceCanvas

    case urlBar

    // Various
    case surfaceBackdrop

    // Shadows
    case shadowPrimary
    case shadowSecondary
    case shadowTertiary
    case highlightPrimary

    // Text
    case textPrimary
    case textSecondary
    case textTertiary
    case accentTextPrimary
    case textSelectionFill
    case textPlaceholder

    // Controls
    case controlFillPrimary
    case controlFillSecondary
    case controlFillTertiary
    case controlRaisedBackdrop
    case controlRaisedFillPrimary

    // Brand
    case accentPrimary
    case accentGlowPrimary
    case accentGlowSecondary
    case accentContentPrimary
    case accentTertiary

    // Brand Alt
    case accentAltGlowPrimary
    case accentAltContentPrimary

    // Container
    case containerBorderPrimary

    // Accent Brand
    case accentBrandPrimary
    case accentBrandTertiary
    case accentBrandContentPrimary

    // System
    case lines
    case border

    // Alert
    case alertGreen
    case alertYellow

    // Shield
    case shieldPrivacy

    // VPN
    case vpnGreen
    case vpnGreenPressed
    case vpnGreenForeground
    case vpnGreenForegroundPressed
    case vpnYellow
    case vpnYellowPressed
    case vpnYellowForeground
    case vpnYellowForegroundPressed

    // Icons
    case iconsPrimary
    case iconsSecondary
    case iconsTertiary

    // Destructive
    case destructivePrimary
    case destructiveTertiary
    case destructiveContentPrimary
    case destructiveGlowPrimary

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
    case surfaceDecorationPrimary
    case surfaceDecorationSecondary
    case surfaceDecorationTertiary
    case surfaceDecorationQuaternary

}
#endif
