//
//  AIChatURLParameters.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public enum AIChatURLParameters {
    /// Prompt text passed to Duck.ai.
    public static let promptQueryName = "q"
    /// Flag indicating the prompt should be auto-submitted.
    public static let autoSubmitPromptQueryName = "prompt"
    /// Value used with `autoSubmitPromptQueryName` for auto-submit.
    public static let autoSubmitPromptQueryValue = "1"
    /// Repeating parameter for selecting one or more RAG tools.
    public static let toolChoiceName = "toolChoice"
    /// Flow selector key used for onboarding-specific Duck.ai behavior.
    public static let flowQueryName = "flow"
    /// Flow selector value for mobile app onboarding.
    public static let mobileAppOnboardingFlowQueryValue = "mobile-app-onboarding"

    public static let modeName = "mode"
    public static let voiceModeValue = "voice"
    public static let imageModeValue = "image"

    /// Appends `?mode=voice` to the given base URL.
    public static func voiceModeURL(from baseURL: URL) -> URL {
        modeURL(from: baseURL, mode: voiceModeValue)
    }

    /// Appends `?mode=image` to the given base URL.
    public static func imageModeURL(from baseURL: URL) -> URL {
        modeURL(from: baseURL, mode: imageModeValue)
    }

    private static func modeURL(from baseURL: URL, mode: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == modeName }
        queryItems.append(URLQueryItem(name: modeName, value: mode))
        components.queryItems = queryItems
        return components.url ?? baseURL
    }
}

/// Allowed onboarding flow types passed through Duck.ai URL query params.
public enum AIChatOnboardingFlowType {
    /// Default behavior: no explicit onboarding flow parameter is sent.
    case `default`
    /// Uses the mobile-app-onboarding Duck.ai flow.
    case mobileAppOnboarding

    /// Serialized `flow` query value (if any) used by onboarding-specific FE behavior.
    public var flowQueryValue: String? {
        switch self {
        case .default:
            return nil
        case .mobileAppOnboarding:
            return AIChatURLParameters.mobileAppOnboardingFlowQueryValue
        }
    }
}
