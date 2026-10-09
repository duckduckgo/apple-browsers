//
//  DuckAiTermsOfServiceMeasurement.swift
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

/// Which group an input session joined, for a user who hasn't accepted: the disclaimer rendered, or
/// the build doesn't show it. Each platform puts this in the pixel name.
public enum DuckAiTermsOfServiceSessionGroup: Equatable {
    case shown
    case notShown
}

/// How the session's first prompt was sent. The disclaimer changes which of these are possible.
public enum DuckAiTermsOfServiceSendMethod: String, Equatable {
    case ask
    case `return`
    case voice
    case quickAction = "quick_action"
}

/// Where the user first accepted Duck.ai's Terms of Service.
public enum DuckAiTermsOfServiceAcceptanceSource: String, Equatable {
    case nativeInput = "native_input"
    case web
}

public enum DuckAiTermsOfServiceMeasurementEvent: Equatable {
    case sessionStarted(DuckAiTermsOfServiceSessionGroup)
    case promptSubmitted(DuckAiTermsOfServiceSessionGroup, DuckAiTermsOfServiceSendMethod)
    case abandoned(DuckAiTermsOfServiceSessionGroup)
    case linkTapped
    case accepted(DuckAiTermsOfServiceAcceptanceSource, isNativeDisclaimerEnabled: Bool)
}

public extension DuckAiTermsOfServiceMeasurementEvent {

    /// The same on every platform; macOS appends `_macos`.
    var pixelName: String {
        switch self {
        case .sessionStarted(.shown): return "aichat_terms_of_service_shown"
        case .sessionStarted(.notShown): return "aichat_terms_of_service_not_shown"
        case .promptSubmitted(.shown, _): return "aichat_terms_of_service_shown_prompt_submitted"
        case .promptSubmitted(.notShown, _): return "aichat_terms_of_service_not_shown_prompt_submitted"
        case .abandoned(.shown): return "aichat_terms_of_service_shown_abandoned"
        case .abandoned(.notShown): return "aichat_terms_of_service_not_shown_abandoned"
        case .linkTapped: return "aichat_terms_of_service_link_tapped"
        case .accepted: return "aichat_terms_of_service_accepted"
        }
    }

    /// `surface` is the native input, which the web's acceptance doesn't have.
    func pixelParameters(surface: String?) -> [String: String] {
        var parameters: [String: String] = [:]
        parameters["surface"] = surface
        switch self {
        case .promptSubmitted(_, let sendMethod):
            parameters["send_method"] = sendMethod.rawValue
        case .accepted(let source, let isNativeDisclaimerEnabled):
            parameters["source"] = source.rawValue
            parameters["native_disclaimer"] = isNativeDisclaimerEnabled ? "enabled" : "disabled"
        case .sessionStarted, .abandoned, .linkTapped:
            break
        }
        return parameters
    }
}

public protocol DuckAiTermsOfServicePixelFiring {
    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent)
}

public struct NullDuckAiTermsOfServicePixelFiring: DuckAiTermsOfServicePixelFiring {
    public init() {}
    public func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {}
}

/// Whether seeing the disclaimer changes if a user who hasn't accepted sends a prompt or bounces.
/// One native input session reports one group, and then one outcome: its first prompt, or abandoned.
public final class DuckAiTermsOfServiceMeasurement {

    private struct Session {
        var group: DuckAiTermsOfServiceSessionGroup?
        var didReportPrompt = false
    }

    private let pixelFiring: DuckAiTermsOfServicePixelFiring
    private var session: Session?

    public init(pixelFiring: DuckAiTermsOfServicePixelFiring = NullDuckAiTermsOfServicePixelFiring()) {
        self.pixelFiring = pixelFiring
    }

    /// The input opened in Duck.ai mode. Only a user who hasn't accepted qualifies, and without the disclaimer
    /// only while nothing blocks sending, since the disclaimer never shows over a block. Ignored mid-session.
    public func inputSessionStarted(hasAccepted: Bool, isDisclaimerEnabled: Bool, isInputBlocked: Bool) {
        guard session == nil, !hasAccepted else { return }
        guard !isDisclaimerEnabled else {
            // Joins `shown` once the disclaimer renders, which a block can delay or prevent.
            session = Session()
            return
        }
        guard !isInputBlocked else { return }
        session = Session(group: .notShown)
        pixelFiring.fire(.sessionStarted(.notShown))
    }

    /// The disclaimer is on screen, not just resolved.
    public func disclaimerBecameVisible() {
        guard var session, session.group == nil else { return }
        session.group = .shown
        self.session = session
        pixelFiring.fire(.sessionStarted(.shown))
    }

    public func promptSubmitted(_ sendMethod: DuckAiTermsOfServiceSendMethod) {
        guard var session, let group = session.group, !session.didReportPrompt else { return }
        session.didReportPrompt = true
        self.session = session
        pixelFiring.fire(.promptSubmitted(group, sendMethod))
    }

    /// The input closed, collapsed, left Duck.ai mode or went to the background.
    public func inputSessionEnded() {
        guard let session else { return }
        self.session = nil
        guard let group = session.group, !session.didReportPrompt else { return }
        pixelFiring.fire(.abandoned(group))
    }

    public func linkTapped() {
        pixelFiring.fire(.linkTapped)
    }

    /// Only an input showing the disclaimer can record an acceptance.
    public func acceptedInNativeInput() {
        pixelFiring.fire(.accepted(.nativeInput, isNativeDisclaimerEnabled: true))
    }
}
