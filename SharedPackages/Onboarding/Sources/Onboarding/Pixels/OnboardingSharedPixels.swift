//
//  OnboardingSharedPixels.swift
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

import Common
import FoundationExtensions
import Foundation
import PixelKit

public protocol OnboardingSharedPixelHandling {
    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?,
              variant: OnboardingPixelParameter.Variant?)
}

public extension OnboardingSharedPixelHandling {
    #if os(macOS)
    /// Fires the provided shared onboarding pixel event with nil source and flow parameters.
    /// For use on macOS only, which has no non-default onboarding sources, flows, or variants.
    func fire(_ event: OnboardingSharedPixelEvent) {
        fire(event, source: nil, flow: nil, variant: nil)
    }
    #endif

    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?) {
        fire(event, source: source, flow: flow, variant: nil)
    }
}

public enum OnboardingPixelParameter {
    /// Pixel parameter for the entry point into the onboarding flow.
    public enum Source: String {
        case `default` = "default"
        case duckAICustomProductPage = "duckai_cpp"
    }

    /// Pixel parameter for the type of onboarding flow the user started.
    public enum Flow: String {
        case `default` = "default"
        case duckAI = "duckai"
    }

    /// Pixel parameter for the variant of the onboarding flow the user enters after a branching step during onboarding.
    public enum Variant: String {
        case duckAISearch = "search_plus_duckai-search"
        case duckAIChat = "search_plus_duckai-chat"
    }
}

final public class OnboardingSharedPixelHandler: OnboardingSharedPixelHandling {
    private struct ParameterKeys {
        static let installType = "it"
        static let daysSinceInstall = "d"
        static let source = "source"
        static let flow = "flow"
        static let variant = "variant"
    }

    public enum InstallType: String {
        case newInstall = "new"
        case reinstall
    }

    public enum Platform: String {
        case iOS
        case macOS

        var pixelPrefix: String {
            switch self {
            case .iOS:
                return "m_ios_"
            case .macOS:
                return "m_mac_"
            }
        }
    }

    private let platform: Platform
    private let installTypeProvider: () -> InstallType?
    private let installDateProvider: () -> Date?
    private let currentDateProvider: () -> Date
    private let pixelFiring: PixelFiring?

    private var daysSinceInstall: Int? {
        guard let installDate = installDateProvider() else { return nil }
        return Calendar.current.numberOfDaysBetween(installDate, and: currentDateProvider())
    }

    private var installParameters: [String: String] {
        var additionalParameters: [String: String] = [:]

        if let installType = installTypeProvider() {
            additionalParameters[ParameterKeys.installType] = installType.rawValue
        }

        if let daysSinceInstall, (0...28).contains(daysSinceInstall) {
            additionalParameters[ParameterKeys.daysSinceInstall] = String(daysSinceInstall)
        }

        return additionalParameters
    }

    public init(platform: Platform,
                installTypeProvider: @escaping () -> InstallType?,
                installDateProvider: @escaping () -> Date?,
                currentDateProvider: @escaping () -> Date = { Date() },
                pixelFiring: PixelFiring? = PixelKit.shared) {
        self.platform = platform
        self.installTypeProvider = installTypeProvider
        self.installDateProvider = installDateProvider
        self.currentDateProvider = currentDateProvider
        self.pixelFiring = pixelFiring
    }

    public func fire(_ event: OnboardingSharedPixelEvent,
                     source: OnboardingPixelParameter.Source?,
                     flow: OnboardingPixelParameter.Flow?,
                     variant: OnboardingPixelParameter.Variant?) {
        var additionalParameters = installParameters
        if let source {
            additionalParameters[ParameterKeys.source] = source.rawValue
        }
        if let flow {
            additionalParameters[ParameterKeys.flow] = flow.rawValue
        }
        if let variant {
            additionalParameters[ParameterKeys.variant] = variant.rawValue
        }

        pixelFiring?.fire(event,
                          frequency: .uniqueByNameAndParameters,
                          withAdditionalParameters: additionalParameters,
                          withNamePrefix: platform.pixelPrefix)
    }

}

public enum OnboardingSharedPixelEvent: PixelKitEvent, Equatable {
    // Linear onboarding events
    case welcome(EngagementEvent)
    case skipOnboarding(EngagementEvent) // iOS only
    case setDefault(EngagementEvent)
    case aiIntro(EngagementEvent) // iOS only (AI Protections Activated!)
    case addToDock(EngagementEvent)
    case appIconColor(AppIconColorEvent) // iOS only
    case addressBarPosition(AddressBarPositionEvent) // iOS only
    case importData(EngagementEvent) // macOS only
    case chromeExtensionInstall(EngagementEvent) // macOS only
    case duckPlayer(EngagementEvent) // macOS only
    case customization(CustomizeEvent) // macOS only
    case searchExperience(SearchExperienceEvent)

