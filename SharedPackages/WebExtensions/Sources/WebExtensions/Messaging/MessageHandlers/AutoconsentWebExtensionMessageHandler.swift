//
//  AutoconsentWebExtensionMessageHandler.swift
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
import os.log
import PrivacyConfig

public protocol AutoconsentPreferencesProviding {
    var isAutoconsentEnabled: Bool { get }
}

@available(macOS 15.4, iOS 18.4, *)
public final class AutoconsentWebExtensionMessageHandler: WebExtensionMessageHandler {

    enum Method: String {
        case sendPixel
        case refreshCpmDashboardState
        case showCpmAnimation
        case cookiePopupHandled
        case isFeatureEnabled
        case isSubFeatureEnabled
        case getResourceIfNew
        case isAutoconsentSettingEnabled
        case extensionLog
    }

    private static let successResponse: [String: String] = ["response": "ok"]

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let autoconsentPreferences: AutoconsentPreferencesProviding

    public var handledFeatureName: String { "autoconsent" }

    public init(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.autoconsentPreferences = autoconsentPreferences
    }

    public func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        Logger.webExtensions.debug("📝 AutoconsentWebExtensionMessageHandler received method: \(message.method)")

        guard let method = Method(rawValue: message.method) else {
            return .failure(WebExtensionMessageHandlerError.unknownMethod(message.method))
        }

        switch method {
        case .sendPixel:
//            return handleSendPixel(message.params)
            Logger.webExtensions.debug("📝 AutoconsentWebExtensionMessageHandler --- Params: \(String(describing: message.params))")
            return .failure(WebExtensionMessageHandlerError.unknownMethod("sendPixel"))
        case .refreshCpmDashboardState:
//            return handleRefreshCpmDashboardState(message.params)
            return .failure(WebExtensionMessageHandlerError.unknownMethod("refreshCpmDashboardState"))
        case .showCpmAnimation:
//            return handleShowCpmAnimation(message.params)
            Logger.webExtensions.debug("📝 AutoconsentWebExtensionMessageHandler --- Params: \(String(describing: message.params))")
            return .failure(WebExtensionMessageHandlerError.unknownMethod("showCpmAnimation"))
        case .cookiePopupHandled:
//            return handleCookiePopupHandled(message.params)
            Logger.webExtensions.debug("📝 AutoconsentWebExtensionMessageHandler --- Params: \(String(describing: message.params))")
            return .failure(WebExtensionMessageHandlerError.unknownMethod("cookiePopupHandled"))
        case .isFeatureEnabled:
            return handleIsFeatureEnabled(message.params)
        case .isSubFeatureEnabled:
            return handleIsSubFeatureEnabled(message.params)
        case .getResourceIfNew:
            return handleGetResourceIfNew(message.params)
        case .isAutoconsentSettingEnabled:
            return handleIsAutoconsentSettingEnabled(message.params)
        case .extensionLog:
            return handleExtensionLog(message.params)
        }
    }

//    private func handleSendPixel(_ params: [String: Any]?) -> WebExtensionMessageResult {
//        guard
//            let pixelName = params?["pixelName"] as? String,
//            let type = params?["type"] as? String
//        else {
//            return .failure(WebExtensionMessageHandlerError.missingParameter("pixelName or type"))
//        }
//
//        let pixelParams = params?["params"] as? [String: String] ?? [:]
//
//        Logger.webExtensions.debug("📊 Send Pixel - name: \(pixelName), type: \(type), params: \(pixelParams)")
//
//        return .success(Self.successResponse)
//    }

//    private func handleRefreshCpmDashboardState(_ params: [String: Any]?) -> WebExtensionMessageResult {
//        guard
//            let tabId = params?["tabId"] as? Int,
//            let domain = params?["domain"] as? String,
//            let consentStatus = params?["consentStatus"] as? [String: Any],
//            let consentManaged = consentStatus["consentManaged"] as? Bool
//        else {
//            return .failure(WebExtensionMessageHandlerError.missingParameter("tabId, domain, or consentStatus"))
//        }
//
//        let cosmetic = consentStatus["cosmetic"] as? Bool
//        let optoutFailed = consentStatus["optoutFailed"] as? Bool
//        let selftestFailed = consentStatus["selftestFailed"] as? Bool
//        let consentReloadLoop = consentStatus["consentReloadLoop"] as? Bool
//        let consentRule = consentStatus["consentRule"] as? String
//        let consentHeuristicEnabled = consentStatus["consentHeuristicEnabled"] as? Bool
//
//        Logger.webExtensions.debug("📊 Refresh CPM Dashboard State - tabId: \(tabId), domain: \(domain), consentManaged: \(consentManaged)")
//
//        return .success(Self.successResponse)
//    }

//    private func handleShowCpmAnimation(_ params: [String: Any]?) -> WebExtensionMessageResult {
//        guard
//            let tabId = params?["tabId"] as? Int,
//            let topUrl = params?["topUrl"] as? String,
//            let isCosmetic = params?["isCosmetic"] as? Bool
//        else {
//            return .failure(WebExtensionMessageHandlerError.missingParameter("tabId, topUrl, or isCosmetic"))
//        }
//
//        Logger.webExtensions.debug("🎬 Show CPM Animation - tabId: \(tabId), topUrl: \(topUrl), isCosmetic: \(isCosmetic)")
//
//        return .success(Self.successResponse)
//    }

