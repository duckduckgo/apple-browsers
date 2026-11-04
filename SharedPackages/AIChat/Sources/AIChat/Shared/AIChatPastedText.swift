//
//  AIChatPastedText.swift
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

/// A long plain-text paste staged as an attachment. `id` identifies the chip in the app and is never sent;
/// the wire shape is `payload`.
public struct AIChatPastedText: Identifiable, Equatable {
    public let id: UUID
    public let content: String

    public init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }

    /// UTF-16 code units, untrimmed, matching how the web app measures length.
    public var length: Int { content.utf16.count }

    /// First non-blank line, trimmed. Empty when every line is blank.
    public var title: String {
        content
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    public var payload: AIChatNativePrompt.NativePromptPastedText {
        AIChatNativePrompt.NativePromptPastedText(content: content)
    }
}
