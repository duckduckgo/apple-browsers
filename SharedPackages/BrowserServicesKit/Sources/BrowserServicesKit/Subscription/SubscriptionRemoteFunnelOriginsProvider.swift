//
//  SubscriptionRemoteFunnelOriginsProvider.swift
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

public enum ResolvedFunnelOrigin: Equatable {
    case app(String)
    case remote(String)
    case unknown(reportableOrigin: String?)

    fileprivate static func reportableOrigin(_ origin: String) -> String? {
        let origin = origin.lowercased()
        guard origin.range(of: "^funnel_[a-z0-9_]{1,64}$", options: .regularExpression) != nil else {
            return nil
        }
        return origin
    }
}

public protocol SubscriptionRemoteFunnelOriginsProviding {
    var allowlistedOrigins: Set<String> { get }
}

extension SubscriptionRemoteFunnelOriginsProviding {

    public func resolveOrigin(_ origin: String?, isAppOrigin: (String) -> Bool) -> ResolvedFunnelOrigin? {
        guard let origin, !origin.isEmpty else { return nil }
        if isAppOrigin(origin) {
            return .app(origin)
        }
        if allowlistedOrigins.contains(origin) {
            return .remote(origin)
        }
        return .unknown(reportableOrigin: ResolvedFunnelOrigin.reportableOrigin(origin))
    }
}

public struct DefaultSubscriptionRemoteFunnelOriginsProvider: SubscriptionRemoteFunnelOriginsProviding {

    private static let logger = Logger(subsystem: "Subscription", category: "RemoteFunnelOrigins")

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    public init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    public var allowlistedOrigins: Set<String> {
        let privacyConfig = privacyConfigurationManager.privacyConfig
        guard privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.subscriptionRemoteFunnelOrigins),
              let settingsString = privacyConfig.settings(for: PrivacyProSubfeature.subscriptionRemoteFunnelOrigins),
              let settingsData = settingsString.data(using: .utf8) else {
            return []
        }
        do {
            return Set(try JSONDecoder().decode(Settings.self, from: settingsData).funnelOriginAllowlist)
        } catch {
            Self.logger.error("Failed to decode remote funnel origins settings: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Failed to decode remote funnel origins settings: \(error)")
            return []
        }
    }

    private struct Settings: Decodable {
        let funnelOriginAllowlist: [String]
    }
}
