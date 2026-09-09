//
//  MultiTabMentionToken.swift
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

struct MultiTabMentionToken: Equatable {
    let range: NSRange
    let query: String

    /// Mirrors macOS's AIChatMentionTokenDetector. Spaces belong to the query; hard line breaks end it.
    static func token(in text: String, selection: NSRange) -> Self? {
        let text = text as NSString
        guard selection.length == 0, selection.location > 0, selection.location <= text.length else { return nil }
        let caret = selection.location
        for index in stride(from: caret - 1, through: 0, by: -1) {
            let character = text.character(at: index)
            if [0x0A, 0x0D, 0x2028, 0x2029].contains(character) { return nil }
            guard character == 0x40 else { continue }
            let startsToken = index == 0 || [0x20, 0x09, 0x0A, 0x0D, 0xA0, 0x2028, 0x2029].contains(text.character(at: index - 1))
            guard startsToken else { continue }
            return Self(range: NSRange(location: index, length: caret - index),
                        query: text.substring(with: NSRange(location: index + 1, length: caret - index - 1)))
        }
        return nil
    }

    func filter(_ tabs: [MultiTabAttachmentCandidate]) -> [MultiTabAttachmentCandidate] {
        MultiTabAttachmentCandidateFilter.filter(tabs, query: query)
    }
}
