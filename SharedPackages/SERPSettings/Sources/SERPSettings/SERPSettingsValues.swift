//
//  SERPSettingsValues.swift
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

/// Search Assist frequency (the SERP `kbe` / duckAssistFrequency setting).
///
/// Raw values are the exact strings the SERP stores, so the typed API can never
/// persist a value outside the SERP's allowlist.
public enum SearchAssistFrequency: String, CaseIterable {
    case never = "0"
    case onDemand = "1"
    case sometimes = "2"
    case often = "3"

    /// Bundled default used when the key is absent from native storage.
    public static let defaultValue: SearchAssistFrequency = .sometimes
}

/// Value encoding for the SERP "Hide AI-Generated Images" setting (`kbj`).
///
/// The SERP stores `"1"` to hide and `"-1"` to show. The native side models this
/// as a `Bool` (hidden), so this namespace centralizes the encoding.
public enum HideAIGeneratedImages {

    /// Stored when AI-generated images are hidden.
    public static let hideRawValue = "1"

    /// Stored when AI-generated images are shown.
    public static let showRawValue = "-1"

    /// Bundled default used when the key is absent from native storage (images shown).
    public static let defaultValue = false

    /// Maps the `Bool` (hidden) representation to the SERP raw value.
    public static func rawValue(forHidden hidden: Bool) -> String {
        hidden ? hideRawValue : showRawValue
    }

    /// Maps a SERP raw value to the `Bool` (hidden) representation, or `nil` if unrecognized.
    public static func isHidden(fromRawValue rawValue: String) -> Bool? {
        switch rawValue {
        case hideRawValue: return true
        case showRawValue: return false
        default: return nil
        }
    }
}

/// Value encoding for the SERP "Safe Search" setting (`kp`).
///
/// Raw values are the `kp` wire values from the SERP settings schema — strict `1`, moderate `-1`,
/// off `-2`. `rawValue` is the effective value sent in the native → SERP snapshot; ``storageValue``
/// is what's written to the blob (the default is omitted).
public enum SafeSearch: String {
    case strict = "1"
    case moderate = "-1"
    case off = "-2"

    /// Bundled default, used when the key is absent from native storage.
    public static let defaultValue: SafeSearch = .moderate

    /// The value written to native storage, or `nil` for the default (`moderate`), which is stored
    /// as key-absence — mirroring the SERP, which omits defaults from what it syncs to native.
    var storageValue: String? {
        self == .defaultValue ? nil : rawValue
    }
}
