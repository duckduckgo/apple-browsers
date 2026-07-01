//
//  IPadDuckAIControlValues.swift
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
import AIChat

/// The values currently selected across the iPad address-bar Duck.ai controls
protocol IPadDuckAIControlValues {

    /// The Duck.ai model id selected in the iPad address-bar model picker, or `nil`.
    var selectedModelId: String? { get }

    /// The Duck.ai reasoning effort selected in the iPad address-bar reasoning picker, or `nil`.
    var selectedReasoningEffort: AIChatReasoningEffort? { get }

    /// The Duck.ai tools selected in the iPad address-bar tool picker, or `nil` when no tool is
    /// selected or the picker is inactive.
    var selectedTools: [AIChatRAGTool]? { get }
}

/// A concrete snapshot of `IPadDuckAIControlValues`. Every value defaults to `nil`, so callers
/// without active controls (iPhone, the base omnibar, tests) can use `IPadDuckAIControlValuesSnapshot()`.
struct IPadDuckAIControlValuesSnapshot: IPadDuckAIControlValues {
    var selectedModelId: String?
    var selectedReasoningEffort: AIChatReasoningEffort?
    var selectedTools: [AIChatRAGTool]?
}
