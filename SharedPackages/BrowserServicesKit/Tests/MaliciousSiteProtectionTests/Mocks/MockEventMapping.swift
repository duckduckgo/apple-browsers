//
//  MockEventMapping.swift
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

import Common
import Foundation
import MaliciousSiteProtection
import PixelKit

public class MockEventMapping: EventMapping<MaliciousSiteProtection.Event> {
    var events: [MaliciousSiteProtection.Event] = []
    var clientSideHitParam: String?
    #if os(iOS)
    var singleDataSetUpdatePerformanceInfos: [SingleDataSetUpdatePerformanceInfo] = []
    var singleDataSetUpdateDiskUsageInfos: [SingleDataSetUpdateDiskUsageInfo] = []
    var aggregateDataSetPerformanceInfos: [AggregateDataSetPerformanceInfo] = []
    var aggregateDataSetUpdateDiskUsageInfos: [AggregateDataSetUpdateDiskUsageInfo] = []
    #endif
    var errorParam: Error?

    public init() {
        weak var weakSelf: MockEventMapping!
        super.init { event, error, params, _ in
            weakSelf!.events.append(event)
            switch event {
            case .errorPageShown:
                weakSelf!.clientSideHitParam = params?[PixelKit.Parameters.clientSideHit]
            #if os(iOS)
            case .singleDataSetUpdatePerformance(let info):
                weakSelf!.singleDataSetUpdatePerformanceInfos.append(info)
            case .singleDataSetUpdateDiskUsage(let info):
                weakSelf!.singleDataSetUpdateDiskUsageInfos.append(info)
            case .aggregateDataSetUpdatePerformance(let info):
                weakSelf!.aggregateDataSetPerformanceInfos.append(info)
            case .aggregateDataSetUpdateDiskUsage(let info):
                weakSelf!.aggregateDataSetUpdateDiskUsageInfos.append(info)
            #endif
            default:
                break
            }
        }
        weakSelf = self
    }

}
