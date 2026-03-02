//
//  AIChatModel.swift
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

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import DesignResourcesKitIcons

/// Represents an AI model available in the model picker.
public struct AIChatModel {
    public let id: String
    public let name: String
    public let provider: ModelProvider
    public let supportsImageUpload: Bool
    /// Whether the current user has access to this model based on their subscription tier.
    public let entityHasAccess: Bool

    public enum ModelProvider {
        case openAI
        case meta
        case anthropic
        case mistral
        case unknown
    }

    public init(id: String, name: String, provider: ModelProvider, supportsImageUpload: Bool, entityHasAccess: Bool) {
        self.id = id
        self.name = name
        self.provider = provider
        self.supportsImageUpload = supportsImageUpload
        self.entityHasAccess = entityHasAccess
    }

    /// Returns a platform-appropriate icon for use in menu items.
    #if os(macOS)
    public var menuIcon: NSImage? {
        switch provider {
        case .openAI: return DesignSystemImages.Glyphs.Size16.aiModelOpenAI
        case .meta: return DesignSystemImages.Glyphs.Size16.aiModelLlama
        case .anthropic: return DesignSystemImages.Glyphs.Size16.aiModelClaude
        case .mistral: return DesignSystemImages.Glyphs.Size16.aiModelMistral
        case .unknown: return nil
        }
    }
    #elseif os(iOS)
    public var menuIcon: UIImage? {
        switch provider {
        case .openAI: return DesignSystemImages.Glyphs.Size16.aiModelOpenAI
        case .meta: return DesignSystemImages.Glyphs.Size16.aiModelLlama
        case .anthropic: return DesignSystemImages.Glyphs.Size16.aiModelClaude
        case .mistral: return DesignSystemImages.Glyphs.Size16.aiModelMistral
        case .unknown: return nil
        }
    }
    #endif
}
