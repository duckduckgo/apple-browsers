//
//  OptOutSubmissionWideEventData.swift
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

public final class OptOutSubmissionWideEventData: WideEventData {
    public static let pixelName = "pir_opt_out_submission"
    private static let featureName = "pir-opt-out-submission"

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var dataBrokerURL: String
    public var dataBrokerVersion: String?
    public var submissionInterval: WideEvent.MeasuredInterval?

    public var errorData: WideEventErrorData?

    public struct Stage: Codable, Equatable {
        public let name: StageName
        public let duration: Double?
        public let tries: Int?
        public let actionID: String?

        public init(name: StageName,
                    duration: Double?,
                    tries: Int?,
                    actionID: String?) {
            self.name = name
            self.duration = duration
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

    public var stages: [Stage] = []

    public init(globalData: WideEventGlobalData,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                dataBrokerURL: String,
                dataBrokerVersion: String?,
                submissionInterval: WideEvent.MeasuredInterval? = nil) {
        self.globalData = globalData
        self.contextData = contextData
        self.appData = appData
        self.dataBrokerURL = dataBrokerURL
        self.dataBrokerVersion = dataBrokerVersion
        self.submissionInterval = submissionInterval
    }

    public func appendStage(_ stage: Stage) {
        stages.append(stage)
    }
}

extension OptOutSubmissionWideEventData {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = Self.featureName
        parameters[WideEventParameter.PIR.OptOutSubmissionFeature.dataBrokerURL] = dataBrokerURL

        if let dataBrokerVersion {
            parameters[WideEventParameter.PIR.OptOutSubmissionFeature.dataBrokerVersion] = dataBrokerVersion
        }

        if let duration = submissionInterval?.durationMilliseconds {
            parameters[WideEventParameter.PIR.OptOutSubmissionFeature.submissionLatency] = String(duration)
        }

        for (index, stage) in stages.enumerated() {
            let base = WideEventParameter.PIR.OptOutSubmissionFeature.stagePrefix(index: index)
            parameters["\(base).name"] = stage.name.rawValue

            if let duration = stage.duration {
                parameters["\(base).duration_ms"] = String(duration)
            }

            if let tries = stage.tries {
                parameters["\(base).tries"] = String(tries)
            }

            if let actionID = stage.actionID {
                parameters["\(base).action_id"] = actionID.isEmpty ? "unknown" : actionID
            }
        }

        return parameters
    }
}
