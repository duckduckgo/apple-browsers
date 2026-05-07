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
