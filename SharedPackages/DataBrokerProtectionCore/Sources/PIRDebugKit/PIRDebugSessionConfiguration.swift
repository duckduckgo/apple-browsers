//
//  PIRDebugSessionConfiguration.swift
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
import Common
import DataBrokerProtectionCore

/// The DBP email/captcha services endpoint. Resolved to a base URL that is passed explicitly to
/// `EmailService`/`CaptchaService` (via their `baseURL:` param) so targeting does not depend on the
/// `#if DEBUG`-gated `serviceRoot` override or shared UserDefaults, and works in release builds.
public enum PIRServicesEndpoint: Equatable {
    case production
    case staging
    case custom(URL)

    public var baseURL: URL {
        switch self {
        case .production: return URL(string: "https://dbp.duckduckgo.com")!
        case .staging: return URL(string: "https://dbp-staging.duckduckgo.com")!
        case .custom(let url): return url
        }
    }

    var selectedEnvironment: DataBrokerProtectionSettings.SelectedEnvironment {
        switch self {
        case .production, .custom: return .production
        case .staging: return .staging
        }
    }
}

/// One-shot configuration for a ``PIRDebugSession``.
public struct PIRDebugSessionConfiguration {

    /// Source used by ``PIRDebugSession/fetchBrokers()``.
    public let rulesSource: BrokerRulesProviding
    /// Injected `contentScopeIsolated.js` source. Default `.bundled`.
    public let scriptSource: InjectedScriptSource
    public let authManager: DataBrokerProtectionAuthenticationManaging
    public let showWebView: Bool
    /// Await time (seconds) applied around every action. Fractional and zero allowed; negatives rejected.
    public let operationAwaitTime: TimeInterval
    public let servicesEndpoint: PIRServicesEndpoint
    public let userAgentApplicationName: String?

    // Runner dependencies with PIRDebugKit-provided defaults.
    public let featureFlagger: DBPFeatureFlagging
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public let executionConfig: BrokerJobExecutionConfig

    /// Optional privacy configuration `Data`. `nil` uses the bundled `macos-config.json` resource.
    public let privacyConfigData: Data?

    public init(rulesSource: BrokerRulesProviding,
                authManager: DataBrokerProtectionAuthenticationManaging,
                scriptSource: InjectedScriptSource = .bundled,
                showWebView: Bool = false,
                operationAwaitTime: TimeInterval = 1,
                servicesEndpoint: PIRServicesEndpoint = .production,
                userAgentApplicationName: String? = "pir-debug",
                featureFlagger: DBPFeatureFlagging = PIRDebugFeatureFlagger(),
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = PIRDebugPixels.stderrLoggingPixelHandler(),
                executionConfig: BrokerJobExecutionConfig = BrokerJobExecutionConfig(),
                privacyConfigData: Data? = nil) throws {
        guard operationAwaitTime >= 0 else {
            throw PIRDebugError.negativeOperationAwaitTime(operationAwaitTime)
        }
        self.rulesSource = rulesSource
        self.authManager = authManager
        self.scriptSource = scriptSource
        self.showWebView = showWebView
        self.operationAwaitTime = operationAwaitTime
        self.servicesEndpoint = servicesEndpoint
        self.userAgentApplicationName = userAgentApplicationName
        self.featureFlagger = featureFlagger
        self.pixelHandler = pixelHandler
        self.executionConfig = executionConfig
        self.privacyConfigData = privacyConfigData
    }
}
