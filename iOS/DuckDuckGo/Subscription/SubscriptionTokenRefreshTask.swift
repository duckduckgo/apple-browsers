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
import Subscription

/// Runs `SubscriptionTokenKeepAlive` from a `BGProcessingTask`, and when the app comes to the foreground or a session starts,
/// so the subscription token is refreshed even when the app isn't opened for a long time.
final class SubscriptionTokenRefreshTask {

    /// The background task identifier. It is listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.duckduckgo.app.subscriptionTokenRefresh"

    private let keepAlive: SubscriptionTokenKeepAlive
    private let scheduler: BGTaskScheduling
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter

    /// - Parameters:
    ///   - keepAlive: Decides when the token is refreshed and refreshes it.
    ///   - scheduler: Registers and submits the background task.
    ///   - notificationCenter: Where `.accountDidSignIn` and `.accountDidSignOut` are observed.
    ///   - now: The current date.
    init(keepAlive: SubscriptionTokenKeepAlive,
         scheduler: BGTaskScheduling = BGTaskScheduler.shared,
         notificationCenter: NotificationCenter = .default,
         now: @escaping () -> Date = Date.init) {
        self.keepAlive = keepAlive
        self.scheduler = scheduler
        self.notificationCenter = notificationCenter
        self.now = now
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    /// Registers the background task's launch handler and starts observing sign-ins and sign-outs.
    /// Call once, before the app finishes launching.
    func register() {
        scheduler.register(forTaskWithIdentifier: Self.taskIdentifier) { [weak self] task in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(task)
        }

        observers.append(notificationCenter.addObserver(forName: .accountDidSignIn, object: nil, queue: nil) { [weak self] _ in
            self?.refreshAndSchedule()
        })
        observers.append(notificationCenter.addObserver(forName: .accountDidSignOut, object: nil, queue: nil) { [weak self] _ in
            self?.cancelScheduledTask()
        })
    }

    /// Refreshes the token if it is due, then schedules the background task for the next check, or cancels it when there is nothing to check.
    @discardableResult
    func refreshAndSchedule() -> Task<Void, Never> {
        Task { [keepAlive] in
            let outcome = await keepAlive.refreshIfNeeded()
            schedule(after: outcome)
        }
    }

    /// Runs the keep-alive for a launched background task, schedules the next one and completes `task`.
    /// When the task expires first, the refresh is cancelled and the task is scheduled again after the keep-alive's retry interval.
    @discardableResult
    func handle(_ task: BGTaskInterface) -> Task<Void, Never> {
        Logger.subscription.log("Token keep-alive: background task started")
        let completion = TaskCompletion(task: task)

        let work = Task { [keepAlive] in
            let outcome = await keepAlive.refreshIfNeeded()
            guard !Task.isCancelled else { return }
            schedule(after: outcome)
            if case .failed = outcome {
                completion.complete(success: false)
            } else {
                completion.complete(success: true)
            }
        }

        task.expirationHandler = { [weak self] in
            Logger.subscription.error("Token keep-alive: background task expired")
            work.cancel()
            if let self {
                self.submit(earliestBeginDate: self.now().addingTimeInterval(SubscriptionTokenKeepAlive.defaultRetryInterval))
            }
            completion.complete(success: false)
        }
        return work
    }

    private func schedule(after outcome: SubscriptionTokenKeepAlive.Outcome) {
        guard let nextCheckDate = outcome.nextCheckDate else {
            cancelScheduledTask()
            return
        }
        submit(earliestBeginDate: nextCheckDate)
    }

    private func submit(earliestBeginDate: Date) {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = earliestBeginDate

        // Background tasks can be debugged by breaking after the `submit` call, then running the following LLDB command, before resuming:
        // e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.duckduckgo.app.subscriptionTokenRefresh"]
        do {
            try scheduler.submit(request)
            Logger.subscription.log("Token keep-alive: background task scheduled for \(earliestBeginDate, privacy: .public)")
        } catch {
            Logger.subscription.error("Token keep-alive: failed to schedule the background task: \(String(describing: error), privacy: .public)")
        }
    }

    private func cancelScheduledTask() {
        scheduler.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        Logger.subscription.log("Token keep-alive: background task cancelled")
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
            task.setTaskCompleted(success: success)
        }
    }
}
