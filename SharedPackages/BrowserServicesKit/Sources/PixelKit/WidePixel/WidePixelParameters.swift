//
//  WidePixelParameters.swift
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

public protocol WidePixelParameterProviding {
    func pixelParameters() -> [String: String]
}

public enum WidePixelParameter {

    public enum Global {
        static let platform = "global.platform"
        static let type = "global.type"
        static let sampleRate = "global.sample_rate"
        static let formFactor = "global.form_factor"
    }

    public enum App {
        static let name = "app.name"
        static let version = "app.version"
        static let internalUser = "app.internal_user"
    }

    public enum Context {
        static let name = "context.name"
    }

    public enum Feature {
        static let name = "feature.name"
        static let status = "feature.status"
        static let statusReason = "feature.status_reason"

        static let errorDomain = "feature.data.error.domain"
        static let errorCode = "feature.data.error.code"
        static let underlyingErrorDomain = "feature.data.error.underlying_domain"
        static let underlyingErrorCode = "feature.data.error.underlying_code"
    }

    public enum SubscriptionFeature {
        static let purchasePlatform = "feature.data.ext.purchase_platform"
        static let failingStep = "feature.data.ext.failing_step"
        static let subscriptionIdentifier = "feature.data.ext.subscription_identifier"
        static let freeTrialEligible = "feature.data.ext.free_trial_eligible"
        static let accountCreationLatency = "feature.data.ext.account_creation_latency_ms_bucketed"
        static let accountPaymentLatency = "feature.data.ext.account_payment_latency_ms_bucketed"
        static let accountActivationLatency = "feature.data.ext.account_activation_latency_ms_bucketed"
    }

}
