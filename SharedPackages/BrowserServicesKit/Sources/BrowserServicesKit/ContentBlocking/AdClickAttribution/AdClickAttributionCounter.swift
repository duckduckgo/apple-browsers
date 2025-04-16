//
//  AdClickAttributionCounter.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

/// This class aggregates detected Ad Attributions on a websites and stores that count over a certain time interval.
public class AdClickAttributionCounter {

    public enum Constant {

        public static let pageLoadsCountKey = "AdClickAttributionCounter_Count"
        public static let lastSendAtKey = "AdClickAttributionCounter_Date"
        public static let sendInterval: Double = 60 * 60 * 24 // 24 hours

    }

    private let store: KeyValueStoring
    private let onSend: (_ count: Int) -> Void
    private let sendInterval: Double

    public init(store: KeyValueStoring = AdClickAttributionCounterStore(),
                sendInterval: Double = Constant.sendInterval,
                onSendRequest: @escaping (_ count: Int) -> Void) {
        self.store = store
        self.onSend = onSendRequest
        self.sendInterval = sendInterval
    }

    public func onAttributionActive(currentTime: Date = Date()) {
        save(pageLoadsCount: pageLoadsCount + 1)
        sendEventsIfNeeded(currentTime: currentTime)
    }

    public func sendEventsIfNeeded(currentTime: Date = Date()) {
        guard let lastSendAt else {
            save(lastSendAt: currentTime)
            return
        }

        if abs(currentTime.timeIntervalSince(lastSendAt)) > sendInterval {
            if pageLoadsCount > 0 {
                onSend(pageLoadsCount)
                resetStats(currentTime: currentTime)
            } else {
                save(lastSendAt: currentTime)
            }
        }
    }

    private func resetStats(currentTime: Date = Date()) {
        save(pageLoadsCount: 0)
        save(lastSendAt: currentTime)
    }

    // MARK: - Store

    private var lastSendAt: Date? { store.object(forKey: Constant.lastSendAtKey) as? Date }
    private var pageLoadsCount: Int { store.object(forKey: Constant.pageLoadsCountKey) as? Int ?? 0 }

    private func save(lastSendAt: Date) {
        store.set(lastSendAt, forKey: Constant.lastSendAtKey)
    }

    private func save(pageLoadsCount: Int) {
        store.set(pageLoadsCount, forKey: Constant.pageLoadsCountKey)
    }

}
