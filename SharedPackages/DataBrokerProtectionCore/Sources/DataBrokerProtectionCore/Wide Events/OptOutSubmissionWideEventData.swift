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
import PixelKit

public final class OptOutSubmissionWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "pir_opt_out_submission",
        featureName: "pir-opt-out-submission",
        mobileMetaType: "ios-pir-opt-out-submission",
        desktopMetaType: "macos-pir-opt-out-submission",
        version: "1.0.0"
    )

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var dataBrokerURL: String
    public var dataBrokerVersion: String?
    public var submissionInterval: WideEvent.MeasuredInterval?

    public var errorData: WideEventErrorData?

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
}

extension OptOutSubmissionWideEventData {

    public enum StatusReason: String {
        case submissionWindowExpired = "submission_window_expired"
        case recordFoundDateMissing = "record_found_date_missing"
    }

    public func pixelParameters() -> [String: String] {
        Dictionary(compacting: [
            (DBPWideEventParameter.OptOutSubmissionFeature.dataBrokerURL, dataBrokerURL),
            (DBPWideEventParameter.OptOutSubmissionFeature.dataBrokerVersion, dataBrokerVersion),
            (DBPWideEventParameter.OptOutSubmissionFeature.submissionLatency, submissionInterval?.stringValue(.noBucketing)),
        ])
    }
}

extension OptOutSubmissionWideEventData: WideEventDataMeasuringInterval {
    public var measuredInterval: WideEvent.MeasuredInterval? {
        get { submissionInterval }
        set { submissionInterval = newValue }
    }
}
