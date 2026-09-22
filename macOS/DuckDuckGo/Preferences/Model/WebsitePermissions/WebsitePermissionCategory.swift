//
//  WebsitePermissionCategory.swift
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

import FeatureFlags_macOS
import PrivacyConfig

enum WebsitePermissionCategory: CaseIterable, Hashable, Identifiable {
    case notifications
    case location
    case camera
    case microphone
    case externalApps
    case popups
    case autoplay

    var id: Self { self }

    var title: String {
        switch self {
        case .notifications:
            return UserText.permissionNotification
        case .location:
            return UserText.permissionGeolocation
        case .camera:
            return UserText.permissionCamera
        case .microphone:
            return UserText.permissionMicrophone
        case .externalApps:
            return UserText.permissionCenterExternalApps
        case .popups:
            return UserText.permissionPopups
        case .autoplay:
            return UserText.permissionAutoplay
        }
    }

    /// The category a permission belongs to, or `nil` for a type this pane has no section for.
    static func category(for permissionType: PermissionType) -> WebsitePermissionCategory? {
        allCases.first { $0.contains(permissionType) }
    }

    /// The categories the pane lists. Autoplay only appears while its feature flag is on, since
    /// nothing applies the saved decisions otherwise.
    static func visibleCases(featureFlagger: FeatureFlagger) -> [WebsitePermissionCategory] {
        allCases.filter { $0.isVisible(featureFlagger: featureFlagger) }
    }

    func isVisible(featureFlagger: FeatureFlagger) -> Bool {
        guard self == .autoplay else { return true }
        return featureFlagger.isFeatureOn(.autoplayPolicy)
    }

    /// Copy for one of this category's decisions.
    func decisionTitle(for decision: PersistedPermissionDecision) -> String {
        self == .autoplay ? decision.autoplayTitle : decision.websitePermissionsTitle
    }

    func contains(_ permissionType: PermissionType) -> Bool {
        switch (self, permissionType) {
        case (.notifications, .notification),
            (.location, .geolocation),
            (.camera, .camera),
            (.microphone, .microphone),
            (.externalApps, .externalScheme),
            (.popups, .popups),
            (.autoplay, .autoplayPolicy):
            return true
        default:
            return false
        }
    }
}
