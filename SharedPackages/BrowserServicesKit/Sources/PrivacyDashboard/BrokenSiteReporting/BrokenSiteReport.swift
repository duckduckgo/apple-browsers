//
//  BrokenSiteReport.swift
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
//  Implementation guidelines: https://app.asana.com/0/1198207348643509/1200202563872939/f

import Foundation
import Common

public struct BrokenSiteReport {

    public enum Mode {

        case regular
        case toggle

    }

    public enum Source {

        /// From the app menu's "Report Broken Site"
        case appMenu
        /// From the privacy dashboard's "Website not working?"
        case dashboard
        /// From the app menu's "Disable Privacy Protection"
        case onProtectionsOffMenu
        /// From the privacy dashboard's on protections toggle off
        case onProtectionsOffDashboard
        /// From the 'Site Not Working?' prompt that appears after user refreshes 3 times within 20 sec window
        case prompt
        /// From the prompt that appears after user toggled off protections which asks if it helped
        case afterTogglePrompt

        public var rawValue: String {
            switch self {
            case .appMenu: return "menu"
            case .dashboard: return "dashboard"
            case .onProtectionsOffMenu: return "on_protections_off_menu"
            case .onProtectionsOffDashboard: return "on_protections_off_dashboard_main"
            case .prompt: return "reload-three-times-within-20-seconds" // previously multiple events were under this; now there's only one
            case .afterTogglePrompt: return "after_toggle_prompt"
            }
        }

    }

#if os(iOS)
    public enum SiteType: String {

        case desktop
        case mobile

    }
#endif

    public enum OpenerContext: String {
        case serp
        case external
        case navigation
    }

    public static let allowedQueryReservedCharacters = CharacterSet(charactersIn: ",")

    let siteUrl: URL
    let category: String
    let description: String?
    let osVersion: String
    let manufacturer: String
    let upgradedHttps: Bool
    let tdsETag: String?
    let configVersion: String?
    let blockedTrackerDomains: [String]
    let installedSurrogates: [String]
    let isGPCEnabled: Bool
    let ampURL: String
    let urlParametersRemoved: Bool
    let reportFlow: Source
    let protectionsState: Bool
    var lastSentDay: String?
    let errors: [Error]?
    let httpStatusCodes: [Int]?
    let openerContext: OpenerContext?
    let vpnOn: Bool
    let jsPerformance: [Double]?
    let userRefreshCount: Int
    let locale: Locale
    let cookieConsentInfo: CookieConsentInfo?
    let debugFlags: String
    let privacyExperiments: [String: String]
#if os(iOS)
    let siteType: SiteType
    let atb: String
    let model: String
    let variant: String
#endif

#if os(macOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        configVersion: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        openerContext: OpenerContext?,
        vpnOn: Bool,
        jsPerformance: [Double]?,
        userRefreshCount: Int,
        locale: Locale = Locale.current,
        cookieConsentInfo: CookieConsentInfo?,
        debugFlags: String,
        privacyExperiments: [String: String]
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.configVersion = configVersion
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.openerContext = openerContext
        self.vpnOn = vpnOn
        self.jsPerformance = jsPerformance
        self.userRefreshCount = userRefreshCount
        self.locale = locale
        self.cookieConsentInfo = cookieConsentInfo
        self.debugFlags = debugFlags
        self.privacyExperiments = privacyExperiments
    }
#endif

#if os(iOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        configVersion: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        siteType: SiteType,
        atb: String,
        model: String,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        openerContext: OpenerContext?,
        vpnOn: Bool,
        jsPerformance: [Double]?,
        userRefreshCount: Int,
        variant: String,
        locale: Locale = Locale.current,
        cookieConsentInfo: CookieConsentInfo?,
        debugFlags: String,
        privacyExperiments: [String: String]
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.configVersion = configVersion
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.siteType = siteType
        self.atb = atb
        self.model = model
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.openerContext = openerContext
        self.vpnOn = vpnOn
        self.jsPerformance = jsPerformance
        self.userRefreshCount = userRefreshCount
        self.variant = variant
        self.locale = locale
        self.cookieConsentInfo = cookieConsentInfo
        self.debugFlags = debugFlags
        self.privacyExperiments = privacyExperiments
    }
#endif

    /// A dictionary containing all the parameters needed from the Report Broken Site Pixel
    public var requestParameters: [String: String] { getRequestParameters(forReportMode: .regular) }

    public func getRequestParameters(forReportMode mode: Mode) -> [String: String] {
        var result: [String: String] = [
            "siteUrl": siteUrl.trimmingQueryItemsAndFragment().absoluteString,
            "upgradedHttps": upgradedHttps.description,
            "tds": tdsETag?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "",
            "remote_config_version": configVersion ?? "",
            "blockedTrackers": blockedTrackerDomains.joined(separator: ","),
            "surrogates": installedSurrogates.joined(separator: ","),
            "gpc": isGPCEnabled.description,
            "ampUrl": ampURL,
            "urlParametersRemoved": urlParametersRemoved.description,
            "os": osVersion,
            "manufacturer": manufacturer,
            "reportFlow": reportFlow.rawValue,
            "openerContext": openerContext?.rawValue ?? "",
            "vpnOn": vpnOn.description,
            "userRefreshCount": String(userRefreshCount),
            "locale": locale.localeIdentifierAsJsonFormat,
            "consentManaged": boolToStringValue(cookieConsentInfo?.consentManaged),
            "consentOptoutFailed": boolToStringValue(cookieConsentInfo?.optoutFailed),
            "consentSelftestFailed": boolToStringValue(cookieConsentInfo?.selftestFailed),
            "debugFlags": debugFlags
        ]

        if mode == .regular {
            result["category"] = category
            result["description"] = description ?? ""
            result["protectionsState"] = protectionsState.description
        }

        if let lastSentDay = lastSentDay {
            result["lastSentDay"] = lastSentDay
        }

        if let httpStatusCodes {
            let codes: [String] = httpStatusCodes.map { String($0) }
            result["httpErrorCodes"] = codes.joined(separator: ",")
        }

        if let errors {
            result["errorDescriptions"] = encodeErrors(errors)
        }

        if let jsPerformance {
            let perf = jsPerformance.map { String($0) }.joined(separator: ",")
            result["jsPerformance"] = perf
        }

        for (key, value) in privacyExperiments {
            result[key] = value
        }

#if os(iOS)
        result["siteType"] = siteType.rawValue
        result["atb"] = atb
        result["model"] = model
        result["variant"] = variant
#endif
        return result
    }

    private func boolToStringValue(_ value: Bool?) -> String {
        switch value {
        case .init(true):
            return "1"
        case .init(false):
            return "0"
        default:
            return ""
        }
    }

    private func encodeErrors(_ errors: [Error]) -> String {
        let errorDescriptions: [String] = errors.map {
            let error = $0 as NSError
            return "\(error.code) - \(error.domain):\(error.localizedDescription)"
        }
        let jsonString = try? String(data: JSONSerialization.data(withJSONObject: errorDescriptions), encoding: .utf8)!
        return jsonString ?? ""
    }

}
