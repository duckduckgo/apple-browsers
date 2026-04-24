//
//  FreemiumDBPUserStateManaging.swift
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

/// Minimal interface for freemium user state needed by the iOS PIR manager.
/// The full implementation is provided by `FreemiumDBPUserStateManager`.
public protocol FreemiumDBPUserStateManaging {
    /// Whether the user has activated the freemium DBP feature (saved a profile and started scanning).
    var didActivate: Bool { get }
}

/// No-op default used until the real FreemiumDBPUserStateManager is wired in.
/// Always returns `didActivate = false`, preserving pre-freemium behavior.
struct DisabledFreemiumDBPUserStateManager: FreemiumDBPUserStateManaging {
    var didActivate: Bool { false }
}
