//
//  PlatformColor.swift
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

#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

// MARK: - UIColor / PlatformColor

#if canImport(UIKit)
public extension UIColor {

    convenience init(hex: String) {
        let rawColor = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let hasAlpha = rawColor.count == 8
        var parsed: UInt64 = 0

        Scanner(string: rawColor).scanHexInt64(&parsed)

        let componentA = CGFloat((parsed >> 24) & 0xFF) / 255.0
        let componentB = CGFloat((parsed >> 16) & 0xFF) / 255.0
        let componentC = CGFloat((parsed >> 8) & 0xFF) / 255.0
        let componentD = CGFloat(parsed & 0xFF) / 255.0
        let defaultAlpha = CGFloat(1.0)

        guard hasAlpha else {
            self.init(red: componentB, green: componentC, blue: componentD, alpha: defaultAlpha)
            return
        }

        self.init(red: componentA, green: componentB, blue: componentC, alpha: componentD)
    }

    convenience init(darkHex: String, lightHex: String) {
        self.init { trait in
            switch trait.userInterfaceStyle {
            case .dark:
                UIColor(hex: darkHex)
            default:
                UIColor(hex: lightHex)
            }
        }
    }
}
#endif

// MARK: - NSColor / PlatformColor

#if canImport(AppKit)
public extension NSColor {

    convenience init(hex: String) {
        let rawColor = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let hasAlpha = rawColor.count == 8
        var parsed: UInt64 = 0

        Scanner(string: rawColor).scanHexInt64(&parsed)

        let componentA = CGFloat((parsed >> 24) & 0xFF) / 255.0
        let componentB = CGFloat((parsed >> 16) & 0xFF) / 255.0
        let componentC = CGFloat((parsed >> 8) & 0xFF) / 255.0
        let componentD = CGFloat(parsed & 0xFF) / 255.0
        let defaultAlpha = CGFloat(1)

        guard hasAlpha else {
            self.init(srgbRed: componentB, green: componentC, blue: componentD, alpha: defaultAlpha)
            return
        }

        self.init(srgbRed: componentA, green: componentB, blue: componentC, alpha: componentD)
    }

    convenience init(name colorName: NSColor.Name? = nil, darkHex: String, lightHex: String) {
        self.init(name: colorName) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                NSColor(hex: darkHex)

            default:
                NSColor(hex: lightHex)
            }
        }
    }
}
#endif
