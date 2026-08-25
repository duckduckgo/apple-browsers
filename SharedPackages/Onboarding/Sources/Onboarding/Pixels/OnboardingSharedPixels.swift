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
        case tailoredByDownloadReason = "tailored_by_download_reason"
    }

    /// Pixel parameter for the variant of the onboarding flow the user enters after a branching step during onboarding.
    public enum Variant: String {
        case duckAISearch = "search_plus_duckai-search"
        case duckAIChat = "search_plus_duckai-chat"
        // Records the download reason the user selected, passed to every pixel after the choice for internal cohort segmentation.
        case downloadReasonSearch = "download_reason_search"
        case downloadReasonAIChat = "download_reason_ai-chat"
        case downloadReasonNoAI = "download_reason_no-ai"
        case downloadReasonAdBlocking = "download_reason_ad-blocking"
    }
}

public extension OnboardingPixelParameter.Variant {
    /// Maps the domain download reason to its pixel variant, so the selected reason can be
    /// recorded on the segmented-onboarding pixels for cohort segmentation.
    init(_ reason: OnboardingDownloadReason) {
        switch reason {
        case .browserPrivately: self = .downloadReasonSearch
        case .privateAIChat:    self = .downloadReasonAIChat
        case .noAI:             self = .downloadReasonNoAI
        case .blockAds:         self = .downloadReasonAdBlocking
        }
    }
}

final public class OnboardingSharedPixelHandler: OnboardingSharedPixelHandling {
    private struct ParameterKeys {
        static let installType = "installType"
        static let daysSinceInstall = "daysSinceInstall"
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

        if let daysSinceInstall,
           let bucket = Self.daysSinceInstallBucket(for: daysSinceInstall) {
            additionalParameters[ParameterKeys.daysSinceInstall] = bucket
        }

        return additionalParameters
    }

    private static func daysSinceInstallBucket(for days: Int) -> String? {
        switch days {
        case 0:
            return "0"
        case 1...3:
            return "1-3"
        case 4...10:
            return "4-10"
        case 11...28:
            return "11-28"
        case 29...:
            return "28+"
        default:
            return nil
        }
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
                          options: .parameters(additionalParameters, namePrefix: platform.pixelPrefix))
    }

}

public enum OnboardingSharedPixelEvent: PixelKit.Event, Equatable {
    /// Frozen: these names ship without a platform marker.
    public var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyOmitted }

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
    case endTryDuckAI(EngagementEvent) // iOS only — the Try Duck.ai end-of-journey dialog
    case subscriptionPromo(EngagementEvent) // iOS only

    // Segmented onboarding (download-reason) events — iOS only
    case downloadChoice(DownloadChoiceEvent)
    case preferencesSerp(SerpEngagementEvent)
    case preferencesAIModel(AIModelEvent)
    case preferencesAIToggleMode(AIToggleModeEvent)
    case preferencesAISearch(AISearchEngagementEvent)
    case preferencesDuckAI(DuckAIEvent)
    case preferencesAdBlocking(AdBlockingEngagementEvent)

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

    /// The download-reason selection screen. `Value` records the reason the user chose.
    public enum DownloadChoiceEvent: Equatable {
        public enum Value: String {
            case search
            case aiChat = "ai-chat"
            case noAI = "no-ai"
            case adBlocking = "ad-blocking"
        }

        case shown
        case clicked(Value)
    }

    /// The SERP preferences screen.
    public enum SerpEngagementEvent: Equatable {
        case shown
        case clicked(recentlyVisitedSitesEnabled: Bool, safeSearchEnabled: Bool)
    }

    /// The AI search settings screen.
    public enum AISearchEngagementEvent: Equatable {
        case shown
        case clicked(searchAssistEnabled: Bool, aiGeneratedImagesEnabled: Bool)
    }

    /// The ad-blocking & cookie preferences screen ("Internet, without the noise").
    public enum AdBlockingEngagementEvent: Equatable {
        case shown
        case clicked(youTubeAdBlockingEnabled: Bool, cookiePopUpProtectionEnabled: Bool, popUpsWithoutOptOutsEnabled: Bool)
    }

    /// The AI model picker. The selected model as a coarse label (e.g. "claude", "chatgpt")
    public enum AIModelEvent: Equatable {
        case shown
        case clicked(model: String)
    }

    /// The Search/AI address-bar toggle-mode screen.
    public enum AIToggleModeEvent: Equatable {
        case shown
        case clicked(openNewTabsWithAIChat: Bool)
    }

    /// The "Keep Duck.ai on / Turn Duck.ai off" screen.
    public enum DuckAIEvent: Equatable {
        public enum Value: String {
            case on
            case off
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
            "event": eventType
        ]

        if let value {
            parameters["value"] = value
        }

        parameters.merge(extraParameters) { _, new in new }

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
        case .endTryDuckAI: return "end-try-duckai"
        case .subscriptionPromo: return "subscription-promo"
        case .downloadChoice: return "download-choice"
        case .preferencesSerp: return "preferences_serp"
        case .preferencesAIModel: return "preferences_ai-model"
        case .preferencesAIToggleMode: return "preferences_ai-toggle-mode"
        case .preferencesAISearch: return "preferences_ai-search"
        case .preferencesDuckAI: return "preferences_duck-ai"
        case .preferencesAdBlocking: return "preferences_ad-blocking"
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
                .endTryDuckAI(let event),
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
        case .downloadChoice(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesSerp(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesAISearch(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesAdBlocking(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesAIModel(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesAIToggleMode(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            }
        case .preferencesDuckAI(let event):
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
                .endTryDuckAI(let event),
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
        case .downloadChoice(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        case .preferencesSerp(let event):
            switch event {
            case .shown, .clicked:
                // Toggle states are emitted via `extraParameters`, not as `value`.
                return nil
            }
        case .preferencesAISearch(let event):
            switch event {
            case .shown, .clicked:
                return nil
            }
        case .preferencesAdBlocking(let event):
            switch event {
            case .shown, .clicked:
                return nil
            }
        case .preferencesAIModel(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let model):
                return model
            }
        case .preferencesAIToggleMode(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let openNewTabsWithAIChat):
                return String(openNewTabsWithAIChat)
            }
        case .preferencesDuckAI(let event):
            switch event {
            case .shown:
                return nil
            case .clicked(let value):
                return value.rawValue
            }
        }
    }

    // Screen-specific toggle states emitted as their own pixel parameters (in addition to `event`/`value`).
    var extraParameters: [String: String] {
        switch self {
        case .preferencesSerp(.clicked(let recentlyVisitedSitesEnabled, let safeSearchEnabled)):
            return [
                "recently_visited_sites_enabled": String(recentlyVisitedSitesEnabled),
                "safe_search_enabled": String(safeSearchEnabled)
            ]
        case .preferencesAISearch(.clicked(let searchAssistEnabled, let aiGeneratedImagesEnabled)):
            return [
                "search_assist_enabled": String(searchAssistEnabled),
                "ai_generated_images_enabled": String(aiGeneratedImagesEnabled)
            ]
        case .preferencesAdBlocking(.clicked(let youTubeAdBlockingEnabled, let cookiePopUpProtectionEnabled, let popUpsWithoutOptOutsEnabled)):
            return [
                "youtube_ad_blocking_enabled": String(youTubeAdBlockingEnabled),
                "cookie_popup_protection_enabled": String(cookiePopUpProtectionEnabled),
                "popups_without_optouts_enabled": String(popUpsWithoutOptOutsEnabled)
            ]
        default:
            return [:]
        }
    }
}
