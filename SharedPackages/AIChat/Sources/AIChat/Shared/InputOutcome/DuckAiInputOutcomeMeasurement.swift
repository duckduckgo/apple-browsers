//
//  DuckAiInputOutcomeMeasurement.swift
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

public enum DuckAiInputSurface: String, Equatable {
    case addressBar = "address_bar"
    case duckAI = "duck_ai"
    case contextualChat = "contextual_chat"
    case promptBar = "promptbar"
}

public enum DuckAiInputSubmitMethod: String, Equatable {
    case button
    /// Return. iPhone and iPad don't send on Return while the disclaimer shows.
    case enter
    /// Quick actions, Paste & Go and dictation.
    case other
}

public enum DuckAiInputOutcome: Equatable {
    case promptSubmitted(DuckAiInputSubmitMethod)
    /// A suggested prompt tapped in the contextual sheet.
    case suggestedPrompt
    case voiceStarted
    case abandoned
}

/// What one opening of a Duck.ai input led to, as `aichat_input_outcome` on every platform.
public struct DuckAiInputOutcomeEvent: Equatable {

    public static let pixelName = "aichat_input_outcome"

    public let surface: DuckAiInputSurface
    public let isTermsOfServiceDisclaimerShown: Bool
    public let outcome: DuckAiInputOutcome

    public init(surface: DuckAiInputSurface,
                isTermsOfServiceDisclaimerShown: Bool,
                outcome: DuckAiInputOutcome) {
        self.surface = surface
        self.isTermsOfServiceDisclaimerShown = isTermsOfServiceDisclaimerShown
        self.outcome = outcome
    }

    public var parameters: [String: String] {
        var parameters = [
            "surface": surface.rawValue,
            "tos_disclaimer_shown": String(isTermsOfServiceDisclaimerShown)
        ]
        switch outcome {
        case .promptSubmitted(let submitMethod):
            parameters["outcome"] = "prompt_submitted"
            parameters["submit_method"] = submitMethod.rawValue
        case .suggestedPrompt:
            parameters["outcome"] = "suggested_prompt"
        case .voiceStarted:
            parameters["outcome"] = "voice_started"
        case .abandoned:
            parameters["outcome"] = "abandoned"
        }
        return parameters
    }
}

public protocol DuckAiInputOutcomePixelFiring {
    func fire(_ event: DuckAiInputOutcomeEvent)
}

/// Whether people send a prompt or leave while the Duck.ai Terms of Service disclaimer shows.
/// Each opening of the input reports once: its first outcome, or `abandoned` when it closes without one.
public final class DuckAiInputOutcomeMeasurement {

    private struct OpenInput {
        let surface: DuckAiInputSurface
        var isTermsOfServiceDisclaimerShown: Bool
        var hasReported = false
    }

    private let pixelFiring: DuckAiInputOutcomePixelFiring
    private var openInput: OpenInput?

    public init(pixelFiring: DuckAiInputOutcomePixelFiring) {
        self.pixelFiring = pixelFiring
    }

    /// Ignored while the input is already open, so callers can re-sync on every state change.
    public func inputOpened(surface: DuckAiInputSurface, isTermsOfServiceDisclaimerShown: Bool) {
        guard openInput == nil else { return }
        openInput = OpenInput(surface: surface, isTermsOfServiceDisclaimerShown: isTermsOfServiceDisclaimerShown)
    }

    /// The disclaimer is on screen, not just resolved.
    public func termsOfServiceDisclaimerBecameVisible() {
        openInput?.isTermsOfServiceDisclaimerShown = true
    }

    /// The input closed, collapsed, left Duck.ai mode or went to the background.
    public func inputClosed() {
        guard let openInput else { return }
        self.openInput = nil
        guard !openInput.hasReported else { return }
        fire(openInput, outcome: .abandoned)
    }

    /// Only the first outcome counts; `abandoned` comes from `inputClosed()`.
    public func record(_ outcome: DuckAiInputOutcome) {
        guard var openInput, !openInput.hasReported else { return }
        openInput.hasReported = true
        self.openInput = openInput
        fire(openInput, outcome: outcome)
    }

    private func fire(_ openInput: OpenInput, outcome: DuckAiInputOutcome) {
        pixelFiring.fire(DuckAiInputOutcomeEvent(surface: openInput.surface,
                                                 isTermsOfServiceDisclaimerShown: openInput.isTermsOfServiceDisclaimerShown,
                                                 outcome: outcome))
    }
}
