//
//  ThemeColors.swift
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

public protocol ThemeColors {
    var accentAltContentPrimary: PlatformColor { get }
    var accentAltContentSecondary: PlatformColor { get }
    var accentAltContentTertiary: PlatformColor { get }
    var accentAltGlowPrimary: PlatformColor { get }
    var accentAltPrimary: PlatformColor { get }
    var accentAltSecondary: PlatformColor { get }
    var accentAltTertiary: PlatformColor { get }
    var accentAltTextPrimary: PlatformColor { get }
    var accentAltTextSecondary: PlatformColor { get }
    var accentAltTextTertiary: PlatformColor { get }

    var accentContentPrimary: PlatformColor { get }
    var accentContentSecondary: PlatformColor { get }
    var accentContentTertiary: PlatformColor { get }
    var accentGlowPrimary: PlatformColor { get }
    var accentPrimary: PlatformColor { get }
    var accentSecondary: PlatformColor { get }
    var accentTertiary: PlatformColor { get }
    var accentTextPrimary: PlatformColor { get }
    var accentTextSecondary: PlatformColor { get }
    var accentTextTertiary: PlatformColor { get }

    var controlsDecorationPrimary: PlatformColor { get }
    var controlsDecorationSecondary: PlatformColor { get }
    var controlsDecorationTertiary: PlatformColor { get }
    var controlsFillPrimary: PlatformColor { get }
    var controlsFillSecondary: PlatformColor { get }
    var controlsFillTertiary: PlatformColor { get }

    var decorationPrimary: PlatformColor { get }
    var decorationSecondary: PlatformColor { get }
    var decorationTertiary: PlatformColor { get }

    var destructiveContentPrimary: PlatformColor { get }
    var destructiveContentSecondary: PlatformColor { get }
    var destructiveContentTertiary: PlatformColor { get }
    var destructiveGlow: PlatformColor { get }
    var destructivePrimary: PlatformColor { get }
    var destructiveSecondary: PlatformColor { get }
    var destructiveTertiary: PlatformColor { get }
    var destructiveTextPrimary: PlatformColor { get }
    var destructiveTextSecondary: PlatformColor { get }
    var destructiveTextTertiary: PlatformColor { get }

    var highlightPrimary: PlatformColor { get }

    var iconsPrimary: PlatformColor { get }
    var iconsSecondary: PlatformColor { get }
    var iconsTertiary: PlatformColor { get }

    var shadowPrimary: PlatformColor { get }
    var shadowSecondary: PlatformColor { get }
    var shadowTertiary: PlatformColor { get }

    var surfaceBackdrop: PlatformColor { get }
    var surfaceCanvas: PlatformColor { get }
    var surfacePrimary: PlatformColor { get }
    var surfaceSecondary: PlatformColor { get }
    var surfaceTertiary: PlatformColor { get }

    var textPrimary: PlatformColor { get }
    var textSecondary: PlatformColor { get }
    var textTertiary: PlatformColor { get }

    var toneShadePrimary: PlatformColor { get }
    var toneTintPrimary: PlatformColor { get }
}
