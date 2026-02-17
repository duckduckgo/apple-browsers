//
//  Color+Hex.swift
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

import SwiftUI

public extension Color {

    /// Creates a color from a 24-bit RGB hex integer in the sRGB color space.
    ///
    /// The value is interpreted as `0xRRGGBB` where each pair represents an 8-bit
    /// channel value (0–255).
    ///
    /// ```swift
    /// Color(0xFF6600)              // bright orange, fully opaque
    /// Color(0xFF6600, opacity: 0.5) // bright orange, 50% opacity
    /// ```
    ///
    /// - Parameters:
    ///   - hex: A `UInt32` encoding RGB channels, e.g. `0x3969EF`.
    ///   - opacity: The opacity of the color, from `0` (transparent) to `1` (opaque). Defaults to `1`.
    init(_ hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Creates a color by parsing a hex string in the sRGB color space.
    ///
    /// Accepts 6-character (`RRGGBB`) or 8-character (`RRGGBBAA`) hex strings,
    /// with or without a leading `#`. Returns `nil` if the string is not a valid
    /// hex color representation.
    ///
    /// ```swift
    /// Color(hex: "#FF6600")     // bright orange, fully opaque
    /// Color(hex: "FF660080")    // bright orange, ~50% opacity
    /// Color(hex: "ZZZ")         // nil – invalid input
    /// ```
    ///
    /// - Parameter hex: A hex color string, e.g. `"#3969EF"` or `"3969EFFF"`.
    /// - Returns: A `Color` if parsing succeeds, otherwise `nil`.
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        // Normalize RRGGBB → RRGGBBFF so both formats share a single extraction path
        let rgba: UInt64
        switch sanitized.count {
        case 6:
            guard let value = UInt64(sanitized, radix: 16) else { return nil }
            rgba = (value << 8) | 0xFF
        case 8:
            guard let value = UInt64(sanitized, radix: 16) else { return nil }
            rgba = value
        default:
            return nil
        }

        self.init(.sRGB,
                  red: Double((rgba >> 24) & 0xFF) / 255.0,
                  green: Double((rgba >> 16) & 0xFF) / 255.0,
                  blue: Double((rgba >> 8) & 0xFF) / 255.0,
                  opacity: Double(rgba & 0xFF) / 255.0)
    }
}