    // Contextual onboarding events
    case search(SuggestedOrCustomEvent)
    case searchChatToggle(SuggestionOrCustomToggleEvent) // iOS only
    case searchResults(EngagementEvent)
    case visitSite(SuggestedOrCustomEvent)
    case trackersBlocked(EngagementEvent)
    case fireButton(EngagementEvent)
    case end(EngagementEvent)
    case subscriptionPromo(EngagementEvent) // iOS only

    public enum EngagementEvent: Equatable {
        public enum Value: String {
            case engage
            case dismiss
        }

        case shown
        case clicked(Value)
        case confirmed
    }

    public enum SearchExperienceEvent: Equatable {
        public enum Value: String {
            case searchOnly = "search_only"
            case searchPlusDuckAI = "search_plus_duckai"
        }

        case shown
        case clicked(Value)
    }

    public enum SuggestedOrCustomEvent: Equatable {
        public enum Value: String {
            case suggested
            case custom
            case dismiss
        }

        case shown
        case clicked(Value)
    }

    public enum SuggestionOrCustomToggleEvent: Equatable {
        public enum Value: String {
            case suggestedChat = "suggested_chat"
            case suggestedSearch = "suggested_search"
            case customChat = "custom_chat"
            case customSearch = "custom_search"
        }

        case shown
        case clicked(Value)
    }

    public enum CustomizeEvent: Equatable {
        public enum Value: String {
            case bookmarksBar = "bookmarks_bar"
            case restoreSession = "restore_session"
            case homeButton = "home_button"
        }

        case shown
        case clicked([Value])
    }

    /// Matches alternate app icon colors (`AppIcon`) in the iOS app.
    public enum AppIconColorEvent: Equatable {
        public enum Value: String {
            case red
            case pink
            case yellow
            case green
            case blue
            case purple
            case black
            case white
        }

        case shown
        case clicked(Value)
    }

    public enum AddressBarPositionEvent: Equatable {
        public enum Value: String {
            case top
            case bottom
        }

        case shown
        case clicked(Value)
    }
}

public extension OnboardingSharedPixelEvent {
    var name: String {
        "onboarding_\(stepName)"
    }

    var parameters: [String: String]? {
        var parameters = [
            "e": eventType
        ]

        if let value {
            parameters["value"] = value
        }

        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    var error: NSError? {
        nil
    }
}

private extension OnboardingSharedPixelEvent {
    var stepName: String {
        switch self {
        case .welcome: return "welcome"
        case .skipOnboarding: return "skip-onboarding"
        case .setDefault: return "set-default"
        case .aiIntro: return "ai-intro"
        case .addToDock: return "add-to-dock"
        case .appIconColor: return "app-icon-color"
        case .addressBarPosition: return "address-bar-position"
        case .importData: return "import-data"
        case .chromeExtensionInstall: return "chrome-extension-install"
        case .duckPlayer: return "duck-player"
        case .customization: return "customization"
        case .searchExperience: return "search-experience"
        case .search: return "search"
        case .searchChatToggle: return "search-chat-toggle"
        case .searchResults: return "search-results"
        case .visitSite: return "visit-site"
        case .trackersBlocked: return "trackers-blocked"
        case .fireButton: return "fire-button"
        case .end: return "end"
        case .subscriptionPromo: return "subscription-promo"
        }
    }

    private struct ParameterValues {
        static let shown = "shown"
        static let clicked = "clicked"
        static let dismiss = "dismiss"
        static let confirmed = "confirmed"
    }

    var eventType: String {
        switch self {
        case .welcome(let event),
                .setDefault(let event),
                .aiIntro(let event),
                .addToDock(let event),
                .importData(let event),
                .chromeExtensionInstall(let event),
                .duckPlayer(let event),
                .skipOnboarding(let event),
                .searchResults(let event),
                .trackersBlocked(let event),
                .fireButton(let event),
                .end(let event),
                .subscriptionPromo(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            case .confirmed:
                return ParameterValues.confirmed
            }
        case .appIconColor(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .addressBarPosition(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .searchExperience(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .search(let event),
                .visitSite(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .customization(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .searchChatToggle(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        }
    }

    var value: String? {
        switch self {
        case .welcome(let event),
                .setDefault(let event),
                .aiIntro(let event),
                .addToDock(let event),
                .importData(let event),
                .chromeExtensionInstall(let event),
                .duckPlayer(let event),
                .skipOnboarding(let event),
                .searchResults(let event),
                .trackersBlocked(let event),
                .fireButton(let event),
                .end(let event),
                .subscriptionPromo(let event):
            switch event {
            case .shown, .confirmed:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .appIconColor(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .addressBarPosition(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .searchExperience(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .search(let event),
                .visitSite(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .customization(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                if value.isEmpty {
                    return ParameterValues.dismiss
                } else {
                    return value.map { $0.rawValue }.joined(separator: ",")
                }
            }
        case .searchChatToggle(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        }
    }
}
