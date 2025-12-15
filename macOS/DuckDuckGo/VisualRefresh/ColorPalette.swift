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
import DesignResourcesKit

protocol ColorPalette {
    var surfaceBackdrop: NSColor { get }
    var surfaceCanvas: NSColor { get }
    var surfacePrimary: NSColor { get }
    var surfaceSecondary: NSColor { get }
    var surfaceTertiary: NSColor { get }

    var surfaceDecorationPrimary: NSColor { get }
    var surfaceDecorationSecondary: NSColor { get }
    var surfaceDecorationTertiary: NSColor { get }

    var textPrimary: NSColor { get }
    var textSecondary: NSColor { get }
    var textTertiary: NSColor { get }

    var iconsPrimary: NSColor { get }
    var iconsSecondary: NSColor { get }
    var iconsTertiary: NSColor { get }

    var toneShadePrimary: NSColor { get }

    var accentPrimary: NSColor { get }
    var accentSecondary: NSColor { get }
    var accentTertiary: NSColor { get }
    var accentGlowPrimary: NSColor { get }
    var accentTextPrimary: NSColor { get }
    var accentTextSecondary: NSColor { get }
    var accentTextTertiary: NSColor { get }
    var accentContentPrimary: NSColor { get }
    var accentContentSecondary: NSColor { get }
    var accentContentTertiary: NSColor { get }

    var accentAltPrimary: NSColor { get }
    var accentAltSecondary: NSColor { get }
    var accentAltTertiary: NSColor { get }
    var accentAltGlowPrimary: NSColor { get }
    var accentAltTextPrimary: NSColor { get }
    var accentAltTextSecondary: NSColor { get }
    var accentAltTextTertiary: NSColor { get }
    var accentAltContentPrimary: NSColor { get }
    var accentAltContentSecondary: NSColor { get }
    var accentAltContentTertiary: NSColor { get }

    var controlsFillPrimary: NSColor { get }
    var controlsFillSecondary: NSColor { get }
    var controlsFillTertiary: NSColor { get }

    var highlightPrimary: NSColor { get }

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
