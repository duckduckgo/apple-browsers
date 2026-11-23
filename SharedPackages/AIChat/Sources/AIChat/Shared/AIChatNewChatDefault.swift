//
//  AIChatNewChatDefault.swift
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

/// The tier default a new chat starts on, as sent by `/models` in `newChatDefault`.
public enum AIChatNewChatDefault: Equatable, Sendable {
    /// The field is missing or unreadable: the server doesn't send a default yet.
    case unavailable
    /// The server sent `null`: it deliberately has no default for this user.
    case noDefault
    /// `reasoningEffort` is `nil` when the server omits it or sends one the app doesn't know.
    case model(id: String, reasoningEffort: AIChatReasoningEffort?)
}

extension AIChatNewChatDefault {

    private struct Wire: Decodable {
        let modelId: String
        let reasoningEffort: String?
    }

    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> AIChatNewChatDefault {
        guard container.contains(key) else { return .unavailable }
        if (try? container.decodeNil(forKey: key)) == true { return .noDefault }
        guard let wire = try? container.decode(Wire.self, forKey: key) else { return .unavailable }
        return .model(id: wire.modelId, reasoningEffort: wire.reasoningEffort.flatMap(AIChatReasoningEffort.init(rawValue:)))
    }

    /// Same shape as `/models`, read from an already-parsed JSON object such as the usage-limits snapshot.
    static func make(from value: Any?) -> AIChatNewChatDefault {
        guard let value else { return .unavailable }
        if value is NSNull { return .noDefault }
        guard let object = value as? [String: Any], let modelId = object["modelId"] as? String else { return .unavailable }
        let effort = (object["reasoningEffort"] as? String).flatMap(AIChatReasoningEffort.init(rawValue:))
        return .model(id: modelId, reasoningEffort: effort)
    }
}

/// The model and effort a new chat starts on. A `nil` effort leaves it to the model's own default.
public struct AIChatNewChatSelection: Equatable, Sendable {
    /// Whether the selection is the server's default or a fallback because the server had no usable one.
    public enum Origin: Equatable, Sendable {
        case server
        case fallback
    }

    public let modelId: String
    public let reasoningEffort: AIChatReasoningEffort?
    public let origin: Origin

    public init(modelId: String, reasoningEffort: AIChatReasoningEffort?, origin: Origin) {
        self.modelId = modelId
        self.reasoningEffort = reasoningEffort
        self.origin = origin
    }
}

public enum AIChatNewChatDefaultResolver {

    /// `overLimitDefault` wins while the user is over their usage limit, if they can use it.
    public static func resolve(_ newChatDefault: AIChatNewChatDefault,
                               overLimitDefault: AIChatNewChatDefault = .unavailable,
                               models: [AIChatModel],
                               userTier: AIChatUserTier) -> AIChatNewChatSelection? {
        if case let .model(id, reasoningEffort) = overLimitDefault,
           let selection = selection(modelId: id, reasoningEffort: reasoningEffort, origin: .server, in: models) {
            return selection
        }
        switch newChatDefault {
        case .noDefault:
            return firstAccessibleSelection(in: models)
        case .unavailable:
            return localDefaultSelection(for: userTier, in: models) ?? firstAccessibleSelection(in: models)
        case let .model(id, reasoningEffort):
            return selection(modelId: id, reasoningEffort: reasoningEffort, origin: .server, in: models)
                ?? localDefaultSelection(for: userTier, in: models)
                ?? firstAccessibleSelection(in: models)
        }
    }

    /// What a new chat starts on before `/models` has loaded, from the local tier defaults.
    public static func resolveBeforeModelsLoad(userTier: AIChatUserTier) -> AIChatNewChatSelection {
        AIChatLocalNewChatDefaults.selection(for: userTier)
    }

    private static func selection(modelId: String,
                                  reasoningEffort: AIChatReasoningEffort?,
                                  origin: AIChatNewChatSelection.Origin,
                                  in models: [AIChatModel]) -> AIChatNewChatSelection? {
        guard let model = models.first(where: { $0.id == modelId && $0.entityHasAccess }) else { return nil }
        let supportedEffort = reasoningEffort.flatMap { model.supportedReasoningEffort.contains($0) ? $0 : nil }
        return AIChatNewChatSelection(modelId: model.id, reasoningEffort: supportedEffort, origin: origin)
    }

    private static func localDefaultSelection(for userTier: AIChatUserTier, in models: [AIChatModel]) -> AIChatNewChatSelection? {
        let local = AIChatLocalNewChatDefaults.selection(for: userTier)
        return selection(modelId: local.modelId, reasoningEffort: local.reasoningEffort, origin: .fallback, in: models)
    }

    private static func firstAccessibleSelection(in models: [AIChatModel]) -> AIChatNewChatSelection? {
        models.first(where: \.entityHasAccess).map { AIChatNewChatSelection(modelId: $0.id, reasoningEffort: nil, origin: .fallback) }
    }
}

/// Tier defaults for when `/models` hasn't loaded yet or doesn't send `newChatDefault`.
enum AIChatLocalNewChatDefaults {

    static func selection(for userTier: AIChatUserTier) -> AIChatNewChatSelection {
        switch userTier {
        case .free:
            return AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback)
        case .plus, .pro, .internal:
            return AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback)
        }
    }
}
