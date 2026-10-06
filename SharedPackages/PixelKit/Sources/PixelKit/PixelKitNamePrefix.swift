//
//  PixelKitNamePrefix.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// What PixelKit puts in front of a pixel's `name`.
///
/// Set on the event, via `PixelKit.Event.namePrefix`. Defaults to `.platformDefault`.
public enum PixelKitNamePrefix: Equatable {

    /// The host platform's prefix: `m_mac_` on macOS, nothing on iOS.
    ///
    /// On macOS a name already starting with `m_mac_` is left alone, and a `DebugEvent` gets
    /// `m_mac_debug_` instead.
    case platformDefault

    /// Prepend nothing. `name` is the complete pixel name.
    case none

    /// Prepend a literal, e.g. `.custom("m_")`. Applied on every platform.
    case custom(String)

    /// The string this prefix prepends, or `nil` for `.platformDefault`, which is resolved at fire
    /// time from the platform PixelKit was built for.
    public var literal: String? {
        switch self {
        case .platformDefault: return nil
        case .none: return ""
        case .custom(let prefix): return prefix
        }
    }
}
