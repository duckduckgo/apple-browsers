//
//  SyncJoinReportPixel.swift
//  DuckDuckGo
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

import DDGSync
import PixelKit

struct SyncJoinReportPixel: PixelKit.Event {
    let report: PairingV2JoinReport

    var name: String {
        report.didSucceed ? "sync_setup_joiner_recovery_code_done_success" : "sync_setup_joiner_recovery_code_done_failed"
    }

    var namePrefix: PixelKitNamePrefix { .none }

    var parameters: [String: String]? {
        ["host_has_account": String(report.hostHasAccount),
         "host_kind": report.hostKind.rawValue,
         "joiner_has_account": String(report.joinerHasAccount),
         "joiner_kind": report.joinerKind.rawValue,
         "protocol_version": report.protocolVersion]
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }
}
