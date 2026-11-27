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

    var modelId: String? {
        guard case let .model(id, _) = self else { return nil }
        return id
    }
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

    /// The usage-limits snapshot's default, which only ever names a model: without one the regular default applies.
    static func overLimitDefault(from value: Any?) -> AIChatNewChatDefault {
        guard let object = value as? [String: Any], let modelId = object["modelId"] as? String else { return .unavailable }
        let effort = (object["reasoningEffort"] as? String).flatMap(AIChatReasoningEffort.init(rawValue:))
        return .model(id: modelId, reasoningEffort: effort)
    }
}

/// The default the usage-limits snapshot sends while the user is over their limit.
public struct AIChatOverLimitNewChatDefault: Equatable, Sendable {
    /// `.unavailable` when over the limit without a named model.
    public let newChatDefault: AIChatNewChatDefault
    public let resetsAt: Date

    public static let notOverLimit = AIChatOverLimitNewChatDefault(.unavailable, resetsAt: .distantPast)

    public init(_ newChatDefault: AIChatNewChatDefault, resetsAt: Date) {
        self.newChatDefault = newChatDefault
        self.resetsAt = resetsAt
    }

    /// Lapses when the limit resets, so new chats go back to the regular default without a new snapshot.
    public func newChatDefault(at date: Date) -> AIChatNewChatDefault {
        isOverLimit(at: date) ? newChatDefault : .unavailable
    }

    /// Over the limit until it resets.
    public func isOverLimit(at date: Date) -> Bool {
        date < resetsAt
    }
}

/// The model and effort a new chat starts on. A `nil` effort leaves it to the model's own default.
public struct AIChatNewChatSelection: Equatable, Sendable {
    /// Whether the selection is a server default, the user's own default, or a fallback because neither was usable.
    public enum Origin: Equatable, Sendable {
        case server
        /// The "Default AI Model" setting from Duck.ai settings.
        case user
        /// The user set a default model the chat can't start on, so it starts on another default.
        case userDefaultUnavailable
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

    /// The default effort applies only while the input is on the default model.
    public func reasoningEffort(onModelId selectedModelId: String?) -> AIChatReasoningEffort? {
        selectedModelId == modelId ? reasoningEffort : nil
    }
}

public enum AIChatNewChatDefaultResolver {

    /// One source of a new-chat default, such as the over-limit or the `/models` default.
    public struct Candidate: Equatable, Sendable {
        public let newChatDefault: AIChatNewChatDefault
        public let origin: AIChatNewChatSelection.Origin

        public init(_ newChatDefault: AIChatNewChatDefault, origin: AIChatNewChatSelection.Origin) {
            self.newChatDefault = newChatDefault
            self.origin = origin
        }
    }

    /// The first candidate the user can use wins, then the local tier default (when the tier is known), then the first accessible model.
    /// A candidate that deliberately has no default skips straight to the first accessible model.
    /// Passing over a `.user` candidate reports `.userDefaultUnavailable`.
    public static func resolve(_ candidates: [Candidate],
                               models: [AIChatModel],
                               userTier: AIChatUserTier?) -> AIChatNewChatSelection? {
        let selection = firstUsableSelection(candidates, models: models, userTier: userTier)
        guard candidates.contains(where: { $0.origin == .user }), let selection, selection.origin != .user else { return selection }
        return AIChatNewChatSelection(modelId: selection.modelId, reasoningEffort: selection.reasoningEffort, origin: .userDefaultUnavailable)
    }

    private static func firstUsableSelection(_ candidates: [Candidate],
                                             models: [AIChatModel],
                                             userTier: AIChatUserTier?) -> AIChatNewChatSelection? {
        for candidate in candidates {
            switch candidate.newChatDefault {
            case .unavailable:
                continue
            case .noDefault:
                return firstAccessibleSelection(in: models)
            case let .model(id, reasoningEffort):
                if let selection = selection(modelId: id, reasoningEffort: reasoningEffort, origin: candidate.origin, in: models) {
                    return selection
                }
            }
        }
        return userTier.flatMap { localDefaultSelection(for: $0, in: models) } ?? firstAccessibleSelection(in: models)
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
