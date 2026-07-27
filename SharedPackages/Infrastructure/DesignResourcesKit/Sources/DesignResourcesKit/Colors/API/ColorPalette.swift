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

import Foundation

public struct DesignSystemPalette {
    /// The current color palette set globally.
    ///
    /// Used as a default parameter value when creating colors via public color extensions.
    public static var current: ColorPalette {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _current
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _current = newValue
        }
    }

    // `current` is a globally mutable & nonisolated variable, which isn't allowed in Swift 6.
    // To get around this, the public `current` getter is protected by a lock, and `nonisolated(unsafe)` is applied to
    // promise the Swift compiler that this value is threadsafe.
    nonisolated(unsafe) private static var _current: ColorPalette = .legacy
    private static let lock = NSLock()
}

public enum ColorPalette {
    case legacy
    case `default`

#if os(iOS)
    @available(*, deprecated, message: "Use .default — the rebranded palette is now the default.")
    public static var rebranded: ColorPalette { .default }
#endif

#if os(macOS)
    case coolGray
    case desert
    case green
    case orange
    case rose
    case slateBlue
    case violet
#endif

    var paletteDefinition: SharedColorPaletteDefinition.Type {
        switch self {
        case .default:
            return DefaultColorPalette.self
        case .legacy:
            return LegacyColorPalette.self
#if os(macOS)
        case .coolGray:
            return CoolGrayColorPalette.self
        case .desert:
            return DesertColorPalette.self
        case .green:
            return GreenColorPalette.self
        case .orange:
            return OrangeColorPalette.self
        case .rose:
            return RoseColorPalette.self
        case .slateBlue:
            return SlateBlueColorPalette.self
        case .violet:
            return VioletColorPalette.self
#endif
        }
    }

    public var isRebranded: Bool { self != .legacy }
}
