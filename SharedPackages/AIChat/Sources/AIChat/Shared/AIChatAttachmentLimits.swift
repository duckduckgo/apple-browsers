//
//  AIChatAttachmentLimits.swift
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

public struct AIChatAttachmentFileLimits: Decodable, Equatable {
    public let maxPerConversation: Int
    public let maxFileSizeMB: Int
    public let maxTotalFileSizeBytes: Int
    public let maxPagesPerFile: Int

    public init(maxPerConversation: Int, maxFileSizeMB: Int, maxTotalFileSizeBytes: Int, maxPagesPerFile: Int) {
        self.maxPerConversation = maxPerConversation
        self.maxFileSizeMB = maxFileSizeMB
        self.maxTotalFileSizeBytes = maxTotalFileSizeBytes
        self.maxPagesPerFile = maxPagesPerFile
    }
}

public struct AIChatAttachmentImageLimits: Decodable, Equatable {
    public let maxPerTurn: Int
    public let maxPerConversation: Int
    public let maxInputCharsWithAttachments: Int

    public init(maxPerTurn: Int, maxPerConversation: Int, maxInputCharsWithAttachments: Int) {
        self.maxPerTurn = maxPerTurn
        self.maxPerConversation = maxPerConversation
        self.maxInputCharsWithAttachments = maxInputCharsWithAttachments
    }
}

public struct AIChatAttachmentTierLimits: Decodable, Equatable {
    public let files: AIChatAttachmentFileLimits
    public let images: AIChatAttachmentImageLimits

    public init(files: AIChatAttachmentFileLimits, images: AIChatAttachmentImageLimits) {
        self.files = files
        self.images = images
    }
}

public struct AIChatAttachmentLimits: Decodable, Equatable {
    public let free: AIChatAttachmentTierLimits
    public let plus: AIChatAttachmentTierLimits
    public let pro: AIChatAttachmentTierLimits

    public init(free: AIChatAttachmentTierLimits, plus: AIChatAttachmentTierLimits, pro: AIChatAttachmentTierLimits) {
        self.free = free
        self.plus = plus
        self.pro = pro
    }

    public func limits(for userTier: AIChatUserTier) -> AIChatAttachmentTierLimits {
        switch userTier {
        case .free:
            return free
        case .plus:
            return plus
        case .pro, .internal:
            return pro
        }
    }
}
