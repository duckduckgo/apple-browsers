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

final class MockEventMapping: @unchecked Sendable {
    private let lock = NSLock()
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
    private struct RecordedEvents {
        var events: [MaliciousSiteProtection.Event] = []
        var clientSideHitParam: String?
        #if os(iOS)
        var dataSetUpdateTimeEvents: [BucketedEvent] = []
        var dataSetSizeEvents: [BucketedEvent] = []
        var dataSetLoadTimeEvents: [BucketedEvent] = []
        var aggregateUpdateTimeEvents: [AggregateEvent] = []
        var aggregateSizeEvents: [AggregateEvent] = []
        #endif
    }

    private var recorded = RecordedEvents()
    var events: [MaliciousSiteProtection.Event] { lock.withLock { recorded.events } }
    var clientSideHitParam: String? { lock.withLock { recorded.clientSideHitParam } }
    #if os(iOS)
    var dataSetUpdateTimeEvents: [BucketedEvent] { lock.withLock { recorded.dataSetUpdateTimeEvents } }
    var dataSetSizeEvents: [BucketedEvent] { lock.withLock { recorded.dataSetSizeEvents } }
    var dataSetLoadTimeEvents: [BucketedEvent] { lock.withLock { recorded.dataSetLoadTimeEvents } }
    var aggregateUpdateTimeEvents: [AggregateEvent] { lock.withLock { recorded.aggregateUpdateTimeEvents } }
    var aggregateSizeEvents: [AggregateEvent] { lock.withLock { recorded.aggregateSizeEvents } }
    #endif

    func makeMapping() -> EventMapping<MaliciousSiteProtection.Event> {
        EventMapping { [self] event, _, params, _ in
            lock.withLock { record(event, params: params) }
        }
    }

    private func record(_ event: MaliciousSiteProtection.Event, params: [String: String]?) {
        recorded.events.append(event)
        switch event {
        case .errorPageShown:
            recorded.clientSideHitParam = params?[PixelKit.Parameters.clientSideHit]
        #if os(iOS)
        case .dataSetUpdateTime(let category, let type, let bucket):
            recorded.dataSetUpdateTimeEvents.append(BucketedEvent(category: category, type: type, bucket: bucket.rawValue))
        case .dataSetSize(let category, let type, let bucket):
            recorded.dataSetSizeEvents.append(BucketedEvent(category: category, type: type, bucket: bucket.rawValue))
        case .dataSetLoadTime(let category, let type, let bucket):
            recorded.dataSetLoadTimeEvents.append(BucketedEvent(category: category, type: type, bucket: bucket.rawValue))
        case .dataSetAggregateUpdateTime(let type, let bucket):
            recorded.aggregateUpdateTimeEvents.append(AggregateEvent(type: type, bucket: bucket.rawValue))
        case .dataSetAggregateSize(let type, let bucket):
            recorded.aggregateSizeEvents.append(AggregateEvent(type: type, bucket: bucket.rawValue))
        #endif
        default:
            break
        }
    }
}
