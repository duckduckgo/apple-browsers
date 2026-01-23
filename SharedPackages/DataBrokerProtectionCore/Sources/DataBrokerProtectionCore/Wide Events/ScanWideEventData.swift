//
//  ScanWideEventData.swift
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

public final class ScanWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "pir_scan_attempt",
        featureName: "pir-scan-attempt",
        mobileMetaType: "ios-pir-scan-attempt",
        desktopMetaType: "macos-pir-scan-attempt"
    )

    public enum AttemptType: String, Codable {
        case newScan = "new-data"
        case maintenanceScan = "regular-check"
        case confirmOptOutScan = "removal-verification"
    }

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var dataBrokerURL: String
    public var dataBrokerVersion: String?
    public var attemptType: AttemptType
    public var attemptNumber: Int
    public var scanInterval: WideEvent.MeasuredInterval?

    public var errorData: WideEventErrorData?

    public init(globalData: WideEventGlobalData,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                dataBrokerURL: String,
                dataBrokerVersion: String?,
                attemptType: AttemptType,
                attemptNumber: Int,
                scanInterval: WideEvent.MeasuredInterval) {
        self.globalData = globalData
        self.contextData = contextData
        self.appData = appData
        self.dataBrokerURL = dataBrokerURL
        self.dataBrokerVersion = dataBrokerVersion
        self.attemptType = attemptType
        self.attemptNumber = attemptNumber
        self.scanInterval = scanInterval
    }
}

extension ScanWideEventData {
    public func pixelParameters() -> [String: String] {
        Dictionary(compacting: [
            (DBPWideEventParameter.ScanFeature.dataBrokerURL, dataBrokerURL),
            (DBPWideEventParameter.ScanFeature.dataBrokerVersion, dataBrokerVersion),
            (DBPWideEventParameter.ScanFeature.attemptType, attemptType.rawValue),
            (DBPWideEventParameter.ScanFeature.attemptNumber, String(attemptNumber)),
            (DBPWideEventParameter.ScanFeature.scanLatency, scanInterval?.stringValue(.noBucketing)),
        ])
    }
}

extension ScanWideEventData: WideEventDataMeasuringInterval {
    public var measuredInterval: WideEvent.MeasuredInterval? {
        get { scanInterval }
        set { scanInterval = newValue }
    }
}
