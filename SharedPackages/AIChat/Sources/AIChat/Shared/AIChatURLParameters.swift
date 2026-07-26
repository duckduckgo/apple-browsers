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
    /// Flag indicating the host app renders the chat input natively.
    public static let nativeInputName = "native-input"
    /// Value used with `nativeInputName` when native input is enabled.
    public static let nativeInputValue = "true"
    /// Flow selector key used for onboarding-specific Duck.ai behavior.
    public static let flowQueryName = "flow"
    /// Flow selector value for mobile app onboarding.
    public static let mobileAppOnboardingFlowQueryValue = "mobile-app-onboarding"

    public static let modeName = "mode"
    public static let voiceModeValue = "voice"
    public static let imageModeValue = "image"

    public static let sidebarName = "sidebar"
    public static let sidebarOpenValue = "open"

    public static let settingsName = "settings"
    public static let settingsOpenValue = "open"

    public static let feedbackName = "feedback"
    public static let feedbackPositiveValue = "positive"
    public static let feedbackNegativeValue = "negative"

    public static let chatProtectionName = "chatProtection"
    public static let chatProtectionOpenValue = "open"

    /// Tells the Duck.ai FE to render only the Customize Responses card.
    public static let customizeResponsesName = "customize-responses"
    public static let customizeResponsesValue = "full"

    /// Appends `?mode=voice` to the given base URL.
    public static func voiceModeURL(from baseURL: URL) -> URL {
        modeURL(from: baseURL, mode: voiceModeValue)
    }

    /// Appends `?mode=image` to the given base URL.
    public static func imageModeURL(from baseURL: URL) -> URL {
        modeURL(from: baseURL, mode: imageModeValue)
    }

    /// Appends `?sidebar=open` to the given base URL.
    public static func sidebarOpenURL(from baseURL: URL) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: sidebarName, value: sidebarOpenValue))
    }

    /// Appends `?settings=open` to the given base URL.
    public static func settingsOpenURL(from baseURL: URL) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: settingsName, value: settingsOpenValue))
    }

    /// Appends `?feedback=positive` / `?feedback=negative` to the given base URL.
    public static func feedbackURL(from baseURL: URL, value: String) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: feedbackName, value: value))
    }

    /// Appends `?chatProtection=open` to the given base URL.
    public static func chatProtectionURL(from baseURL: URL) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: chatProtectionName, value: chatProtectionOpenValue))
    }

    /// Appends `?customize-responses=full` to the given base URL.
    public static func nativeCustomizeModalURL(from baseURL: URL) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: customizeResponsesName, value: customizeResponsesValue))
    }

    /// Appends `?native-input=true` to the given base URL.
    public static func nativeInputURL(from baseURL: URL) -> URL {
        baseURL.addingOrReplacing(URLQueryItem(name: nativeInputName, value: nativeInputValue))
    }

    /// Removes `native-input` from the given base URL.
    public static func removingNativeInputURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == nativeInputName }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url ?? baseURL
    }

    /// Adds or removes `native-input` for URLs that support the native input contract.
    public static func updatingNativeInputURL(from baseURL: URL, isNativeInputAvailable: Bool, isSupportedURL: Bool) -> URL {
        guard isSupportedURL else { return baseURL }
        if isNativeInputAvailable {
            return nativeInputURL(from: baseURL)
        }
        return removingNativeInputURL(from: baseURL)
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
