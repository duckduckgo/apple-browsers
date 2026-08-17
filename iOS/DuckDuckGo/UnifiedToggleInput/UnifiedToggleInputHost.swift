//
//  UnifiedToggleInputHost.swift
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

import Foundation

/// Identifies the surface that hosts a `UnifiedToggleInputCoordinator`.
/// Parameterizes which UTI elements are visible (toggle, fire, suggestions overlay,
/// floating submit, page-context chip).
enum UnifiedToggleInputHost: Equatable {
    /// Hosted by `MainViewController` — the omnibar / full-tab AI chat surface.
    case omnibar
    /// Hosted by `AIChatContextualWebViewController` — the post-submit contextual chat surface.
    case contextualChat
}

/// The state a contextual-chat input is born into. Composes two otherwise-independent facts — whether
/// the session has a prompt in it yet, and whether a keyboard comes up alongside the input — as the
/// three combinations that actually occur, so the contradictory fourth can't be expressed.
enum ContextualInputStart: Equatable {
    /// Nothing submitted yet: the user is about to type, so the input opens expanded and takes focus.
    case expandedPreSubmit
    /// Installed into a chat already on screen, taking focus as it appears.
    case expandedOnExistingChat
    /// Opening onto a chat that already exists with no keyboard, so the input starts as the plain pill.
    case collapsedOnExistingChat

    /// Drives the follow-up placeholder and the model chip, which read as a fresh session until a prompt lands.
    var isPreSubmit: Bool { self == .expandedPreSubmit }

    var startsCollapsed: Bool { self == .collapsedOnExistingChat }
}
