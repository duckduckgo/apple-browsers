//
//  OptOutWideEventData.swift
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

public final class OptOutWideEventData: WideEventData {
    public static let pixelName = "pir_opt_out"

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var dataBrokerURL: String
    public var dataBrokerVersion: String?
    public var submissionInterval: WideEvent.MeasuredInterval?
    public var confirmationInterval: WideEvent.MeasuredInterval?

    public var errorData: WideEventErrorData?

    public struct Stage: Codable, Equatable {
        public let name: StageName
        public let durationMilliseconds: Int?
        public let tries: Int?
        public let actionID: String?

        public init(name: StageName,
                    durationMilliseconds: Int?,
                    tries: Int?,
                    actionID: String?) {
            self.name = name
            self.durationMilliseconds = durationMilliseconds
            self.tries = tries
            self.actionID = actionID
        }
    }

    public enum StageName: String, Codable, CaseIterable {
        case start
        case emailGenerate = "email-generate"
        case captchaParse = "captcha-parse"
        case captchaSend = "captcha-send"
        case captchaSolve = "captcha-solve"
        case submit
        case emailReceive = "email-receive"
        case emailConfirm = "email-confirm"
        case emailConfirmHalted = "email-confirm-halted"
        case emailConfirmDecoupled = "email-confirm-decoupled"
        case validate
        case fillForm = "fill-form"
        case conditionFound = "condition-found"
        case conditionNotFound = "condition-not-found"
        case other
    }

    public private(set) var stages: [Stage]

    public init(globalData: WideEventGlobalData,
                contextData: WideEventContextData = WideEventContextData(name: "pir-opt-out"),
                appData: WideEventAppData = WideEventAppData(),
                dataBrokerURL: String,
                dataBrokerVersion: String?,
                submissionInterval: WideEvent.MeasuredInterval? = nil,
                confirmationInterval: WideEvent.MeasuredInterval? = nil,
                errorData: WideEventErrorData? = nil,
                stages: [Stage] = []) {
        self.globalData = globalData
        self.contextData = contextData
        self.appData = appData
        self.dataBrokerURL = dataBrokerURL
        self.dataBrokerVersion = dataBrokerVersion
        self.submissionInterval = submissionInterval
        self.confirmationInterval = confirmationInterval
        self.errorData = errorData
        self.stages = stages
    }

    public func appendStage(_ stage: Stage) {
        stages.append(stage)
    }
}

extension OptOutWideEventData {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = "pir-opt-out"
        parameters[WideEventParameter.PIR.OptOutFeature.dataBrokerURL] = dataBrokerURL

        if let dataBrokerVersion {
            parameters[WideEventParameter.PIR.OptOutFeature.dataBrokerVersion] = dataBrokerVersion
        }

        if let submissionBuckets = bucketedValues(for: submissionInterval) {
            parameters.merge(submissionBuckets.withPrefix(WideEventParameter.PIR.OptOutFeature.submissionIntervalPrefix), uniquingKeysWith: { _, new in new })
        }

        if let confirmationBuckets = bucketedValues(for: confirmationInterval) {
            parameters.merge(confirmationBuckets.withPrefix(WideEventParameter.PIR.OptOutFeature.confirmationIntervalPrefix), uniquingKeysWith: { _, new in new })
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

        for (index, stage) in stages.enumerated() {
            let base = WideEventParameter.PIR.OptOutFeature.stagePrefix(index: index)
            parameters["\(base).name"] = stage.name.rawValue

            if let duration = stage.durationMilliseconds {
                parameters["\(base).duration_ms"] = String(duration)
            }

            if let tries = stage.tries {
                parameters["\(base).tries"] = String(tries)
            }

            if let actionID = stage.actionID, !actionID.isEmpty {
                parameters["\(base).action_id"] = actionID
            }
        }

        return parameters
    }

    private func bucketedValues(for interval: WideEvent.MeasuredInterval?) -> IntervalBuckets? {
        guard let interval, let start = interval.start, let end = interval.end else { return nil }
        let ms = max(Int(end.timeIntervalSince(start) * 1000), 0)
        return IntervalBuckets(durationMilliseconds: ms)
    }
}

private struct IntervalBuckets {
    let durationMilliseconds: Int

    func withPrefix(_ prefix: String) -> [String: String] {
        return ["\(prefix).duration_ms_bucketed": String(bucket(durationMilliseconds))]
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
