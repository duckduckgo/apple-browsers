//
//  EmailConfirmationJobDependencies.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

public protocol EmailConfirmationJobDependencyProviding {
    var database: DataBrokerProtectionRepository { get }
    var contentScopeProperties: ContentScopeProperties { get }
    var privacyConfig: PrivacyConfigurationManaging { get }
    var executionConfig: BrokerJobExecutionConfig { get }
    var pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> { get }
    var emailConfirmationDataService: EmailConfirmationDataServiceProvider { get }
    var captchaService: CaptchaServiceProtocol { get }
    var vpnBypassService: VPNBypassFeatureProvider? { get }
    var featureFlagger: DBPFeatureFlagging { get }
}

public struct EmailConfirmationJobDependencies: EmailConfirmationJobDependencyProviding {
    public let database: DataBrokerProtectionRepository
    public let contentScopeProperties: ContentScopeProperties
    public let privacyConfig: PrivacyConfigurationManaging
    public let executionConfig: BrokerJobExecutionConfig
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public let emailConfirmationDataService: EmailConfirmationDataServiceProvider
    public let captchaService: CaptchaServiceProtocol
    public let vpnBypassService: VPNBypassFeatureProvider?
    public let featureFlagger: DBPFeatureFlagging

    public init(from brokerDependencies: BrokerProfileJobDependencyProviding) {
        self.database = brokerDependencies.database
        self.contentScopeProperties = brokerDependencies.contentScopeProperties
        self.privacyConfig = brokerDependencies.privacyConfig
        self.executionConfig = brokerDependencies.executionConfig
        self.pixelHandler = brokerDependencies.pixelHandler
        self.emailConfirmationDataService = brokerDependencies.emailConfirmationDataService
        self.captchaService = brokerDependencies.captchaService
        self.vpnBypassService = brokerDependencies.vpnBypassService
        self.featureFlagger = brokerDependencies.featureFlagger
    }

    public init(database: DataBrokerProtectionRepository,
                contentScopeProperties: ContentScopeProperties,
                privacyConfig: PrivacyConfigurationManaging,
                executionConfig: BrokerJobExecutionConfig,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                emailConfirmationDataService: EmailConfirmationDataServiceProvider,
                captchaService: CaptchaServiceProtocol,
                vpnBypassService: VPNBypassFeatureProvider?,
                featureFlagger: DBPFeatureFlagging) {
        self.database = database
        self.contentScopeProperties = contentScopeProperties
        self.privacyConfig = privacyConfig
        self.executionConfig = executionConfig
        self.pixelHandler = pixelHandler
        self.emailConfirmationDataService = emailConfirmationDataService
        self.captchaService = captchaService
        self.vpnBypassService = vpnBypassService
        self.featureFlagger = featureFlagger
    }
}
