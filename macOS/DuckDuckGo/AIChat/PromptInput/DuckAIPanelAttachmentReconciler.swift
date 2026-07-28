//
//  DuckAIPanelAttachmentReconciler.swift
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
import Foundation

/// Keeps the unified panel attachment list in insertion order when one attachment kind changes.
/// Shared by every `DuckAIPromptDraftStoring` implementation so the carousel's ordering rules
/// can't drift between surfaces.
enum DuckAIPanelAttachmentReconciler {

    static func reconciled(_ current: [AIChatPanelAttachment], replacingImagesWith images: [AIChatImageAttachment]) -> [AIChatPanelAttachment] {
        reconciled(current,
                   replacingKindWith: images.map(AIChatPanelAttachment.image),
                   matchesKind: { if case .image = $0 { true } else { false } })
    }

    static func reconciled(_ current: [AIChatPanelAttachment], replacingTabsWith tabs: [AIChatTabAttachment]) -> [AIChatPanelAttachment] {
        reconciled(current,
                   replacingKindWith: tabs.map(AIChatPanelAttachment.tab),
                   matchesKind: { if case .tab = $0 { true } else { false } })
    }

    static func reconciled(_ current: [AIChatPanelAttachment], replacingFilesWith files: [AIChatFileAttachment]) -> [AIChatPanelAttachment] {
        reconciled(current,
                   replacingKindWith: files.map(AIChatPanelAttachment.file),
                   matchesKind: { if case .file = $0 { true } else { false } })
    }

    /// Entries of other kinds keep their positions; entries of the replaced kind are taken from
    /// `updatedOfKind` (dropping removed ids), and genuinely new ids are appended.
    private static func reconciled(
        _ current: [AIChatPanelAttachment],
        replacingKindWith updatedOfKind: [AIChatPanelAttachment],
        matchesKind: (AIChatPanelAttachment) -> Bool
    ) -> [AIChatPanelAttachment] {
        let updatedById: [String: AIChatPanelAttachment] = Dictionary(
            uniqueKeysWithValues: updatedOfKind.map { ($0.attachmentId, $0) }
        )
        var consumed = Set<String>()
        var result: [AIChatPanelAttachment] = []
        for entry in current {
            if matchesKind(entry) {
                if let updated = updatedById[entry.attachmentId] {
                    result.append(updated)
                    consumed.insert(entry.attachmentId)
                }
            } else {
                result.append(entry)
            }
        }
        for entry in updatedOfKind where !consumed.contains(entry.attachmentId) {
            result.append(entry)
        }

        return result
    }
}

extension NSRange {

    /// Clamps a selection range so it never points past the end of the text it describes.
    func clamped(toTextLength length: Int) -> NSRange {
        if location > length {
            return NSRange(location: length, length: 0)
        }
        if upperBound > length {
            return NSRange(location: location, length: max(0, length - location))
        }
        return self
    }
}
