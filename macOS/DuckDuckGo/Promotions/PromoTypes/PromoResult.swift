//
//  PromoResult.swift
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

/// Outcome of showing a promo.
/// Determines whether the promo is eligible to be shown again on the next trigger, and if so, after what interval (cooldown).
enum PromoResult {
    /// User engaged with the CTA. Permanently dismissed.
    case actioned

    /// User dismissed without engaging.
    /// - `.ignored()` (default, cooldown is nil) -> permanently dismissed.
    /// - `.ignored(cooldown: interval)` -> temporarily dismissed; may re-show after cooldown interval elapses.
    case ignored(cooldown: TimeInterval? = nil)

    /// Promo retracted itself or encountered an error.
    /// No state change recorded; eligible again on next trigger.
    case noChange
}
