//
//  SubscriptionTokenRefreshTask.swift
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

import BackgroundTasks
import Foundation
import os.log
import PixelKit
import Subscription

/// Runs `SubscriptionTokenKeepAlive` from a `BGProcessingTask`, and when the app comes to the foreground or a session starts,
/// so the subscription token is refreshed even when the app isn't opened for a long time.
final class SubscriptionTokenRefreshTask {

    /// The background task identifier. It is listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.duckduckgo.app.subscriptionTokenRefresh"

    private let keepAlive: SubscriptionTokenKeepAlive
    private let scheduler: BGTaskScheduling
    private let debugSettings: SubscriptionTokenRefreshDebugStoring?
    private let retryInterval: () -> TimeInterval
    private let pixelFiring: PixelFiring?
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter

    /// - Parameters:
    ///   - keepAlive: Decides when the token is refreshed and refreshes it.
    ///   - scheduler: Registers and submits the background task.
    ///   - debugSettings: Where each run is recorded for the debug menu. Nil records nothing.
    ///   - retryInterval: The delay before scheduling the task again when it expires before the run finishes.
    ///   - pixelFiring: Fires `SubscriptionTokenRefreshPixel` for the runs it reports.
    ///   - notificationCenter: Where sign-ins, sign-outs and debug run requests are observed, and `.subscriptionTokenRefreshDidRun` is posted.
    ///   - now: The current date.
    init(keepAlive: SubscriptionTokenKeepAlive,
         scheduler: BGTaskScheduling = BGTaskScheduler.shared,
         debugSettings: SubscriptionTokenRefreshDebugStoring? = nil,
         retryInterval: @escaping () -> TimeInterval = { SubscriptionTokenKeepAlive.defaultRetryInterval },
         pixelFiring: PixelFiring? = PixelKit.shared,
         notificationCenter: NotificationCenter = .default,
         now: @escaping () -> Date = Date.init) {
        self.keepAlive = keepAlive
        self.scheduler = scheduler
        self.debugSettings = debugSettings
        self.retryInterval = retryInterval
        self.pixelFiring = pixelFiring
        self.notificationCenter = notificationCenter
        self.now = now
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    /// Registers the background task's launch handler and starts observing sign-ins, sign-outs and debug run requests.
    /// Call once, before the app finishes launching.
    func register() {
        let registered = scheduler.register(forTaskWithIdentifier: Self.taskIdentifier) { [weak self] task in
            guard let self else {
                Logger.subscriptionTokenKeepAlive.error("Background task launched after its handler was released")
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(task)
        }
        if registered {
            Logger.subscriptionTokenKeepAlive.log("Background task registered: \(Self.taskIdentifier, privacy: .public)")
        } else {
            Logger.subscriptionTokenKeepAlive.error("Failed to register the background task \(Self.taskIdentifier, privacy: .public)")
        }

        observers.append(notificationCenter.addObserver(forName: .accountDidSignIn, object: nil, queue: nil) { [weak self] _ in
            Logger.subscriptionTokenKeepAlive.log("Sign-in observed")
            self?.refreshAndSchedule(trigger: .signIn)
        })
        observers.append(notificationCenter.addObserver(forName: .accountDidSignOut, object: nil, queue: nil) { [weak self] _ in
            Logger.subscriptionTokenKeepAlive.log("Sign-out observed")
            self?.cancelScheduledTask()
        })
        observers.append(notificationCenter.addObserver(forName: .subscriptionTokenRefreshDebugRunRequested, object: nil, queue: nil) { [weak self] _ in
            Logger.subscriptionTokenKeepAlive.log("Run requested from the debug menu")
            self?.refreshAndSchedule(trigger: .debugMenu)
        })
    }

    /// Refreshes the token if it is due, then schedules the background task for the next check, or cancels it when there is nothing to check.
    /// - Parameter trigger: What started the run, recorded for the debug menu.
    @discardableResult
    func refreshAndSchedule(trigger: SubscriptionTokenRefreshRun.Trigger = .foreground) -> Task<Void, Never> {
        Logger.subscriptionTokenKeepAlive.log("Run started, trigger: \(trigger.rawValue, privacy: .public)")
        return Task { [keepAlive] in
            let outcome = await keepAlive.refreshIfNeeded()
            let nextCheck = schedule(after: outcome)
            record(trigger: trigger, outcome: outcome, nextCheck: nextCheck)
        }
    }

    /// Runs the keep-alive for a launched background task, schedules the next one and completes `task`.
    /// When the task expires first, the refresh is cancelled and the task is scheduled again after the keep-alive's retry interval.
    @discardableResult
    func handle(_ task: BGTaskInterface) -> Task<Void, Never> {
        Logger.subscriptionTokenKeepAlive.log("Run started, trigger: \(SubscriptionTokenRefreshRun.Trigger.backgroundTask.rawValue, privacy: .public)")
        let completion = TaskCompletion(task: task)

        let work = Task { [keepAlive] in
            let outcome = await keepAlive.refreshIfNeeded()
            guard !Task.isCancelled else {
                Logger.subscriptionTokenKeepAlive.log("Background run finished after expiring, outcome \(outcome.description, privacy: .public) discarded")
                return
            }
            let nextCheck = schedule(after: outcome)
            record(trigger: .backgroundTask, outcome: outcome, nextCheck: nextCheck)
            if case .failed = outcome {
                completion.complete(success: false)
            } else {
                completion.complete(success: true)
            }
        }

        task.expirationHandler = { [weak self] in
            Logger.subscriptionTokenKeepAlive.error("Background task expired before the run finished")
            work.cancel()
            if let self {
                self.submit(earliestBeginDate: self.now().addingTimeInterval(self.retryInterval()))
                self.pixelFiring?.fire(SubscriptionTokenRefreshPixel.run(trigger: .backgroundTask, result: .expired), frequency: .standard)
            }
            completion.complete(success: false)
        }
        return work
    }

    /// Schedules or cancels the background task after `outcome`.
    /// - Returns: The date the task was scheduled for, or nil when it was cancelled.
    private func schedule(after outcome: SubscriptionTokenKeepAlive.Outcome) -> Date? {
        guard let nextCheckDate = outcome.nextCheckDate else {
            cancelScheduledTask()
            return nil
        }
        submit(earliestBeginDate: nextCheckDate)
        return nextCheckDate
    }

    private func submit(earliestBeginDate: Date) {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = earliestBeginDate

        // Background tasks can be debugged by breaking after the `submit` call, then running the following LLDB command, before resuming:
        // e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.duckduckgo.app.subscriptionTokenRefresh"]
        do {
            try scheduler.submit(request)
            Logger.subscriptionTokenKeepAlive.log("Background task scheduled for \(earliestBeginDate, privacy: .public)")
        } catch {
            Logger.subscriptionTokenKeepAlive.error("Failed to schedule the background task: \(String(describing: error), privacy: .public)")
        }
    }

    private func cancelScheduledTask() {
        scheduler.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        Logger.subscriptionTokenKeepAlive.log("Background task cancelled")
    }

    private func record(trigger: SubscriptionTokenRefreshRun.Trigger, outcome: SubscriptionTokenKeepAlive.Outcome, nextCheck: Date?) {
        Logger.subscriptionTokenKeepAlive.log("Run finished, trigger: \(trigger.rawValue, privacy: .public), outcome: \(outcome.description, privacy: .public)")
        debugSettings?.lastRun = SubscriptionTokenRefreshRun(date: now(), trigger: trigger, outcome: outcome.description, nextCheck: nextCheck)
        notificationCenter.post(name: .subscriptionTokenRefreshDidRun, object: nil)
        if let pixel = SubscriptionTokenRefreshPixel.run(trigger: trigger, outcome: outcome) {
            pixelFiring?.fire(pixel, frequency: .standard)
        }
    }
}

/// Completes a background task once, whichever of the work and the expiration handler finishes first.
private final class TaskCompletion: @unchecked Sendable {
    private let task: BGTaskInterface
    private let lock = NSLock()
    private var isCompleted = false

    init(task: BGTaskInterface) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        let shouldComplete = !isCompleted
        isCompleted = true
        lock.unlock()
        if shouldComplete {
            Logger.subscriptionTokenKeepAlive.log("Background task completed, success: \(success, privacy: .public)")
            task.setTaskCompleted(success: success)
        }
    }
}
