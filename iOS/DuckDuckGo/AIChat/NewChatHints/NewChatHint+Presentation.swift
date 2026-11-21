//
//  NewChatHint+Presentation.swift
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
import DesignResourcesKitIcons
import UIKit

extension NewChatHint {

    /// The value pixels report for this hint, shared with Android.
    var pixelValue: String {
        switch self {
        case .documents: return "documents"
        case .photo: return "photo"
        case .imageGeneration: return "image_generation"
        }
    }

    var title: String {
        switch self {
        case .documents: return UserText.aiChatNewChatHintDocuments
        case .photo: return UserText.aiChatNewChatHintPhoto
        case .imageGeneration: return UserText.aiChatNewChatHintImageGeneration
        }
    }

    var icon: UIImage {
        switch self {
        case .documents: return DesignSystemImages.Glyphs.Size24.documentNew
        case .photo: return DesignSystemImages.Glyphs.Size24.image
        case .imageGeneration: return DesignSystemImages.Glyphs.Size24.images
        }
    }

    /// Whether `model` can do what the hint offers.
    func isSupported(by model: AIChatModel) -> Bool {
        switch self {
        case .documents: return model.supportsFileUpload
        case .photo: return model.supportsImageUpload
        case .imageGeneration: return model.supportsTool(.imageGeneration)
        }
    }

    /// The model a tap uses: the selected one when it can, otherwise the first accessible one that can.
    /// Nil when no model the user can pick supports the hint, which hides it.
    static func capableModel(for hint: NewChatHint, in models: [AIChatModel], selectedModelID: String?) -> AIChatModel? {
        let capable = models.filter { $0.entityHasAccess && hint.isSupported(by: $0) }
        return capable.first { $0.id == selectedModelID } ?? capable.first
    }

    /// Every hint in an order that stays the same for a tab, so the row doesn't reshuffle while the user looks at it.
    /// Seeded from a stable hash of the tab's ID: `String.hashValue` changes on every launch.
    static func order(forTab tabID: String) -> [NewChatHint] {
        var generator = SeededGenerator(seed: Self.stableHash(tabID))
        return allCases.shuffled(using: &generator)
    }

    /// FNV-1a, 64-bit.
    private static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
}

/// SplitMix64: small, deterministic for a given seed.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
