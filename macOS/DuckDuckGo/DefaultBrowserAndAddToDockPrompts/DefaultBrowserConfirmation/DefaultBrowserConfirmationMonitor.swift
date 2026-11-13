//
//  DefaultBrowserConfirmationMonitor.swift
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
import Foundation
import PixelKit

enum DefaultBrowserConfirmationSource: String {
    case winBack = "default-browser-win-back"
}

enum DefaultBrowserConfirmationCheck: String, Codable {
    /// About 5 seconds after the click.
    case afterClick = "after-click"
    /// The next time the app becomes active.
    case nextActivation = "next-activation"
    /// 24 hours after the click, or the first launch or activation after that.
    case deadline = "24h"

    fileprivate var next: DefaultBrowserConfirmationCheck? {
        switch self {
        case .afterClick: return .nextActivation
        case .nextActivation: return .deadline
        case .deadline: return nil
        }
    }
}

struct DefaultBrowserPendingConfirmation: Codable, Equatable {
    /// When the user clicked the button to set DuckDuckGo as their default browser.
    let clickDate: Date
    var nextCheck: DefaultBrowserConfirmationCheck
}

protocol DefaultBrowserConfirmationStoring: AnyObject {
    /// The click awaiting confirmation and the next check to run, or `nil` when no confirmation is pending.
    var pendingConfirmation: DefaultBrowserPendingConfirmation? { get set }
}

protocol DefaultBrowserConfirmationMonitoring: AnyObject {
    func start(clickDate: Date)
}

final class DefaultBrowserConfirmationMonitor: DefaultBrowserConfirmationMonitoring {

    private enum Event {
        case appBecameActive
        case afterClickTimerFired
        case deadlineTimerFired

        func triggers(_ check: DefaultBrowserConfirmationCheck) -> Bool {
            switch self {
            case .appBecameActive:
                return check == .nextActivation
            case .afterClickTimerFired:
                return check == .afterClick
            case .deadlineTimerFired:
                return check == .deadline
            }
        }
    }

    private let source: DefaultBrowserConfirmationSource
    private let store: DefaultBrowserConfirmationStoring
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let timerFactory: TimerCreating
    private let dateProvider: () -> Date
    private let afterClickDelay: TimeInterval
    private let deadlineInterval: TimeInterval
    private let pixelFiring: PixelFiring?

    private var pending: DefaultBrowserPendingConfirmation? {
        didSet { store.pendingConfirmation = pending }
    }
    private var afterClickTimer: TimerInterface?
    private var deadlineTimer: TimerInterface?
    private var appActiveCancellable: AnyCancellable?

    init(source: DefaultBrowserConfirmationSource,
         store: DefaultBrowserConfirmationStoring,
         defaultBrowserProvider: DefaultBrowserProvider,
         notificationCenter: NotificationCenter = .default,
         timerFactory: TimerCreating = TimerFactory(),
         dateProvider: @escaping () -> Date = Date.init,
         afterClickDelay: TimeInterval = 5,
         deadlineInterval: TimeInterval = 24 * 60 * 60,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.source = source
        self.store = store
        self.defaultBrowserProvider = defaultBrowserProvider
        self.timerFactory = timerFactory
        self.dateProvider = dateProvider
        self.afterClickDelay = afterClickDelay
        self.deadlineInterval = deadlineInterval
        self.pixelFiring = pixelFiring

        appActiveCancellable = notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handle(.appBecameActive)
            }
    }

    deinit {
        invalidateTimers()
    }

    func start(clickDate: Date) {
        let confirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .afterClick)
        scheduleChecks(for: confirmation)
    }

    func resume() {
        guard let confirmation = store.pendingConfirmation else { return }
        if isPastDeadline(confirmation) {
            evaluate(confirmation, at: .deadline)
        } else {
            scheduleChecks(for: confirmation)
        }
    }

    func cancel() {
        pending = nil
        invalidateTimers()
    }

    private func scheduleChecks(for confirmation: DefaultBrowserPendingConfirmation) {
        invalidateTimers()
        pending = confirmation

        deadlineTimer = makeTimer(after: deadline(for: confirmation).timeIntervalSince(dateProvider()), sending: .deadlineTimerFired)
        if confirmation.nextCheck == .afterClick {
            let afterClickDate = confirmation.clickDate.addingTimeInterval(afterClickDelay)
            afterClickTimer = makeTimer(after: max(0, afterClickDate.timeIntervalSince(dateProvider())), sending: .afterClickTimerFired)
        }
    }

    // MARK: - Events

    private func handle(_ event: Event) {
        guard let pending else { return }

        if isPastDeadline(pending) {
            evaluate(pending, at: .deadline)
        } else if event.triggers(pending.nextCheck) {
            evaluate(pending, at: pending.nextCheck)
        }
    }

    // MARK: - Checks

    private func deadline(for confirmation: DefaultBrowserPendingConfirmation) -> Date {
        confirmation.clickDate.addingTimeInterval(deadlineInterval)
    }

    private func isPastDeadline(_ confirmation: DefaultBrowserPendingConfirmation) -> Bool {
        dateProvider() >= deadline(for: confirmation)
    }

    private func evaluate(_ confirmation: DefaultBrowserPendingConfirmation, at check: DefaultBrowserConfirmationCheck) {
        if defaultBrowserProvider.isDefault {
            finish(with: .confirmed(source: source, check: check))
        } else if let next = check.next {
            pending = DefaultBrowserPendingConfirmation(clickDate: confirmation.clickDate, nextCheck: next)
        } else {
            finish(with: .notConfirmed(source: source))
        }
    }

    private func finish(with pixel: DefaultBrowserConfirmationPixel) {
        pending = nil
        invalidateTimers()
        pixelFiring?.fire(pixel)
    }

    // MARK: - Timers

    private func makeTimer(after interval: TimeInterval, sending event: Event) -> TimerInterface {
        timerFactory.makeTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.handle(event)
        }
    }

    private func invalidateTimers() {
        afterClickTimer?.invalidate()
        afterClickTimer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
    }
}
