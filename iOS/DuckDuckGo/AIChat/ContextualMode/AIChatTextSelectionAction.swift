//
//  AIChatTextSelectionAction.swift
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

/// The Duck.ai actions offered on a text selection, mirroring the three macOS context-menu items
/// (`ContextMenuManager.handleSearchWebItem`). Declared in menu order.
enum AIChatTextSelectionAction: String, CaseIterable, Equatable {
    case summarize
    case ask
    case translate

    /// Whether picking this action submits a prompt straight away.
    ///
    /// Matches macOS exactly: summarize and translate act immediately (`revealChat(for: prompt)`),
    /// while ask only attaches the selection and waits for the user to write their own question
    /// (`revealChat()` with no prompt).
    var autoSubmits: Bool {
        switch self {
        case .summarize, .translate: return true
        case .ask: return false
        }
    }

    /// Whether the selected text becomes an attachment.
    ///
    /// Only ask does. Summarize and translate carry their text inside the tool payload
    /// (`TextSummary` / `Translation`), so attaching it as well would send the model the same text
    /// twice and leave a chip behind for a question that has already been asked.
    var attachesSelection: Bool {
        !autoSubmits
    }
}
