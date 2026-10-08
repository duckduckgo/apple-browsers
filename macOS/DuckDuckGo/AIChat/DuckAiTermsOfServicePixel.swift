//
//  DuckAiTermsOfServicePixel.swift
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

/// The Duck.ai Terms of Service disclaimer's pixels, for users who haven't accepted, name-for-name with iOS.
/// Whether the session showed the disclaimer is in the name, so each group is one series.
enum DuckAiTermsOfServicePixel: PixelKit.Event {

    private enum Parameter {
        static let surface = "surface"
        static let sendMethod = "send_method"
        static let source = "source"
        static let nativeDisclaimer = "native_disclaimer"
    }

    case shown(surface: DuckAiUsageWarningPixelSurface)
    case shownPromptSubmitted(surface: DuckAiUsageWarningPixelSurface, sendMethod: DuckAiTermsOfServiceSendMethod)
    case shownAbandoned(surface: DuckAiUsageWarningPixelSurface)
    case notShown(surface: DuckAiUsageWarningPixelSurface)
    case notShownPromptSubmitted(surface: DuckAiUsageWarningPixelSurface, sendMethod: DuckAiTermsOfServiceSendMethod)
    case notShownAbandoned(surface: DuckAiUsageWarningPixelSurface)
    case linkTapped(surface: DuckAiUsageWarningPixelSurface)
    /// A web acceptance has no native surface.
    case accepted(surface: DuckAiUsageWarningPixelSurface?, source: DuckAiTermsOfServiceAcceptanceSource, isNativeDisclaimerEnabled: Bool)

    init?(event: DuckAiTermsOfServiceMeasurementEvent, surface: DuckAiUsageWarningPixelSurface?) {
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

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .shown: return "aichat_terms_of_service_shown_macos"
        case .shownPromptSubmitted: return "aichat_terms_of_service_shown_prompt_submitted_macos"
        case .shownAbandoned: return "aichat_terms_of_service_shown_abandoned_macos"
        case .notShown: return "aichat_terms_of_service_not_shown_macos"
        case .notShownPromptSubmitted: return "aichat_terms_of_service_not_shown_prompt_submitted_macos"
        case .notShownAbandoned: return "aichat_terms_of_service_not_shown_abandoned_macos"
        case .linkTapped: return "aichat_terms_of_service_link_tapped_macos"
        case .accepted: return "aichat_terms_of_service_accepted_macos"
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

/// Fires the shared measurement's events as this app's pixels. One container VC serves the address bar
/// and the Prompt Bar, so the surface comes from the one it was built for; `nil` for the web's acceptance.
struct DuckAiTermsOfServicePixelAdapter: DuckAiTermsOfServicePixelFiring {

    private let surface: DuckAiUsageWarningPixelSurface?
    private let pixelFiring: PixelFiring?

    init(surface: DuckAiUsageWarningPixelSurface?, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.surface = surface
        self.pixelFiring = pixelFiring
    }

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        guard let pixel = DuckAiTermsOfServicePixel(event: event, surface: surface) else { return }

        Logger.aiChat.debug("[TermsOfService] pixel \(pixel.name, privacy: .public)")
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }
}
