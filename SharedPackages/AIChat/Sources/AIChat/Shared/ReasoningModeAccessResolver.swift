//
//  ReasoningModeAccessResolver.swift
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

public protocol ReasoningModeAccessResolving {
    /// The public access tier required to use `mode` on `model`, or `nil` when the mode
    /// is already accessible to the current user (or the model doesn't support it).
    func requiredPublicTier(for mode: AIChatReasoningMode, model: AIChatModel) -> AIChatModelPublicAccessTier?

    /// Whether a user at `userTier` is allowed to select a mode that requires `requiredTier`.
    func canSelect(modeRequiring requiredTier: AIChatModelPublicAccessTier, userTier: AIChatUserTier) -> Bool
}

public struct ReasoningModeAccessResolver: ReasoningModeAccessResolving {

    public init() {}

    public func requiredPublicTier(for mode: AIChatReasoningMode, model: AIChatModel) -> AIChatModelPublicAccessTier? {
        guard !model.accessibleReasoningModes.contains(mode) else { return nil }
        guard let effort = model.reasoningEffort(for: mode) else { return nil }
        return model.lowestPublicAccessTier(for: effort)
    }

    public func canSelect(modeRequiring requiredTier: AIChatModelPublicAccessTier, userTier: AIChatUserTier) -> Bool {
        switch requiredTier {
        case .free:
            return true
        case .plus:
            return userTier != .free
        case .pro:
            return userTier == .pro || userTier == .internal
        }
    }
}
