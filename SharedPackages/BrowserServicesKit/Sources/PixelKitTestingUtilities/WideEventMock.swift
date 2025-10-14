//
//  WideEventMock.swift
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
import PixelKit
import XCTest

public final class WideEventMock: WideEventManaging {

    public var started: [WideEventData] = []
    public var updates: [WideEventData] = []
    public var completions: [(WideEventData, WideEventStatus)] = []
    public var discarded: [WideEventData] = []

    public var onUpdate: ((WideEventData) -> Void)?
    public var onComplete: ((WideEventData, WideEventStatus) -> Void)?

    public init() {}

    public func startFlow<T: WideEventData>(_ data: T) {
        started.append(data)
    }

    public func updateFlow<T: WideEventData>(_ data: T) {
        updates.append(data)
        onUpdate?(data)
    }

    public func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {
        // Try to find existing data in started or updates arrays
        let allData = (started + updates).compactMap { $0 as? T }
        guard var data = allData.first(where: { $0.globalData.id == globalID }) else {
            return
        }

        update(&data)
        updates.append(data)
    }

    public func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        completions.append((data, status))
        self.onComplete?(data, status)
        onComplete(true, nil)
    }

    public func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        completions.append((data, status))
        onComplete?(data, status)
        return true
    }

    public func discardFlow<T: WideEventData>(_ data: T) {
        discarded.append(data)
    }

    public func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? {
        return started.first { ($0 as? T)?.globalData.id == globalID } as? T
    }

    public func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] {
        return started.compactMap { $0 as? T }
    }
}
