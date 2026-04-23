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
import Foundation
import PixelKit

public protocol OnboardingSharedPixelHandling {
    func fire(_ event: OnboardingSharedPixelEvent)
}

final public class OnboardingSharedPixelHandler: OnboardingSharedPixelHandling {
    private struct ParameterKeys {
        static let installType = "it"
        static let daysSinceInstall = "d"
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

    let platform: Platform
    let installType: InstallType?
    let installDateProvider: () -> Date?
    let currentDateProvider: () -> Date
    let pixelFiring: PixelFiring?

    var daysSinceInstall: Int? {
        guard let installDate = installDateProvider() else { return nil }
        return Calendar.current.numberOfDaysBetween(installDate, and: currentDateProvider())
    }

    var installParameters: [String: String] {
        var additionalParameters: [String: String] = [:]

        if let installType {
            additionalParameters[ParameterKeys.installType] = installType.rawValue
        }

        if let daysSinceInstall, (0...28).contains(daysSinceInstall) {
            additionalParameters[ParameterKeys.daysSinceInstall] = String(daysSinceInstall)
        }

        return additionalParameters
    }

    public init(platform: Platform,
                installType: InstallType?,
                installDateProvider: @escaping () -> Date?,
                currentDateProvider: @escaping () -> Date = { Date() },
                pixelFiring: PixelFiring? = PixelKit.shared) {
        self.platform = platform
        self.installType = installType
        self.installDateProvider = installDateProvider
        self.currentDateProvider = currentDateProvider
        self.pixelFiring = pixelFiring
    }

    public func fire(_ event: OnboardingSharedPixelEvent) {

        pixelFiring?.fire(event,
                          frequency: .uniqueByNameAndParameters,
                          withAdditionalParameters: installParameters,
                          withNamePrefix: platform.pixelPrefix)
    }

}

public enum OnboardingSharedPixelEvent: PixelKitEvent, Equatable {
    // Linear onboarding events
    case welcome(EngagementEvent)
    case setDefault(EngagementEvent)
    case addToDock(EngagementEvent)
    case importData(EngagementEvent)
    case duckPlayer(EngagementEvent)
    case customization(CustomizeEvent)
    case searchExperience(SearchExperienceEvent)

    // Contextual onboarding events
    case search(SuggestedOrCustomEvent)
    case searchResults(EngagementEvent)
    case visitSite(SuggestedOrCustomEvent)
    case trackersBlocked(EngagementEvent)
    case fireButton(EngagementEvent)
    case end(EngagementEvent)

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

    public enum CustomizeEvent: Equatable {
        public enum Value: String {
            case bookmarksBar = "bookmarks_bar"
            case restoreSession = "restore_session"
            case homeButton = "home_button"
        }

        case shown
        case clicked([Value])
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
        switch self {
        case .addToDock:
            // Include pixel source for Add to Dock step, to measure engagement in macOS App Store vs DMG versions.
            // The DMG step adds the app to the Dock programmatically while the App Store step only shows instructions.
            return [.pixelSource]
        default:
            return nil
        }
    }

    var error: NSError? {
        nil
    }
}

private extension OnboardingSharedPixelEvent {
    var stepName: String {
        switch self {
        case .welcome: return "welcome"
        case .setDefault: return "set-default"
        case .addToDock: return "add-to-dock"
        case .importData: return "import-data"
        case .duckPlayer: return "duck-player"
        case .customization: return "customization"
        case .searchExperience: return "search-experience"
        case .search: return "search"
        case .searchResults: return "search-results"
        case .visitSite: return "visit-site"
        case .trackersBlocked: return "trackers-blocked"
        case .fireButton: return "fire-button"
        case .end: return "end"
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
                .addToDock(let event),
                .importData(let event),
                .duckPlayer(let event),
                .searchResults(let event),
                .trackersBlocked(let event),
                .fireButton(let event),
                .end(let event):
            switch event {
            case .shown:
                return ParameterValues.shown
            case .clicked:
                return ParameterValues.clicked
            case .confirmed:
                return ParameterValues.confirmed
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
        }
    }

    var value: String? {
        switch self {
        case .welcome(let event),
                .setDefault(let event),
                .addToDock(let event),
                .importData(let event),
                .duckPlayer(let event),
                .searchResults(let event),
                .trackersBlocked(let event),
                .fireButton(let event),
                .end(let event):
            switch event {
            case .shown, .confirmed:
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
        }
    }
}
