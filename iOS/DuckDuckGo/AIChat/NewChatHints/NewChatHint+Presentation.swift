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

    /// Every hint, best first: the order Android's taps per new chat ranked (image generation, then photos, then
    /// files). Fixed rather than shuffled, so the most used hint sits in the first slot, which is always on screen.
    static let displayOrder: [NewChatHint] = [.imageGeneration, .photo, .documents]
}
