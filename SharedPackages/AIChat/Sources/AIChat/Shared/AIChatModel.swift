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
    /// A shorter display name suitable for compact UI elements like the model picker button.
    public let shortName: String
    public let provider: ModelProvider
    public let supportsImageUpload: Bool
    /// Image formats supported by this model (e.g. ["png", "webp"]). Empty when image upload is not supported.
    public let supportedImageFormats: [String]
    /// Whether the current user has access to this model based on their subscription tier.
    public let entityHasAccess: Bool
    /// The access tiers this model belongs to (e.g. ["free", "plus", "pro", "internal"]).
    public let accessTier: [String]

    public enum ModelProvider {
        case openAI
        case meta
        case anthropic
        case mistral
        case oss
        case unknown
    }

    public init(id: String, name: String, shortName: String? = nil, provider: ModelProvider, supportsImageUpload: Bool, supportedImageFormats: [String] = [], entityHasAccess: Bool, accessTier: [String] = []) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? name
        self.provider = provider
        self.supportsImageUpload = supportsImageUpload
        self.supportedImageFormats = supportedImageFormats
        self.entityHasAccess = entityHasAccess
        self.accessTier = accessTier
    }

    /// Returns a platform-appropriate icon for use in menu items.
    #if os(macOS)
    public var menuIcon: NSImage? {
        switch provider {
        case .openAI: return DesignSystemImages.Glyphs.Size16.aiModelOpenAI
        case .meta: return DesignSystemImages.Glyphs.Size16.aiModelLlama
        case .anthropic: return DesignSystemImages.Glyphs.Size16.aiModelClaude
        case .mistral: return DesignSystemImages.Glyphs.Size16.aiModelMistral
        case .oss: return DesignSystemImages.Glyphs.Size16.aiModelOSS
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
        case .oss: return DesignSystemImages.Glyphs.Size16.aiModelOSS
        case .unknown: return nil
        }
    }
    #endif
}
