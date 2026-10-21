//
//  CookieConsentInfo.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public enum CookieConsentCPMDashboardState: String, Encodable {
    case waiting
    case applied
}

public enum CookieConsentCPMStage: String, Encodable {
    case notStarted = "not_started"
    case configUnavailable = "config_unavailable"
    case settingsMissing = "settings_missing"
    case settingDisabled = "setting_disabled"
    case siteDisabled = "site_disabled"
    case initReceived = "init_received"
    case popupFound = "popup_found"
    case optoutFailed = "optout_failed"
    case done
}

public struct CookieConsentInfo: Encodable {

    public let consentManaged: Bool
    public let cosmetic: Bool?
    public let optoutFailed: Bool?
    public let selftestFailed: Bool?
    public let consentReloadLoop: Bool?
    public let consentRule: String?
    public let consentHeuristicEnabled: Bool?
    public let cpmExtensionDroppedCallbacks: Int?
    public let cpmExtensionLoaded: Bool?
    public let cpmDashboardState: CookieConsentCPMDashboardState?
    public let cpmStage: CookieConsentCPMStage?
    public let cpmErrors: String?
    public let cpmQueueSize: Int?
    public let cpmConfigVersion: String?
    public let configurable = true

    public static var initialCPMDiagnostics: CookieConsentInfo {
        CookieConsentInfo(
            consentManaged: false,
            cosmetic: nil,
            optoutFailed: nil,
            selftestFailed: nil,
            consentReloadLoop: nil,
            consentRule: nil,
            consentHeuristicEnabled: nil,
            cpmExtensionDroppedCallbacks: nil,
            cpmExtensionLoaded: nil,
            cpmDashboardState: .waiting,
            cpmStage: .notStarted,
            cpmErrors: nil,
            cpmQueueSize: nil,
            cpmConfigVersion: ""
        )
    }

    public init(
        consentManaged: Bool,
        cosmetic: Bool?,
        optoutFailed: Bool?,
        selftestFailed: Bool?,
        consentReloadLoop: Bool?,
        consentRule: String?,
        consentHeuristicEnabled: Bool?,
        cpmExtensionDroppedCallbacks: Int? = nil,
        cpmExtensionLoaded: Bool? = nil,
        cpmDashboardState: CookieConsentCPMDashboardState? = nil,
        cpmStage: CookieConsentCPMStage? = nil,
        cpmErrors: String? = nil,
        cpmQueueSize: Int? = nil,
        cpmConfigVersion: String? = nil
    ) {
        self.consentManaged = consentManaged
        self.cosmetic = cosmetic
        self.optoutFailed = optoutFailed
        self.selftestFailed = selftestFailed
        self.consentReloadLoop = consentReloadLoop
        self.consentRule = consentRule
        self.consentHeuristicEnabled = consentHeuristicEnabled
        self.cpmExtensionDroppedCallbacks = cpmExtensionDroppedCallbacks
        self.cpmExtensionLoaded = cpmExtensionLoaded
        self.cpmDashboardState = cpmDashboardState
        self.cpmStage = cpmStage
        self.cpmErrors = cpmErrors
        self.cpmQueueSize = cpmQueueSize
        self.cpmConfigVersion = cpmConfigVersion
    }

    /// Preserves the dashboard-reported CPM state while overlaying values only known when a breakage report is assembled.
    public func withCPMRuntimeInfo(extensionLoaded: Bool?, droppedCallbacks: Int?) -> CookieConsentInfo {
        CookieConsentInfo(
            consentManaged: consentManaged,
            cosmetic: cosmetic,
            optoutFailed: optoutFailed,
            selftestFailed: selftestFailed,
            consentReloadLoop: consentReloadLoop,
            consentRule: consentRule,
            consentHeuristicEnabled: consentHeuristicEnabled,
            cpmExtensionDroppedCallbacks: droppedCallbacks,
            cpmExtensionLoaded: extensionLoaded,
            cpmDashboardState: cpmDashboardState,
            cpmStage: cpmStage,
            cpmErrors: cpmErrors,
            cpmQueueSize: cpmQueueSize,
            cpmConfigVersion: cpmConfigVersion
        )
    }

}
