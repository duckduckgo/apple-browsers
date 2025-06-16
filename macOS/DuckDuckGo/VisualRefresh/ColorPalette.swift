//
//  ColorPalette.swift
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

import AppKit

protocol ColorPalette {
    var surfaceBackdrop: NSColor { get }
    var surfaceCanvas: NSColor { get }
    var surfacePrimary: NSColor { get }
    var surfaceSecondary: NSColor { get }
    var surfaceTertiary: NSColor { get }

    var textPrimary: NSColor { get }
    var textSecondary: NSColor { get }
    var textTertiary: NSColor { get }

    var iconsPrimary: NSColor { get }
    var iconsSecondary: NSColor { get }
    var iconsTertiary: NSColor { get }

    var toneTint: NSColor { get }
    var toneShade: NSColor { get }

    var accentPrimary: NSColor { get }
    var accentSecondary: NSColor { get }
    var accentTertiary: NSColor { get }
    var accentGlow: NSColor { get }
    var accentTextPrimary: NSColor { get }
    var accentTextSecondary: NSColor { get }
    var accentTextTertiary: NSColor { get }
    var accentContentPrimary: NSColor { get }
    var accentContentSecondary: NSColor { get }
    var accentContentTertiary: NSColor { get }

    var accentAltPrimary: NSColor { get }
    var accentAltSecondary: NSColor { get }
    var accentAltTertiary: NSColor { get }
    var accentAltGlow: NSColor { get }
    var accentAltTextPrimary: NSColor { get }
    var accentAltTextSecondary: NSColor { get }
    var accentAltTextTertiary: NSColor { get }
    var accentAltContentPrimary: NSColor { get }
    var accentAltContentSecondary: NSColor { get }
    var accentAltContentTertiary: NSColor { get }

    var controlsFillPrimary: NSColor { get }
    var controlsFillSecondary: NSColor { get }
    var controlsFillTertiary: NSColor { get }
    var controlsDecorationPrimary: NSColor { get }
    var controlsDecorationSecondary: NSColor { get }
    var controlsDecorationTertiary: NSColor { get }

    var highlightDecoration: NSColor { get }

    var decorationPrimary: NSColor { get }
    var decorationSecondary: NSColor { get }
    var decorationTertiary: NSColor { get }

    var shadowPrimary: NSColor { get }
    var shadowSecondary: NSColor { get }
    var shadowTertiary: NSColor { get }

    var destructivePrimary: NSColor { get }
    var destructiveSecondary: NSColor { get }
    var destructiveTertiary: NSColor { get }
    var destructiveGlow: NSColor { get }
    var destructiveTextPrimary: NSColor { get }
    var destructiveTextSecondary: NSColor { get }
    var destructiveTextTertiary: NSColor { get }
    var destructiveContentPrimary: NSColor { get }
    var destructiveContentSecondary: NSColor { get }
    var destructiveContentTertiary: NSColor { get }
}

final class NewColorPalette: ColorPalette {
    let surfaceBackdrop: NSColor = .surfaceBackdrop
    let surfaceCanvas: NSColor = .surfaceCanvas
    let surfacePrimary: NSColor = .surfacePrimary
    let surfaceSecondary: NSColor = .surfaceSecondary
    let surfaceTertiary: NSColor = .surfaceTertiary
    let textPrimary: NSColor = .textPrimary
    let textSecondary: NSColor = .textSecondary
    let textTertiary: NSColor = .textTertiary
    let iconsPrimary: NSColor = .iconsPrimary
    let iconsSecondary: NSColor = .iconsSecondary
    let iconsTertiary: NSColor = .iconsTertiary
    let toneTint: NSColor = .toneTint
    let toneShade: NSColor = .toneShade
    let accentPrimary: NSColor = .accentPrimary
    let accentSecondary: NSColor = .accentSecondary
    let accentTertiary: NSColor = .accentTertiary
    let accentGlow: NSColor = .accentGlow
    let accentTextPrimary: NSColor = .accentTextPrimary
    let accentTextSecondary: NSColor = .accentTextSecondary
    let accentTextTertiary: NSColor = .accentTextTertiary
    let accentContentPrimary: NSColor = .accentContentPrimary
    let accentContentSecondary: NSColor = .accentContentSecondary
    let accentContentTertiary: NSColor = .accentContentTertiary
    let accentAltPrimary: NSColor = .accentAltPrimary
    let accentAltSecondary: NSColor = .accentAltSecondary
    let accentAltTertiary: NSColor = .accentAltTertiary
    let accentAltGlow: NSColor = .accentAltGlow
    let accentAltTextPrimary: NSColor = .accentAltTextPrimary
    let accentAltTextSecondary: NSColor = .accentAltTextSecondary
    let accentAltTextTertiary: NSColor = .accentAltTextTertiary
    let accentAltContentPrimary: NSColor = .accentAltContentPrimary
    let accentAltContentSecondary: NSColor = .accentAltContentSecondary
    let accentAltContentTertiary: NSColor = .accentAltContentTertiary
    let controlsFillPrimary: NSColor = .controlsFillPrimary
    let controlsFillSecondary: NSColor = .controlsFillSecondary
    let controlsFillTertiary: NSColor = .controlsFillTertiary
    let controlsDecorationPrimary: NSColor = .controlsDecorationPrimary
    let controlsDecorationSecondary: NSColor = .controlsDecorationSecondary
    let controlsDecorationTertiary: NSColor = .controlsDecorationTertiary
    let highlightDecoration: NSColor = .highlightDecoration
    let decorationPrimary: NSColor = .decorationPrimary
    let decorationSecondary: NSColor = .decorationSecondary
    let decorationTertiary: NSColor = .decorationTertiary
    let shadowPrimary: NSColor = .shadowPrimary
    let shadowSecondary: NSColor = .shadowSecondary
    let shadowTertiary: NSColor = .shadowTertiary
    let destructivePrimary: NSColor = .destructivePrimary
    let destructiveSecondary: NSColor = .destructiveSecondary
    let destructiveTertiary: NSColor = .destructiveTertiary
    let destructiveGlow: NSColor = .destructiveGlow
    let destructiveTextPrimary: NSColor = .destructiveTextPrimary
    let destructiveTextSecondary: NSColor = .destructiveTextSecondary
    let destructiveTextTertiary: NSColor = .destructiveTextTertiary
    let destructiveContentPrimary: NSColor = .destructiveContentPrimary
    let destructiveContentSecondary: NSColor = .destructiveContentSecondary
    let destructiveContentTertiary: NSColor = .destructiveContentTertiary
}
