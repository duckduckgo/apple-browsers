//
//  OptOutConfirmationWideEventData.swift
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

public final class OptOutConfirmationWideEventData: WideEventData {
    public static let pixelName = "pir_opt_out_confirmation"
    private static let featureName = "pir-opt-out-confirmation"

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var dataBrokerURL: String
    public var dataBrokerVersion: String?
    public var confirmationInterval: WideEvent.MeasuredInterval?

    public var errorData: WideEventErrorData?

    public init(globalData: WideEventGlobalData,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                dataBrokerURL: String,
                dataBrokerVersion: String?,
                confirmationInterval: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil) {
        self.globalData = globalData
        self.contextData = contextData
        self.appData = appData
        self.dataBrokerURL = dataBrokerURL
        self.dataBrokerVersion = dataBrokerVersion
        self.confirmationInterval = confirmationInterval
        self.errorData = errorData
    }
}

extension OptOutConfirmationWideEventData {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = Self.featureName
        parameters[WideEventParameter.PIR.OptOutConfirmationFeature.dataBrokerURL] = dataBrokerURL

        if let dataBrokerVersion {
            parameters[WideEventParameter.PIR.OptOutConfirmationFeature.dataBrokerVersion] = dataBrokerVersion
        }

        if let bucketedDuration = bucketedDuration(for: confirmationInterval) {
            parameters[WideEventParameter.PIR.OptOutConfirmationFeature.confirmationLatency] = String(bucketedDuration)
        }

        if let errorData {
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

    private func bucketedDuration(for interval: WideEvent.MeasuredInterval?) -> Int? {
        guard let interval, let start = interval.start, let end = interval.end else {
            return nil
        }

        let ms = max(Int(end.timeIntervalSince(start) * 1000), 0)
        return bucket(ms)
    }

    private func bucket(_ ms: Int) -> Int {
        switch ms {
        case 0..<1_000: return 1_000
        case 1_000..<5_000: return 5_000
        case 5_000..<10_000: return 10_000
        case 10_000..<30_000: return 30_000
        case 30_000..<60_000: return 60_000
        case 60_000..<300_000: return 300_000
        case 300_000..<600_000: return 600_000
        default: return 1_200_000
        }
    }
}
