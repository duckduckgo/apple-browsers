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
/// This lives on the event rather than on `PixelKit.Options` because a pixel's name is a contract
/// with its definition in `PixelDefinitions` and with whatever queries it. A per-call setting would
/// let two call sites disagree about what the same event is called, with nothing to catch it — which
/// is how the platform-suffix drift happened. `Options` is for transport and payload only.
public enum PixelKitNamePrefix: Equatable {

    /// Let PixelKit apply the host platform's convention: `m_mac_` on macOS (or `m_mac_debug_` for a
    /// `DebugEvent`), nothing on iOS, where names carry too varied a set of prefixes to correct
    /// after the fact.
    ///
    /// The default, and what a macOS pixel almost always wants.
    case platformDefault

    /// Prepend nothing: `name` is already the complete pixel name.
    ///
    /// Equivalent to `.custom("")`. This is what the old `doNotEnforcePrefix: true` argument meant,
    /// moved from ~170 call sites onto the events that were passing it at every one of them.
    case none

    /// Prepend a literal string, for example `"m_"`.
    ///
    /// For a shared package whose prefix is chosen by the host platform rather than by the pixel,
    /// prefer `PixelKit.Event.prefixed(_:)` over restating this on every case.
    case custom(String)

    /// The string this prefix prepends, or `nil` for `.platformDefault`, where the answer depends on
    /// the platform PixelKit was built for and is decided during name resolution.
    public var literal: String? {
        switch self {
        case .platformDefault: return nil
        case .none: return ""
        case .custom(let prefix): return prefix
        }
    }
}
