//
//  PromoSeverity.swift
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

/// How interruptive a promo is.
enum PromoSeverity: Comparable {
    /// Low interruption:
    /// - Doesn't get in the way of another action
    /// - Minimal distraction from the current task
    /// - Example: Highlighting a button via animation
    case low

    /// Medium interruption:
    /// - May get in the way of another action
    /// - Some distraction from current task
    /// - Example: An arrow Tip highlighting a feature
    case medium

    /// High interruption:
    /// - Does get in the way of another action
    /// - Distracts or blocks current task
    /// - Example: Set as Default dialog prompt that doesn't prevent page action
    case high
}
