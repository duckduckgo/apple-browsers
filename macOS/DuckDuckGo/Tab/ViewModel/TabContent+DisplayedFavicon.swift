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
import DesignResourcesKit
import DesignResourcesKitIcons
import FeatureFlags_macOS
import MaliciousSiteProtection
import PrivacyConfig
import WebKit

extension TabContent {

    /// Returns the appropriate favicon for this tab content, considering errors, special URLs, and content types
    /// - Parameters:
    ///   - error: Optional error from the tab (for error state favicons)
    ///   - actualFavicon: The actual favicon loaded from the webpage (if any)
    ///   - isBurner: Whether this is a burner tab (affects newtab favicon)
    ///   - featureFlagger: Feature flag provider for checking enabled features
    /// - Returns: The NSImage to display as the favicon, or nil if no favicon should be shown
    func displayedFavicon(
        error: Error? = nil,
        actualFavicon: NSImage? = nil,
        isBurner: Bool = false,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger
    ) -> NSImage? {

        // Handle error states first
        if let error {
            return Self.errorFavicon(for: error)
        }

        // Handle special content types and URLs
        switch self {
        case .dataBrokerProtection:
            return NSImage(resource: .personalInformationRemovalMulticolor16)

        case .newtab where isBurner:
            return DesignSystemImages.Glyphs.Size16.fireTab

        case .newtab:
            return NSImage(resource: .homeFavicon)

        case .settings:
            return DesignSystemRebrand.isAppRebranded() ? DesignSystemImages.Color.Size16.settings : NSImage(resource: .settingsMulticolor16Legacy)

        case .bookmarks:
            return DesignSystemRebrand.isAppRebranded() ? DesignSystemImages.Color.Size16.bookmarksNew : NSImage(resource: .bookmarksFolder)

        case .onboarding:
            return NSImage(resource: .onboardingDax)

        case .history:
            return DesignSystemRebrand.isAppRebranded() ? DesignSystemImages.Color.Size16.history : NSImage(resource: .historyFaviconLegacy)

        case .subscription:
            return DesignSystemRebrand.isAppRebranded() ?  DesignSystemImages.Color.Size16.subscription : NSImage(resource: .privacyProLegacy)

        case .identityTheftRestoration:
            return NSImage(resource: .identityTheftRestorationMulticolor16)

        case .releaseNotes:
            return NSImage(resource: .homeFavicon)

        case .aiChat:
            return DesignSystemImages.Color.Size16.duckAI

        case .url(let url, _, _):
            // Handle special URL types
            if url.isHistory {
                return DesignSystemRebrand.isAppRebranded() ? DesignSystemImages.Color.Size16.history : NSImage(resource: .historyFaviconLegacy)
            } else if url.isDuckPlayer {
                return NSImage(resource: .duckPlayerSettings)
            } else if url.isDuckAIURL {
                return DesignSystemImages.Color.Size16.duckAI
            } else if url.isEmailProtection {
                return DesignSystemRebrand.isAppRebranded() ? DesignSystemImages.Color.Size16.emailProtection : NSImage(resource: .emailProtectionIconLegacy)
            }

            // For regular URLs, return the actual favicon if available
            return actualFavicon

        case .webExtensionUrl, .none:
            return actualFavicon
        }
    }

    /// Returns the appropriate error favicon based on the error type
    /// - Parameter error: The error that occurred
    /// - Returns: The NSImage to display for the error state
    private static func errorFavicon(for error: Error) -> NSImage {
        // Handle certificate errors and malicious sites
        if let urlError = error as? URLError, urlError.code == .serverCertificateUntrusted {
            return NSImage(resource: .redAlertCircle16)
        } else if let maliciousError = error as? MaliciousSiteError {
            switch maliciousError.code {
            case .phishing, .malware, .scam:
                return NSImage(resource: .redAlertCircle16)
            }
        } else if (error as NSError).isWebContentProcessTerminated {
            return NSImage(resource: .alertCircleColor16)
        }

        // Default error favicon
        return NSImage(resource: .alertCircleColor16)
    }
}

extension NSError {
    /// Helper to check if an error represents a web content process termination
    var isWebContentProcessTerminated: Bool {
        return (self as? WKError)?.code == .webContentProcessTerminated
    }
}
