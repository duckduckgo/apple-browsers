//
//  UsageTimeMonitor.swift
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

import AppKit
import Combine
import os.log
import PixelKit

/// AppKit supplies ordered events on the main thread. The worker owns the tracker and the file store.
final class UsageTimeMonitor {
    private let queue = DispatchQueue(label: "com.duckduckgo.usage-time")
    private let now: () -> UsageTimeReading
    private let store: UsageDayStore
    private var tracker = UsageTimeTracker()
    private var lastReportCheck: TimeInterval?
    private var ticksSinceReportCheck = 0
    private var inputMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: AnyCancellable?
#if DEBUG
    @MainActor private var previewTimer: AnyCancellable?

    @MainActor var isPreviewingEvery30Seconds: Bool { previewTimer != nil }

    @MainActor
    func togglePreviewEvery30Seconds(
        ticks: AnyPublisher<Date, Never> = Timer.publish(every: 30, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
    ) {
        if isPreviewingEvery30Seconds {
            previewTimer = nil
        } else {
            previewTimer = ticks.sink { [weak self] _ in self?.preview() }
        }
    }
#endif

    init(directory: URL, now: @escaping () -> UsageTimeReading = UsageTimeReading.now, pixelFiring: PixelKitFiring? = PixelKit.shared) {
        self.now = now
        store = UsageDayStore(directory: directory) {
            pixelFiring?.fire(UsageTimeStoreDiscardedPixel(), frequency: .standard)
        }
    }

    @MainActor
    func start() {
        guard timer == nil else { return }
        handle(.start)
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                           .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if NSApp.isActive, event.window?.windowController is MainWindowController {
                self?.handle(.input)
            }
            return event
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.handle(.stop) }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handle(.start)
                self?.scheduleCheckpoints()
            }.store(in: &subscriptions)
        scheduleCheckpoints()
    }

    @MainActor
    private func scheduleCheckpoints() {
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.handle(.checkpoint) }
    }

    func handle(_ event: UsageTimeTracker.Event) {
        let reading = now()
        queue.async { self.process(event, at: reading) }
    }

    private func process(_ event: UsageTimeTracker.Event, at reading: UsageTimeReading) {
        let increments = tracker.record(event, at: reading)
        guard !increments.isEmpty else { return }
        let newDay = store.add(increments)
        if event == .checkpoint { ticksSinceReportCheck += 1 }
        let intervalElapsed = reading.uptime - (lastReportCheck ?? 0) >= 300
        let check = event == .start || (event == .checkpoint && (ticksSinceReportCheck >= 5 || intervalElapsed))
        if check {
            lastReportCheck = reading.uptime
            ticksSinceReportCheck = 0
        }
        guard newDay || check || event == .checkpoint || event == .stop else { return }
        do {
            try store.restore()
            let deliveries = try store.checkpoint(at: reading.date, finalize: check ? { $0.reportIfEligible(asOf: reading.date) } : nil)
            for delivery in deliveries {
                log(delivery.payload, preview: false)
            }
        } catch {
            Logger.general.error("Usage-time checkpoint failed")
        }
    }

    @MainActor
    func stopForQuit() {
#if DEBUG
        previewTimer = nil
#endif
        timer = nil
        subscriptions.removeAll()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        let reading = now()
        queue.sync {
            store.add(tracker.record(.stop, at: reading))
            do {
                try store.checkpoint(at: reading.date)
            } catch {
                Logger.general.error("Usage-time quit checkpoint failed")
            }
        }
    }

    func preview() {
        let reading = now()
        queue.async {
            var snapshot = self.tracker
            let today = UsageTimeTracker.calendar.startOfDay(for: reading.date)
            var record = self.store.days[today] ?? UsageDayRecord(firstSignal: reading.date)
            for increment in snapshot.record(.checkpoint, at: reading)
            where UsageTimeTracker.calendar.isDate(increment.start, inSameDayAs: today) {
                record.add(open: increment.open, active: increment.active)
            }
            self.log(DailyUsagePayload(record: record, asOf: reading.date), preview: true)
        }
    }

    private func log(_ payload: DailyUsagePayload, preview: Bool) {
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return }
        if preview {
            Logger.general.notice("Usage time preview: \(json, privacy: .public)")
        } else {
            Logger.general.notice("m_mac_usage_time_daily \(json, privacy: .public)")
        }
    }
}
