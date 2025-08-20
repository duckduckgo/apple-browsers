//
//  TabContent+DisplayedFavicon.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import DesignResourcesKitIcons
import FeatureFlags
import MaliciousSiteProtection
import WebKit

extension TabContent {

    /// Returns the appropriate favicon for this tab content, considering errors, special URLs, and content types
    /// - Parameters:
    ///   - error: Optional error from the tab (for error state favicons)
    ///   - actualFavicon: The actual favicon loaded from the webpage (if any)
    ///   - isBurner: Whether this is a burner tab (affects newtab favicon)
    ///   - featureFlagger: Feature flag provider for checking enabled features
    ///   - visualStyle: Visual style provider for checking new/old style
    /// - Returns: The NSImage to display as the favicon, or nil if no favicon should be shown
    func displayedFavicon(
        error: Error? = nil,
        actualFavicon: NSImage? = nil,
        isBurner: Bool = false,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle
    ) -> NSImage? {

        // Handle error states first
        if let error {
            return Self.errorFavicon(for: error)
        }

        // Handle special content types and URLs
        switch self {
        case .dataBrokerProtection:
            return .personalInformationRemovalMulticolor16

        case .newtab where isBurner:
            return DesignSystemImages.Glyphs.Size16.fireTab

        case .newtab:
            return .homeFavicon

        case .settings:
            return .settingsMulticolor16

        case .bookmarks:
            return .bookmarksFolder

        case .history:
            return featureFlagger.isFeatureOn(.historyView) ? .historyFavicon : nil

        case .subscription:
            return .privacyPro

        case .identityTheftRestoration:
            return .identityTheftRestorationMulticolor16

        case .releaseNotes:
            return .homeFavicon

        case .aiChat:
            return .aiChatPreferences

        case .url(let url, _, _):
            // Handle special URL types
            if url.isHistory {
                return featureFlagger.isFeatureOn(.historyView) ? .historyFavicon : nil
            } else if url.isDuckPlayer {
                return .duckPlayerSettings
            } else if url.isDuckAIURL {
                return .aiChatPreferences
            } else if url.isEmailProtection {
                return .emailProtectionIcon
            }

            // For regular URLs, return the actual favicon if available
            return actualFavicon

        case .onboarding, .webExtensionUrl, .none:
            return actualFavicon
        }
    }

    /// Returns the appropriate error favicon based on the error type
    /// - Parameter error: The error that occurred
    /// - Returns: The NSImage to display for the error state
    private static func errorFavicon(for error: Error) -> NSImage {
        // Handle certificate errors and malicious sites
        if let urlError = error as? URLError, urlError.code == .serverCertificateUntrusted {
            return .redAlertCircle16
        } else if let maliciousError = error as? MaliciousSiteError {
            switch maliciousError.code {
            case .phishing, .malware, .scam:
                return .redAlertCircle16
            }
        } else if (error as NSError).isWebContentProcessTerminated {
            return .alertCircleColor16
        }

        // Default error favicon
        return .alertCircleColor16
    }
}

extension NSError {
    /// Helper to check if an error represents a web content process termination
    var isWebContentProcessTerminated: Bool {
        return (self as? WKError)?.code == .webContentProcessTerminated
    }
}
