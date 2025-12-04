//
//  NSColorExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa

extension NSColor {

    // MARK: Aliases

    static var burnerWindowMouseOverColor: NSColor {
        .alternateSelectedControlTextColor.withAlphaComponent(0.1)
    }

    static var burnerWindowMouseDownColor: NSColor {
        .alternateSelectedControlTextColor.withAlphaComponent(0.2)
    }

    static let detailAccentColor = NSColor(catalogName: "System", colorName: "detailAccentColor") ?? .controlAccentColor

    static var addressBarSuffix: NSColor {
        .detailAccentColor
    }

    static var progressBarGradientDark: NSColor {
        .controlAccentColor
    }

    static var progressBarGradientLight: NSColor {
        .detailAccentColor
    }

    static var textEditorBackground: NSColor {
        .blackWhite5
    }

    static var textEditorBorder: NSColor {
        .blackWhite10
    }

    /// Background color for permission warning rows (system permission disabled)
    /// Light mode: #FFF0C2, Dark mode: #C18010 at 16% opacity
    static var permissionWarningBackground: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0xC1 / 255.0, green: 0x80 / 255.0, blue: 0x10 / 255.0, alpha: 0.16)
            } else {
                return NSColor(red: 0xFF / 255.0, green: 0xF0 / 255.0, blue: 0xC2 / 255.0, alpha: 1.0)
            }
        }
    }

    // MARK: - Helpers

    var ciColor: CIColor {
        CIColor(color: self)!
    }

}
