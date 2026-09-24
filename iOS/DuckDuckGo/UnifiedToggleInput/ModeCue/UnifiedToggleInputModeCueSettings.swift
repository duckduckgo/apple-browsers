//
//  UnifiedToggleInputModeCueSettings.swift
//  DuckDuckGo
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

import Core
import Foundation
import Persistence

/// Which Duck.ai cue the input shows, picked from the address bar's long-press menu while the options
/// are evaluated with the team. Every cue marks Duck.ai only, so Search stays plain.
enum UnifiedToggleInputModeCueStyle: String, CaseIterable, Identifiable {
    case off
    /// A band of colour loops across the typed text.
    case textShimmer
    /// The card's border glows and breathes.
    case glowingBorder
    /// A comet goes one and a half times around the card's border when the card opens in Duck.ai or
    /// switches to it, then fades.
    case borderSweep
    /// The keyboard's top edge shines while the card is open.
    case keyboardEdgeGlow
    /// The glowing border and the keyboard edge glow together.
    case glowingBorderAndKeyboardEdge

    static let fallback: UnifiedToggleInputModeCueStyle = .off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .textShimmer: "Input text shimmer"
        case .glowingBorder: "Glowing border"
        case .borderSweep: "Border sweep"
        case .keyboardEdgeGlow: "Keyboard edge glow"
        case .glowingBorderAndKeyboardEdge: "Glowing border + keyboard edge"
        }
    }
}

enum UnifiedToggleInputModeCueStorageKeys: String, StorageKeyDescribing {
    case style = "unified-toggle-input-mode-cue-style"
}

struct UnifiedToggleInputModeCueKeys: StoringKeys {
    let style = StorageKey<String>(UnifiedToggleInputModeCueStorageKeys.style)
}

/// Stores the chosen cue, falling back to `.off` while nothing has been picked.
struct UnifiedToggleInputModeCueSettings {

    private let storage: any KeyedStoring<UnifiedToggleInputModeCueKeys>

    init(storage: any KeyedStoring<UnifiedToggleInputModeCueKeys> = KeyedStorage(storage: UserDefaults.app)) {
        self.storage = storage
    }

    var style: UnifiedToggleInputModeCueStyle {
        get {
            guard let rawValue = storage.style else { return .fallback }
            return UnifiedToggleInputModeCueStyle(rawValue: rawValue) ?? .fallback
        }
        nonmutating set {
            storage.style = newValue.rawValue
        }
    }
}
