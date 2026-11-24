//
//  DuckAINewChatModelSource.swift
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

/// Where the model of a new chat's first prompt came from. Raw values match the `model_source` pixel parameter.
public enum DuckAINewChatModelSource: String, CaseIterable, Sendable {
    case `default`
    case picked
    case onboarding
    case fallback
    case userDefault = "user_default"
    case userDefaultUnavailable = "user_default_unavailable"

    public static let pixelParameterKey = "model_source"

    /// Ending on the default model and effort counts as the default even after picking something else in between.
    /// `nil` when nothing was picked and the default isn't known yet.
    public static func resolve(sentModelId: String,
                               sendsDefaultEffort: Bool,
                               isPicked: Bool,
                               onboardingModelId: String? = nil,
                               newChatDefault: AIChatNewChatSelection?) -> DuckAINewChatModelSource? {
        if sentModelId == onboardingModelId { return .onboarding }
        if let newChatDefault, newChatDefault.modelId == sentModelId, sendsDefaultEffort {
            switch newChatDefault.origin {
            case .user: return .userDefault
            case .userDefaultUnavailable: return .userDefaultUnavailable
            case .server: return .default
            case .fallback: return .fallback
            }
        }
        if isPicked { return .picked }
        return newChatDefault == nil ? nil : .fallback
    }
}
