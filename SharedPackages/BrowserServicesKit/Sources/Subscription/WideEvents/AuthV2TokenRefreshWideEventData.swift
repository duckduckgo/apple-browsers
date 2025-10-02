//
//  AuthV2TokenRefreshWideEventData.swift
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
import PixelKit

public class AuthV2TokenRefreshWideEventData: WideEventData {
    #if DEBUG
    public static let pixelName = "auth_v2_token_refresh_debug"
    #else
    public static let pixelName = "auth_v2_token_refresh"
    #endif

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var failingStep: FailingStep?
    public var errorData: WideEventErrorData?

    public init(failingStep: FailingStep? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.failingStep = failingStep
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }
}

extension AuthV2TokenRefreshWideEventData {

    public enum FailingStep: String, Codable, CaseIterable {
        case tokenRead = "token_read"
        case refreshAccessToken = "refreshAccessToken"
        case fetchingJWKS = "fetch_jwks"
        case verifyingAccessToken = "verify_access_token"
        case verifyingRefreshToken = "verify_refresh_token"
        case tokenWrite = "token_write"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
    }

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = "authv2-token-refresh"

        if let failingStep = failingStep {
            parameters[WideEventParameter.AuthV2RefreshFeature.failingStep] = failingStep.rawValue
        }

        if let errorData = errorData {
            parameters[WideEventParameter.Feature.errorDomain] = errorData.domain
            parameters[WideEventParameter.Feature.errorCode] = String(errorData.code)

            if let underlyingDomain = errorData.underlyingDomain {
                parameters[WideEventParameter.Feature.underlyingErrorDomain] = underlyingDomain
            }

            if let underlyingCode = errorData.underlyingCode {
                parameters[WideEventParameter.Feature.underlyingErrorCode] = String(underlyingCode)
            }
        }

        return parameters
    }

    private func bucket(_ ms: Int) -> Int {
        switch ms {
        case 0..<1000: return 1000
        case 1000..<5000: return 5000
        case 5000..<10000: return 10000
        case 10000..<30000: return 30000
        case 30000..<60000: return 60000
        case 60000..<300000: return 300000
        default: return 600000
        }
    }

}

extension WideEventParameter {

    public enum AuthV2RefreshFeature {
        static let failingStep = "feature.data.ext.failing_step"
    }

}
