//
//  SharedColorPaletteDefinition.swift
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

protocol SharedColorPaletteDefinition {

    // MARK: - Accent Colors
    static var accentContentPrimary: DynamicColor { get }
    static var accentContentSecondary: DynamicColor { get }
    static var accentContentTertiary: DynamicColor { get }
    static var accentGlowPrimary: DynamicColor { get }
    static var accentGlowSecondary: DynamicColor { get }
    static var accentPrimary: DynamicColor { get }
    static var accentQuaternary: DynamicColor { get }
    static var accentSecondary: DynamicColor { get }
    static var accentTertiary: DynamicColor { get }
    static var accentTextPrimary: DynamicColor { get }
    static var accentTextSecondary: DynamicColor { get }
    static var accentTextTertiary: DynamicColor { get }

    // MARK: - Accent Alt Colors
    static var accentAltContentPrimary: DynamicColor { get }
    static var accentAltContentSecondary: DynamicColor { get }
    static var accentAltContentTertiary: DynamicColor { get }
    static var accentAltGlowPrimary: DynamicColor { get }
    static var accentAltGlowSecondary: DynamicColor { get }
    static var accentAltPrimary: DynamicColor { get }
    static var accentAltSecondary: DynamicColor { get }
    static var accentAltTertiary: DynamicColor { get }
    static var accentAltTextPrimary: DynamicColor { get }
    static var accentAltTextSecondary: DynamicColor { get }
    static var accentAltTextTertiary: DynamicColor { get }

    // MARK: - Alert
    static var alertGreen: DynamicColor { get }
    static var alertYellow: DynamicColor { get }

    // MARK: - Buttons/Primary
    static var buttonsPrimaryDefault: DynamicColor { get }
    static var buttonsPrimaryPressed: DynamicColor { get }
    static var buttonsPrimaryDisabled: DynamicColor { get }
    static var buttonsPrimaryText: DynamicColor { get }
    static var buttonsPrimaryTextDisabled: DynamicColor { get }

    // MARK: - Buttons/SecondaryFill
    static var buttonsSecondaryFillDefault: DynamicColor { get }
    static var buttonsSecondaryFillPressed: DynamicColor { get }
    static var buttonsSecondaryFillDisabled: DynamicColor { get }
    static var buttonsSecondaryFillText: DynamicColor { get }
    static var buttonsSecondaryFillTextDisabled: DynamicColor { get }

    // MARK: - Buttons/Color
    static var buttonsWhite: DynamicColor { get }

    // MARK: - Container Colors
    static var containerFillPrimary: DynamicColor { get }
    static var containerFillSecondary: DynamicColor { get }
    static var containerFillTertiary: DynamicColor { get }
    static var containerBorderPrimary: DynamicColor { get }
    static var containerBorderSecondary: DynamicColor { get }
    static var containerBorderTertiary: DynamicColor { get }

    // MARK: - Controls Colors
    static var controlsBorderPrimary: DynamicColor { get }
    static var controlsBorderSecondary: DynamicColor { get }
    static var controlsBorderTertiary: DynamicColor { get }
    static var controlsBorderQuaternary: DynamicColor { get }
    static var controlsFillPrimary: DynamicColor { get }
    static var controlsFillSecondary: DynamicColor { get }
    static var controlsFillTertiary: DynamicColor { get }

    // MARK: - Destructive Colors
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

    // MARK: - Highlight Colors
    static var highlightPrimary: DynamicColor { get }

    // MARK: - Icons Colors
    static var iconsPrimary: DynamicColor { get }
    static var iconsSecondary: DynamicColor { get }
    static var iconsTertiary: DynamicColor { get }

    // MARK: - System
    static var lines: DynamicColor { get }

    // MARK: - Shadow Colors
    static var shadowPrimary: DynamicColor { get }
    static var shadowSecondary: DynamicColor { get }
    static var shadowTertiary: DynamicColor { get }

    // MARK: - Surface Colors
    static var surfaceBackdrop: DynamicColor { get }
    static var surfaceCanvas: DynamicColor { get }
    static var surfacePrimary: DynamicColor { get }
    static var surfaceSecondary: DynamicColor { get }
    static var surfaceTertiary: DynamicColor { get }

    // MARK: - Surface Decoration
    static var surfaceDecorationPrimary: DynamicColor { get }
    static var surfaceDecorationSecondary: DynamicColor { get }
    static var surfaceDecorationTertiary: DynamicColor { get }

    // MARK: - Text Colors
    static var textPrimary: DynamicColor { get }
    static var textSecondary: DynamicColor { get }
    static var textTertiary: DynamicColor { get }

    // MARK: - Tone Colors
    static var toneShadePrimary: DynamicColor { get }
}

#endif
