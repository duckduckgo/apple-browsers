//
//  SharedDesignSystemColor.swift
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

import Foundation

#if os(macOS)

public typealias DesignSystemColor = SharedDesignSystemColor

public enum SharedDesignSystemColor {

    // Accent
    case accentContentPrimary
    case accentContentSecondary
    case accentContentTertiary
    case accentGlowPrimary
    case accentGlowSecondary
    case accentPrimary
    case accentQuaternary
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
    case accentAltGlowSecondary
    case accentAltPrimary
    case accentAltSecondary
    case accentAltTertiary
    case accentAltTextPrimary
    case accentAltTextSecondary
    case accentAltTextTertiary

    // Alert
    case alertGreen
    case alertYellow

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

    // Buttons/Color
    case buttonsWhite

    // Container
    case containerFillPrimary
    case containerFillSecondary
    case containerFillTertiary
    case containerBorderPrimary
    case containerBorderSecondary
    case containerBorderTertiary

    // Controls
    case controlsBorderPrimary
    case controlsBorderSecondary
    case controlsBorderTertiary
    case controlsBorderQuaternary
    case controlsFillPrimary
    case controlsFillSecondary
    case controlsFillTertiary
    case controlsRaisedBackdrop
    case controlsRaisedFillPrimary

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

    // Icons
    case iconsPrimary
    case iconsSecondary
    case iconsTertiary

    // System
    case lines
    case spinnerStart
    case spinnerFinal

    // Shadows
    case shadowPrimary
    case shadowSecondary
    case shadowTertiary

    // Surface
    case surfaceBackdrop
    case surfaceCanvas
    case surfacePrimary
    case surfaceSecondary
    case surfaceTertiary

    // Surface Decoration
    case surfaceDecorationPrimary
    case surfaceDecorationSecondary
    case surfaceDecorationTertiary

    // Text
    case textPrimary
    case textSecondary
    case textTertiary

    // Tone
    case toneShadePrimary

    // Permission Center
    case permissionCenterBackground
    case permissionCenterContainerBackground
    case permissionWarningBackground
    case permissionReloadButtonBackground
    case permissionReloadButtonText
}

#endif