//    private func handleCookiePopupHandled(_ params: [String: Any]?) -> WebExtensionMessageResult {
//        guard
//            let tabId = params?["tabId"] as? Int,
//            let url = params?["url"] as? String,
//            let msg = params?["msg"] as? [String: Any]
//        else {
//            return .failure(WebExtensionMessageHandlerError.missingParameter("tabId, url, or msg"))
//        }
//
//        Logger.webExtensions.debug("🍪 Cookie Popup Handled - tabId: \(tabId), url: \(url)")
//
//        return .success(Self.successResponse)
//    }

    private func handleIsFeatureEnabled(_ params: [String: Any]?) -> WebExtensionMessageResult {
        guard
            let featureName = params?["featureName"] as? String,
            let urlString = params?["url"] as? String
        else {
            return .failure(WebExtensionMessageHandlerError.missingParameter("featureName or url"))
        }

        Logger.webExtensions.debug("🔍 Is Feature Enabled - feature: \(featureName), url: \(urlString)")

        guard let feature = PrivacyFeature(rawValue: featureName) else {
            Logger.webExtensions.error("❌ Unknown feature name: \(featureName)")
            return .success(["enabled": false])
        }

        let domain = URL(string: urlString)?.host
        let isEnabled = privacyConfigurationManager.privacyConfig.isFeature(feature, enabledForDomain: domain)

        return .success(["enabled": isEnabled])
    }

    private func handleIsSubFeatureEnabled(_ params: [String: Any]?) -> WebExtensionMessageResult {
        guard
            let featureName = params?["featureName"] as? String,
            let subfeatureName = params?["subfeatureName"] as? String
        else {
            return .failure(WebExtensionMessageHandlerError.missingParameter("featureName or subfeatureName"))
        }

        Logger.webExtensions.debug("🔍 Is SubFeature Enabled - feature: \(featureName), subfeature: \(subfeatureName)")

        guard let feature = PrivacyFeature(rawValue: featureName) else {
            Logger.webExtensions.error("❌ Unknown feature name: \(featureName)")
            return .success(["enabled": false])
        }

        guard feature == .autoconsent else {
            Logger.webExtensions.error("❌ Subfeature check not supported for feature: \(featureName)")
            return .success(["enabled": false])
        }

        guard let subfeature = AutoconsentSubfeature(rawValue: subfeatureName) else {
            Logger.webExtensions.error("❌ Unknown autoconsent subfeature: \(subfeatureName)")
            return .success(["enabled": false])
        }

        let isEnabled = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(subfeature)

        return .success(["enabled": isEnabled])
    }

    private func handleGetResourceIfNew(_ params: [String: Any]?) -> WebExtensionMessageResult {
        guard
            let requestedResource = params?["name"] as? String,
            let requestedVersion = params?["version"] as? String
        else {
            return .failure(WebExtensionMessageHandlerError.missingParameter("name or version"))
        }

        Logger.webExtensions.debug("📦 Get Resource If New - name: \(requestedResource), version: \(requestedVersion)")

        switch requestedResource {
        case "config":
            return privacyConfigIfNewerThan(lastVersion: requestedVersion)
        default:
            Logger.webExtensions.error("❌ Unsupported resource type: \(requestedResource)")
            return .failure(WebExtensionMessageHandlerError.unsupportedResourceType(requestedResource))
        }

    }

    private func privacyConfigIfNewerThan(lastVersion: String) -> WebExtensionMessageResult {
        guard let privacyConfigData = try? PrivacyConfigurationData(data: privacyConfigurationManager.currentConfig),
              let currentVersion = privacyConfigData.version else {
            Logger.webExtensions.error("❌ Failed to read privacy config data or version is missing")
            return .failure(WebExtensionMessageHandlerError.configurationError("Failed to read privacy config data or version is missing"))
        }

        if currentVersion == lastVersion {
            return .success([
                "updated": false
            ])
        } else {
            return .success([
                "updated": true,
                "data": privacyConfigData.toJSONDictionary(),
                "version": currentVersion
            ])
        }
    }

    private func handleIsAutoconsentSettingEnabled(_ params: [String: Any]?) -> WebExtensionMessageResult {
        let isEnabled = autoconsentPreferences.isAutoconsentEnabled
        Logger.webExtensions.debug("⚙️ Is Autoconsent Setting Enabled: \(isEnabled)")

        // Uncomment to force-enable web extension CPM regardless of app settings (required for testing as a replacement to native CPM)
        // return .success(["enabled": true])

        return .success(["enabled": isEnabled])
    }

    private func handleExtensionLog(_ params: [String: Any]?) -> WebExtensionMessageResult {
        guard let message = params?["message"] as? String else {
            return .failure(WebExtensionMessageHandlerError.missingParameter("message"))
        }
        Logger.webExtensions.debug("[🪵] \(message)")

        return .success(Self.successResponse)
    }
}
