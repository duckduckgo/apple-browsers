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

}
