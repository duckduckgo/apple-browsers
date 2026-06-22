//
//  AIChatReasoning.swift
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

public enum AIChatReasoningEffort: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
}

/// Per-reasoning-effort access.
public struct AIChatReasoningEffortAccess: Equatable, Sendable {
    public let effort: AIChatReasoningEffort
    public let accessTier: [String]
    public let entityHasAccess: Bool

    public init(effort: AIChatReasoningEffort, accessTier: [String], entityHasAccess: Bool) {
        self.effort = effort
        self.accessTier = accessTier
        self.entityHasAccess = entityHasAccess
    }
}

public enum AIChatReasoningMode: String, CaseIterable, Codable, Equatable, Sendable {
    case fast
    case reasoning
    case extendedReasoning = "extended_reasoning"
}

public extension AIChatModel {
    var availableReasoningModes: [AIChatReasoningMode] {
        reasoningModeMappings.map { $0.mode }
    }

    var accessibleReasoningModes: [AIChatReasoningMode] {
        accessibleReasoningModeMappings.map { $0.mode }
    }

    var supportsReasoningPicker: Bool {
        availableReasoningModes.count > 1 && !accessibleReasoningModes.isEmpty
    }

    /// Returns `true` if the given effort is accessible to the current user for this
    /// model. When `reasoningEffortAccess` is `nil` the model has no per-effort gating
    /// metadata and all supported efforts are considered accessible (keeping backwards-compatibility).
    /// Returns `false` for efforts that aren't in `supportedReasoningEffort`.
    func isAccessible(_ effort: AIChatReasoningEffort) -> Bool {
        guard supportedReasoningEffort.contains(effort) else { return false }
        guard let access = reasoningEffortAccess else { return true }
        guard let entry = access.first(where: { $0.effort == effort }) else { return true }

        return entry.entityHasAccess
    }

    /// Returns the per-effort `accessTier` for `effort` when the user is gated, or `nil` otherwise.
    func accessTier(for effort: AIChatReasoningEffort) -> [String]? {
        guard let access = reasoningEffortAccess,
              let entry = access.first(where: { $0.effort == effort }),
              !entry.entityHasAccess else {
            return nil
        }
        return entry.accessTier
    }

    func resolvedReasoningMode(from preferredMode: AIChatReasoningMode?) -> AIChatReasoningMode? {
        let modes = accessibleReasoningModes
        guard !modes.isEmpty else { return nil }
        guard let preferredMode else { return modes.first }

        return modes.contains(preferredMode) ? preferredMode : modes.first
    }

    func reasoningEffort(for selectedMode: AIChatReasoningMode?) -> AIChatReasoningEffort? {
        guard let selectedMode, availableReasoningModes.contains(selectedMode) else { return nil }

        return reasoningModeMappings.first { $0.mode == selectedMode }?.effort
    }

    func resolvedReasoningEffort(from preferredMode: AIChatReasoningMode?) -> AIChatReasoningEffort? {
        guard let resolvedMode = resolvedReasoningMode(from: preferredMode) else { return nil }

        return accessibleReasoningModeMappings.first { $0.mode == resolvedMode }?.effort
    }
}

private extension AIChatModel {
    var reasoningModeMappings: [(mode: AIChatReasoningMode, effort: AIChatReasoningEffort)] {
        AIChatReasoningMode.mappings.compactMap { mapping in
            guard let effort = firstSupportedReasoningEffort(in: mapping.supportedEfforts) else { return nil }
            return (mapping.mode, effort)
        }
    }

    var accessibleReasoningModeMappings: [(mode: AIChatReasoningMode, effort: AIChatReasoningEffort)] {
        AIChatReasoningMode.mappings.compactMap { mapping in
            guard let effort = firstAccessibleReasoningEffort(in: mapping.supportedEfforts) else { return nil }
            return (mapping.mode, effort)
        }
    }

    func firstSupportedReasoningEffort(in candidates: [AIChatReasoningEffort]) -> AIChatReasoningEffort? {
        candidates.first { supportedReasoningEffort.contains($0) }
    }

    func firstAccessibleReasoningEffort(in candidates: [AIChatReasoningEffort]) -> AIChatReasoningEffort? {
        candidates.first { supportedReasoningEffort.contains($0) && isAccessible($0) }
    }
}

private struct AIChatReasoningModeMapping {
    let mode: AIChatReasoningMode
    let supportedEfforts: [AIChatReasoningEffort]
}

private extension AIChatReasoningMode {
    static let mappings: [AIChatReasoningModeMapping] = [
        AIChatReasoningModeMapping(mode: .fast, supportedEfforts: [.none, .minimal]),
        AIChatReasoningModeMapping(mode: .reasoning, supportedEfforts: [.low]),
        AIChatReasoningModeMapping(mode: .extendedReasoning, supportedEfforts: [.high, .medium])
    ]
}
