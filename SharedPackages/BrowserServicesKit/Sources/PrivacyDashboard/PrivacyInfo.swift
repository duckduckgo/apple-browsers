//
//  PrivacyInfo.swift
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

import Common
import Foundation
import MaliciousSiteProtection
import TrackerRadarKit
import BrowserServicesKit

public protocol SecurityTrust { }
extension SecTrust: SecurityTrust {}

public struct ServerTrustEvaluation {
    let securityTrust: SecurityTrust?
    public let isCertificateInvalid: Bool?

    public init(securityTrust: SecurityTrust?, isCertificateInvalid: Bool?) {
        self.securityTrust = securityTrust
        self.isCertificateInvalid = isCertificateInvalid
    }
}

public final class PrivacyInfo {

    public private(set) var url: URL
    private(set) var parentEntity: Entity?

    @Published public var trackerInfo: TrackerInfo
    @Published private(set) var protectionStatus: ProtectionStatus
    @Published public var serverTrustEvaluation: ServerTrustEvaluation?
    @Published public var connectionUpgradedTo: URL?
    @Published public var cookieConsentManaged: CookieConsentInfo?
    @Published public var malicousSiteThreatKind: MaliciousSiteProtection.ThreatKind?
    @Published public var isSpecialErrorPageVisible: Bool = false
    @Published public var shouldCheckServerTrust: Bool
    public var privacyExperimentCohorts: String
    public private(set) var debugFlags: String = ""

    public init(url: URL, parentEntity: Entity?, protectionStatus: ProtectionStatus, malicousSiteThreatKind: MaliciousSiteProtection.ThreatKind? = .none, shouldCheckServerTrust: Bool = false, allActiveContentScopeExperiments: Experiments = [:]) {
        self.url = url
        self.parentEntity = parentEntity
        self.protectionStatus = protectionStatus
        self.malicousSiteThreatKind = malicousSiteThreatKind
        self.shouldCheckServerTrust = shouldCheckServerTrust
        var experiments: [String: String] = [:]
        for feature in allActiveContentScopeExperiments {
            experiments[feature.key] = feature.value.cohortID
        }
        privacyExperimentCohorts = experiments
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        trackerInfo = TrackerInfo()
    }

    public var https: Bool {
        return url.isHttps
    }

    public var domain: String? {
        return url.host
    }

    public func isFor(_ url: URL?) -> Bool {
        return self.url.host == url?.host
    }

    public func addDebugFlag(_ flag: String) {
        if debugFlags.isEmpty {
            debugFlags = flag
        } else if !debugFlags.contains(flag) {
            debugFlags.append(",\(flag)")
        }
    }
}
