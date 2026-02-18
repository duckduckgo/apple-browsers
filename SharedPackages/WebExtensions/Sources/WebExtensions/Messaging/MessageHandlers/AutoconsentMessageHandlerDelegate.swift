//
//  AutoconsentMessageHandlerDelegate.swift
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

// MARK: - Value Types

/// Represents the consent status information from the web extension
public struct ConsentStatusInfo {
    public let consentManaged: Bool
    public let cosmetic: Bool?
    public let optoutFailed: Bool?
    public let selftestFailed: Bool?
    public let consentReloadLoop: Bool?
    public let consentRule: String?
    public let consentHeuristicEnabled: Bool?

    public init(
        consentManaged: Bool,
        cosmetic: Bool? = nil,
        optoutFailed: Bool? = nil,
        selftestFailed: Bool? = nil,
        consentReloadLoop: Bool? = nil,
        consentRule: String? = nil,
        consentHeuristicEnabled: Bool? = nil
    ) {
        self.consentManaged = consentManaged
        self.cosmetic = cosmetic
        self.optoutFailed = optoutFailed
        self.selftestFailed = selftestFailed
        self.consentReloadLoop = consentReloadLoop
        self.consentRule = consentRule
        self.consentHeuristicEnabled = consentHeuristicEnabled
    }

    /// Initialize from web extension message parameters
    init?(from consentStatus: [String: Any]) {
        guard let consentManaged = consentStatus["consentManaged"] as? Bool else {
            return nil
        }

        self.consentManaged = consentManaged
        self.cosmetic = consentStatus["cosmetic"] as? Bool
        self.optoutFailed = consentStatus["optoutFailed"] as? Bool
        self.selftestFailed = consentStatus["selftestFailed"] as? Bool
        self.consentReloadLoop = consentStatus["consentReloadLoop"] as? Bool
        self.consentRule = consentStatus["consentRule"] as? String
        self.consentHeuristicEnabled = consentStatus["consentHeuristicEnabled"] as? Bool
    }
}

/// Represents pixel information from the web extension
public struct PixelInfo {
    public let name: String
    public let type: String
    public let params: [String: String]

    public init(name: String, type: String, params: [String: String] = [:]) {
        self.name = name
        self.type = type
        self.params = params
    }
}

/// Represents cookie popup handled information
public struct CookiePopupHandledInfo {
    public let url: URL
    public let message: [String: Any]

    public init(url: URL, message: [String: Any]) {
        self.url = url
        self.message = message
    }
}

// MARK: - Delegate Protocol

/// Delegate protocol for handling platform-specific autoconsent operations
/// triggered by the AutoconsentWebExtensionMessageHandler.
///
/// This protocol allows the shared web extension message handler to delegate
/// platform-specific UI updates, analytics, and notifications to iOS or macOS
/// implementations without introducing platform conditionals in shared code.
public protocol AutoconsentMessageHandlerDelegate: AnyObject {

    /// Called when the web extension requests to show a cookie popup animation.
    ///
    /// This typically displays a brief animation in the browser UI to inform
    /// the user that a cookie popup was automatically handled.
    ///
    /// - Parameters:
    ///   - topUrl: The URL of the page where the popup was handled
    ///   - isCosmetic: Whether this was a cosmetic rule (hides popup without clicking)
    ///                 or a full opt-out (actually clicked the reject button)
    func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool)

    /// Called when the web extension requests to refresh the dashboard state.
    ///
    /// This updates the Privacy Dashboard to reflect the current cookie consent
    /// management status for the site.
    ///
    /// - Parameters:
    ///   - domain: The domain for which to update the dashboard
    ///   - consentStatus: Detailed information about the consent status
    func refreshDashboardState(domain: String, consentStatus: ConsentStatusInfo)

    /// Called when a cookie popup has been handled by the web extension.
    ///
    /// This is a more detailed notification that includes the full message
    /// from the web extension, which may contain additional metadata about
    /// how the popup was handled.
    ///
    /// - Parameters:
    ///   - popupInfo: Information about the handled popup
    func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo)

    /// Called when the web extension wants to fire an analytics pixel.
    ///
    /// This delegates pixel firing to the platform-specific analytics infrastructure.
    ///
    /// - Parameters:
    ///   - pixelInfo: Information about the pixel to fire (name, type, parameters)
    func sendPixel(_ pixelInfo: PixelInfo)
}
