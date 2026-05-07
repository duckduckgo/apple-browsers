//
//  AIChatPanelAttachment.swift
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

/// One attachment in the duck.ai omnibar panel — either an image upload or a page-content tab.
/// The omnibar displays attachments in a single horizontal carousel in *insertion order*, so we
/// need a single ordered list that can hold both kinds. `AddressBarSharedTextState` stores
/// `[AIChatPanelAttachment]` as the source of truth; the per-type lists (`aiChatAttachments` /
/// `aiChatTabAttachments`) are derived from it for the existing image-side and submit-side code
/// paths that work with one type at a time.
enum AIChatPanelAttachment: Equatable {
    case image(AIChatImageAttachment)
    case tab(AIChatTabAttachment)
    case file(AIChatFileAttachment)

    /// Stable string id usable as a dictionary key when reconciling views to attachments.
    /// Each attachment kind lives in its own id namespace, prefixed below so the carousel can
    /// key views across kinds without collisions.
    var attachmentId: String {
        switch self {
        case .image(let attachment):
            return "image:\(attachment.id.uuidString)"
        case .tab(let attachment):
            return "tab:\(attachment.id)"
        case .file(let attachment):
            return "file:\(attachment.id.uuidString)"
        }
    }

    static func == (lhs: AIChatPanelAttachment, rhs: AIChatPanelAttachment) -> Bool {
        switch (lhs, rhs) {
        case let (.image(a), .image(b)):
            // `AIChatImageAttachment` doesn't conform to `Equatable`. Match what the existing
            // shared-state setter does when deciding "did the list actually change": id plus
            // `===` identity on the `NSImage` instance (so a resize-replacement is treated as a
            // change but the same instance arriving twice isn't).
            return a.id == b.id && a.image === b.image
        case let (.tab(a), .tab(b)):
            return a == b
        case let (.file(a), .file(b)):
            // `AIChatFileAttachment` doesn't conform to `Equatable`. Files are immutable once
            // attached, so an id match is sufficient.
            return a.id == b.id
        default:
            return false
        }
    }
}
