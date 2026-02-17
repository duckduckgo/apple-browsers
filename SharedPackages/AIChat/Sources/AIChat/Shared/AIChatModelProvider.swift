//
//  AIChatModelProvider.swift
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

/// Represents an AI model available in the model picker.
public struct AIChatModel {
    public let id: String
    public let displayName: String
    public let shortDisplayName: String
    public let provider: ModelProvider
    public let tier: ModelTier

    public enum ModelProvider {
        case openAI
        case meta
        case anthropic
        case mistral
    }

    public enum ModelTier {
        case free
        case premium
    }

    public init(id: String, displayName: String, shortDisplayName: String, provider: ModelProvider, tier: ModelTier) {
        self.id = id
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.provider = provider
        self.tier = tier
    }

    private var sfSymbolName: String {
        switch provider {
        case .openAI: return "brain.head.profile"
        case .meta: return "hare"
        case .anthropic: return "sparkles"
        case .mistral: return "wind"
        }
    }

    /// Returns a platform-appropriate icon for use in menu items.
    /// Uses SF Symbols as placeholders until real provider icons are available.
    #if os(macOS)
    public var menuIcon: NSImage? {
        let image = NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: displayName)
        image?.isTemplate = true
        return image
    }
    #elseif os(iOS)
    public var menuIcon: UIImage? {
        UIImage(systemName: sfSymbolName)
    }
    #endif
}

/// Provides mock model data for the AI model picker.
/// This will be replaced with data from the JS bridge once available.
public enum AIChatModelProvider {

    public static let defaultModel = freeModels[0]

    public static let freeModels: [AIChatModel] = [
        AIChatModel(id: "gpt-4o-mini", displayName: "GPT-4o mini", shortDisplayName: "4o-mini", provider: .openAI, tier: .free),
        AIChatModel(id: "gpt-5-mini", displayName: "GPT-5 mini", shortDisplayName: "5-mini", provider: .openAI, tier: .free),
        AIChatModel(id: "gpt-oss-120b", displayName: "GPT-OSS 120B", shortDisplayName: "OSS-120B", provider: .openAI, tier: .free),
        AIChatModel(id: "llama-4-scout", displayName: "Llama 4 Scout", shortDisplayName: "4-Scout", provider: .meta, tier: .free),
        AIChatModel(id: "claude-3-5-haiku", displayName: "Claude 3.5 Haiku", shortDisplayName: "3.5-Haiku", provider: .anthropic, tier: .free),
        AIChatModel(id: "mistral-small-3", displayName: "Mistral Small 3", shortDisplayName: "Small-3", provider: .mistral, tier: .free),
    ]

    public static let premiumModels: [AIChatModel] = [
        AIChatModel(id: "gpt-4o", displayName: "GPT-4o", shortDisplayName: "4o", provider: .openAI, tier: .premium),
        AIChatModel(id: "gpt-5-1", displayName: "GPT-5.1", shortDisplayName: "5.1", provider: .openAI, tier: .premium),
        AIChatModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", shortDisplayName: "Sonnet-4.5", provider: .anthropic, tier: .premium),
        AIChatModel(id: "llama-4-maverick", displayName: "Llama 4 Maverick", shortDisplayName: "4-Maverick", provider: .meta, tier: .premium),
    ]
}
