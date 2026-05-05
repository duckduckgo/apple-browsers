//
//  UnifiedInputTabState.swift
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

import AIChat

/// Per-tab unified address-bar configuration. Persisted with the tab via
/// NSCoding so reopening the app restores the user's last-used input setup
/// rather than falling back to the global default.
public struct UnifiedInputTabState: Equatable {
    public var preferredTextEntryMode: TextEntryMode
    public var selectedModelID: String?
    public var selectedReasoningMode: AIChatReasoningMode?
    public var selectedTool: AIChatRAGTool?

    public init(
        preferredTextEntryMode: TextEntryMode = .search,
        selectedModelID: String? = nil,
        selectedReasoningMode: AIChatReasoningMode? = nil,
        selectedTool: AIChatRAGTool? = nil
    ) {
        self.preferredTextEntryMode = preferredTextEntryMode
        self.selectedModelID = selectedModelID
        self.selectedReasoningMode = selectedReasoningMode
        self.selectedTool = selectedTool
    }
}

protocol UnifiedInputTabStateProviding: AnyObject {
    var uid: String { get }
    var unifiedInputState: UnifiedInputTabState { get set }
}
