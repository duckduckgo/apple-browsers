//
//  UTIAttachmentPolicy.swift
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
import Foundation

struct UTIAttachmentPolicy {

    static let maxImageAttachments = 3
    static let maxImagesPerConversation = 5

    let attachmentUsage: AIChatAttachmentUsage?
    let pendingAttachmentCount: Int

    var remainingImagesInConversation: Int {
        let conversationUsed = attachmentUsage?.imagesUsed ?? 0
        return max(0, Self.maxImagesPerConversation - conversationUsed)
    }

    var remainingImagesForPicker: Int {
        let perTurnRemaining = Self.maxImageAttachments - pendingAttachmentCount
        let conversationRemaining = remainingImagesInConversation - pendingAttachmentCount
        return max(0, min(perTurnRemaining, conversationRemaining))
    }

    var isConversationImageLimitReached: Bool {
        remainingImagesInConversation == 0
    }
}
