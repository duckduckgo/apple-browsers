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
import Foundation
import os.log

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

enum DefaultBrowserConfirmationResult: Equatable {
    case confirmed(DefaultBrowserConfirmationCheck)
    case notConfirmed
}

protocol DefaultBrowserConfirmationMonitoring: AnyObject {
    func start(clickDate: Date)
}

final class DefaultBrowserConfirmationMonitor: DefaultBrowserConfirmationMonitoring {

    private enum Event {
        case appBecameActive
        case afterClickTimerFired
        case deadlineTimerFired
    }

    private let source: DefaultBrowserConfirmationSource
    private let store: DefaultBrowserConfirmationStoring
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let notificationCenter: NotificationCenter
    private let timerFactory: TimerCreating
    private let dateProvider: () -> Date
    private let afterClickDelay: TimeInterval
    private let deadlineInterval: TimeInterval
    // Temporary: lets tests read results until pixels are added, then pixel firing replaces it.
    // https://app.asana.com/1/137249556945/project/1209825025475019/task/1215996183949490
    private let report: ((DefaultBrowserConfirmationResult) -> Void)?

    private var pending: DefaultBrowserPendingConfirmation? {
        didSet { store.pendingConfirmation = pending }
    }
    private var afterClickTimer: TimerInterface?
    private var deadlineTimer: TimerInterface?
    private var observers: [NSObjectProtocol] = []

    init(source: DefaultBrowserConfirmationSource,
         store: DefaultBrowserConfirmationStoring,
         defaultBrowserProvider: DefaultBrowserProvider,
         notificationCenter: NotificationCenter = .default,
         timerFactory: TimerCreating = TimerFactory(),
         dateProvider: @escaping () -> Date = Date.init,
         afterClickDelay: TimeInterval = 5,
         deadlineInterval: TimeInterval = 24 * 60 * 60,
         report: ((DefaultBrowserConfirmationResult) -> Void)? = nil) {
        self.source = source
        self.store = store
        self.defaultBrowserProvider = defaultBrowserProvider
        self.notificationCenter = notificationCenter
        self.timerFactory = timerFactory
        self.dateProvider = dateProvider
        self.afterClickDelay = afterClickDelay
        self.deadlineInterval = deadlineInterval
        self.report = report

        observers = [
            notificationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                self?.handle(.appBecameActive)
            }
        ]
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
        invalidateTimers()
    }

    func start(clickDate: Date) {
        begin(DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .afterClick))
    }

    func resume() {
        guard let confirmation = store.pendingConfirmation else { return }
        begin(confirmation)
    }

    func cancel() {
        pending = nil
        invalidateTimers()
    }

    private func begin(_ confirmation: DefaultBrowserPendingConfirmation) {
        invalidateTimers()
        pending = confirmation
        if isPastDeadline(confirmation) {
            run(.deadline)
            return
        }
        deadlineTimer = makeTimer(after: deadline(for: confirmation).timeIntervalSince(dateProvider()), sending: .deadlineTimerFired)
        if confirmation.nextCheck == .afterClick {
            let afterClickDate = confirmation.clickDate.addingTimeInterval(afterClickDelay)
            afterClickTimer = makeTimer(after: max(0, afterClickDate.timeIntervalSince(dateProvider())), sending: .afterClickTimerFired)
        }
    }

    // MARK: - Events

    private func handle(_ event: Event) {
        if event == .afterClickTimerFired {
            afterClickTimer = nil
        }
        guard let pending else { return }
        if event == .deadlineTimerFired || isPastDeadline(pending) {
            run(.deadline)
            return
        }
        switch (event, pending.nextCheck) {
        case (.afterClickTimerFired, .afterClick):
            run(.afterClick)
        case (.appBecameActive, .nextActivation):
            run(.nextActivation)
        default:
            break
        }
    }

    // MARK: - Checks

    private func deadline(for confirmation: DefaultBrowserPendingConfirmation) -> Date {
        confirmation.clickDate.addingTimeInterval(deadlineInterval)
    }

    private func isPastDeadline(_ confirmation: DefaultBrowserPendingConfirmation) -> Bool {
        dateProvider() >= deadline(for: confirmation)
    }

    private func run(_ check: DefaultBrowserConfirmationCheck) {
        guard var confirmation = pending else { return }
        if defaultBrowserProvider.isDefault {
            finish(with: .confirmed(check))
        } else if let next = check.next {
            // Temporary: This logging will be removed when pixels are added, before release.
            // https://app.asana.com/1/137249556945/project/1209825025475019/task/1215996183949490
            Logger.general.info("Default browser confirmation (\(self.source.rawValue)): not yet confirmed, next check \(next.rawValue)")
            confirmation.nextCheck = next
            pending = confirmation
        } else {
            finish(with: .notConfirmed)
        }
    }

    private func finish(with result: DefaultBrowserConfirmationResult) {
        pending = nil
        invalidateTimers()
        if let report {
            report(result)
        } else {
            // Temporary: This logging will be replaced with pixels before release.
            // https://app.asana.com/1/137249556945/project/1209825025475019/task/1215996183949490
            Logger.general.info("Default browser confirmation (\(self.source.rawValue)): \(String(describing: result))")
        }
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
