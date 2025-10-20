//
//  WideEventRecorder.swift
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

public final class WideEventRecorder<Data: WideEventDataMeasuringInterval> {

    private let wideEvent: WideEventManaging
    private var wideEventData: Data
    private let queue: DispatchQueue
    private var isCompleted = false

    private init(wideEvent: WideEventManaging, wideEventData: Data, shouldStartFlow: Bool) {
        self.wideEvent = wideEvent
        self.wideEventData = wideEventData
        self.queue = DispatchQueue(label: "com.duckduckgo.wide-event-recorder.\(String(describing: Data.self))", qos: .utility)

        if shouldStartFlow {
            wideEvent.startFlow(wideEventData)
        }
    }

    public static func makeIfPossible(wideEvent: WideEventManaging?,
                                      identifier: String,
                                      sampleRate: Float,
                                      intervalStart: Date?,
                                      makeData: (WideEventGlobalData, WideEvent.MeasuredInterval) -> Data) -> WideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: identifier, sampleRate: sampleRate)
        let interval = WideEvent.MeasuredInterval(start: intervalStart, end: nil)
        let data = makeData(global, interval)

        return WideEventRecorder(wideEvent: wideEvent,
                                 wideEventData: data,
                                 shouldStartFlow: true)
    }

    public static func resumeIfPossible(wideEvent: WideEventManaging?,
                                        identifier: String) -> WideEventRecorder? {
        guard let wideEvent,
              let existing: Data = wideEvent.getFlowData(Data.self, globalID: identifier) else {
            return nil
        }

        return WideEventRecorder(wideEvent: wideEvent,
                                 wideEventData: existing,
                                 shouldStartFlow: false)
    }

    @discardableResult
    public static func startIfPossible(wideEvent: WideEventManaging?,
                                       identifier: String,
                                       sampleRate: Float,
                                       intervalStartProvider: () -> Date?,
                                       makeData: (WideEventGlobalData, WideEvent.MeasuredInterval) -> Data) -> WideEventRecorder? {
        if let recorder = resumeIfPossible(wideEvent: wideEvent, identifier: identifier) {
            return recorder
        }

        let intervalStart = intervalStartProvider()

        return makeIfPossible(wideEvent: wideEvent,
                              identifier: identifier,
                              sampleRate: sampleRate,
                              intervalStart: intervalStart,
                              makeData: makeData)
    }

    private func completeInternal(status: WideEventStatus) {
        guard !isCompleted else { return }
        isCompleted = true

        Task {
            _ = try? await wideEvent.completeFlow(wideEventData, status: status)
        }
    }

    public func markCompleted(at date: Date, invalidIntervalReason: String? = nil) {
        queue.async {
            if self.wideEventData.measuredInterval == nil || self.wideEventData.measuredInterval?.start == nil {
                self.completeInternal(status: .success(reason: invalidIntervalReason))
            } else {
                self.wideEventData.measuredInterval?.end = date
                self.wideEvent.updateFlow(self.wideEventData)
                self.completeInternal(status: .success)
            }
        }
    }
}
