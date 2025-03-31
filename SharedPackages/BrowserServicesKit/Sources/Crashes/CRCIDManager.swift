//
//  CRCIDManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Persistence
import os.log

/// Cohort identifier used exclusively to distinguish systemic crashes, only after the user opts in to send them.
/// Its purpose is strictly limited to improving the reliability of crash reporting and is never used elsewhere.
public class CRCIDManager {
    static let crcidKey = "CRCIDManager.crcidKey"
    var store: KeyValueStoring

    public init(store: KeyValueStoring = UserDefaults.standard) {
        self.store = store
    }

    public func handleCrashSenderResult(result: Result<Data?, Error>, response: HTTPURLResponse?) {
        switch result {
        case .success:
            Logger.general.debug("Crash Collection - Sending Crash Report: succeeded")
            if let receivedCRCID = response?.allHeaderFields[CrashReportSender.httpHeaderCRCID] as? String {
                if crcid != receivedCRCID {
                    Logger.general.debug("Crash Collection - Received new value for CRCID: \(receivedCRCID), setting local crcid value")
                    crcid =  receivedCRCID
                } else {
                    Logger.general.debug("Crash Collection - Received matching value for CRCID: \(receivedCRCID), no update necessary")
                }
            } else {
                Logger.general.debug("Crash Collection - No value for CRCID header: \(CRCIDManager.crcidKey), clearing local crcid value if present")
                crcid = ""
            }
        case .failure(let failure):
            Logger.general.debug("Crash Collection - Sending Crash Report: failed (\(failure))")
        }
    }

    public var crcid: String? {
        get {
            return self.store.object(forKey: CRCIDManager.crcidKey) as? String
        }

        set {
            store.set(newValue, forKey: CRCIDManager.crcidKey)
        }
    }
}
