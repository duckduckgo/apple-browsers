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
    #if os(iOS)
    struct BucketedEvent: Equatable {
        let category: ThreatKind
        let type: DataManager.StoredDataType.Kind
        let bucket: String
    }
    struct AggregateEvent: Equatable {
        let type: DataManager.StoredDataType.Kind
        let bucket: String
    }
    #endif
    var events: [MaliciousSiteProtection.Event] = []
    var clientSideHitParam: String?
    #if os(iOS)
    var dataSetUpdateTimeEvents: [BucketedEvent] = []
    var dataSetSizeEvents: [BucketedEvent] = []
    var aggregateUpdateTimeEvents: [AggregateEvent] = []
    var aggregateSizeEvents: [AggregateEvent] = []
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
            case .dataSetUpdateTime(let category, let type, let bucket):
                weakSelf!.dataSetUpdateTimeEvents.append(BucketedEvent(category: category, type: type, bucket: bucket.rawValue))
            case .dataSetSize(let category, let type, let bucket):
                weakSelf!.dataSetSizeEvents.append(BucketedEvent(category: category, type: type, bucket: bucket.rawValue))
            case .dataSetAggregateUpdateTime(let type, let bucket):
                weakSelf!.aggregateUpdateTimeEvents.append(AggregateEvent(type: type, bucket: bucket.rawValue))
            case .dataSetAggregateSize(let type, let bucket):
                weakSelf!.aggregateSizeEvents.append(AggregateEvent(type: type, bucket: bucket.rawValue))
            #endif
            default:
                break
            }
        }
        weakSelf = self
    }

}
