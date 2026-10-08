//
//  DuckAiTermsOfServicePixel.swift
//  DuckDuckGo
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

import AIChat
import os.log
import PixelKit

/// The Duck.ai Terms of Service disclaimer's pixels, for users who haven't accepted. Whether the session
/// showed the disclaimer is in the name, so each group is one series.
enum DuckAiTermsOfServicePixel: PixelKit.Event {

    private enum Parameter {
        static let surface = "surface"
        static let sendMethod = "send_method"
        static let source = "source"
        static let nativeDisclaimer = "native_disclaimer"
    }

    case shown(surface: UnifiedToggleInputPixelSurface)
    case shownPromptSubmitted(surface: UnifiedToggleInputPixelSurface, sendMethod: DuckAiTermsOfServiceSendMethod)
    case shownAbandoned(surface: UnifiedToggleInputPixelSurface)
    case notShown(surface: UnifiedToggleInputPixelSurface)
    case notShownPromptSubmitted(surface: UnifiedToggleInputPixelSurface, sendMethod: DuckAiTermsOfServiceSendMethod)
    case notShownAbandoned(surface: UnifiedToggleInputPixelSurface)
    case linkTapped(surface: UnifiedToggleInputPixelSurface)
    /// A web acceptance has no native surface.
    case accepted(surface: UnifiedToggleInputPixelSurface?, source: DuckAiTermsOfServiceAcceptanceSource, isNativeDisclaimerEnabled: Bool)

    init?(event: DuckAiTermsOfServiceMeasurementEvent, surface: UnifiedToggleInputPixelSurface?) {
        if case .accepted(let source, let isNativeDisclaimerEnabled) = event {
            self = .accepted(surface: surface, source: source, isNativeDisclaimerEnabled: isNativeDisclaimerEnabled)
            return
        }
        guard let surface else { return nil }
        switch event {
        case .sessionStarted(.shown): self = .shown(surface: surface)
        case .sessionStarted(.notShown): self = .notShown(surface: surface)
        case .promptSubmitted(.shown, let sendMethod): self = .shownPromptSubmitted(surface: surface, sendMethod: sendMethod)
        case .promptSubmitted(.notShown, let sendMethod): self = .notShownPromptSubmitted(surface: surface, sendMethod: sendMethod)
        case .abandoned(.shown): self = .shownAbandoned(surface: surface)
        case .abandoned(.notShown): self = .notShownAbandoned(surface: surface)
        case .linkTapped: self = .linkTapped(surface: surface)
        case .accepted: return nil
        }
    }

    var name: String {
        switch self {
        case .shown: return "aichat_terms_of_service_shown"
        case .shownPromptSubmitted: return "aichat_terms_of_service_shown_prompt_submitted"
        case .shownAbandoned: return "aichat_terms_of_service_shown_abandoned"
        case .notShown: return "aichat_terms_of_service_not_shown"
        case .notShownPromptSubmitted: return "aichat_terms_of_service_not_shown_prompt_submitted"
        case .notShownAbandoned: return "aichat_terms_of_service_not_shown_abandoned"
        case .linkTapped: return "aichat_terms_of_service_link_tapped"
        case .accepted: return "aichat_terms_of_service_accepted"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .shown(let surface), .shownAbandoned(let surface),
             .notShown(let surface), .notShownAbandoned(let surface),
             .linkTapped(let surface):
            return [Parameter.surface: surface.rawValue]
        case .shownPromptSubmitted(let surface, let sendMethod), .notShownPromptSubmitted(let surface, let sendMethod):
            return [Parameter.surface: surface.rawValue, Parameter.sendMethod: sendMethod.rawValue]
        case .accepted(let surface, let source, let isNativeDisclaimerEnabled):
            var parameters = [Parameter.source: source.rawValue,
                              Parameter.nativeDisclaimer: isNativeDisclaimerEnabled ? "enabled" : "disabled"]
            parameters[Parameter.surface] = surface?.rawValue
            return parameters
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

// MARK: - Adapter

/// Fires the shared measurement's events as this app's pixels. The surface is read per fire, since one
/// UTI coordinator serves the address bar, the Duck.ai tab and the contextual sheet.
struct DuckAiTermsOfServicePixelAdapter: DuckAiTermsOfServicePixelFiring {

    private let firing: UTIPixelFiring
    private let surface: () -> UnifiedToggleInputPixelSurface?

    init(firing: UTIPixelFiring = .live, surface: @escaping () -> UnifiedToggleInputPixelSurface?) {
        self.firing = firing
        self.surface = surface
    }

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        guard let pixel = DuckAiTermsOfServicePixel(event: event, surface: surface()) else { return }
        Logger.aiChat.debug("[TermsOfService] pixel \(pixel.name, privacy: .public) \(String(describing: pixel.parameters), privacy: .public)")
        firing.fire(pixel, frequency: .dailyAndCount)
    }
}

extension DuckAiTermsOfServiceSendMethod {

    init(trigger: TextSubmissionTrigger) {
        switch trigger {
        case .sendButton: self = .ask
        case .textEntry: self = .return
        case .programmatic: self = .quickAction
        }
    }

    init(sentWithAsk: Bool) {
        self = sentWithAsk ? .ask : .return
    }
}
