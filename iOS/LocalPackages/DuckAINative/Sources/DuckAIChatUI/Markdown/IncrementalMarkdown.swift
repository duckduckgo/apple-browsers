//
//  IncrementalMarkdown.swift
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

struct PresentedMarkdownBlock: Identifiable, Equatable {
    let id: Int
    let block: MarkdownBlock
    let isStreaming: Bool
}

struct IncrementalMarkdown {
    private(set) var blocks: [PresentedMarkdownBlock] = []
    private(set) var consumedUTF8 = 0
    private(set) var lastParsedUTF8 = 0
    private var source = ""
    private var streaming = true
    private var frozen: [PresentedMarkdownBlock] = []

    mutating func update(_ text: String, isStreaming: Bool) {
        let normalized = MarkdownParser.normalize(text)
        guard normalized != source || streaming != isStreaming else { return }
        if !normalized.hasPrefix(source) {
            frozen = []
            consumedUTF8 = 0
        }
        source = normalized
        streaming = isStreaming
        let start = source.utf8.index(source.utf8.startIndex, offsetBy: consumedUTF8)
        let suffix = String(source[start...])
        lastParsedUTF8 = suffix.utf8.count
        let parsed = MarkdownParser.scan(suffix, isStreaming: isStreaming)
        let base = consumedUTF8
        let tail = parsed.map {
            PresentedMarkdownBlock(id: base + $0.start, block: $0.block, isStreaming: isStreaming && !$0.isStable)
        }
        blocks = frozen + tail
        for (record, block) in zip(parsed, tail) {
            guard record.isStable else { break }
            frozen.append(block)
            consumedUTF8 = base + record.end
        }
    }
}
