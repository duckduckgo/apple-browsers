//
//  SyncAuditLogBackgroundTask.swift
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
import Combine
import DDGSync
import FeatureFlags_iOS
import PrivacyConfig
import UserNotifications
import UIKit
import os.log

@MainActor
final class SyncAuditLogBackgroundTask {
    nonisolated static let identifier = "com.duckduckgo.app.syncAuditLogRefresh"
    nonisolated static let refreshInterval: TimeInterval = 3 * 60 * 60

    private let syncService: DDGSyncing
    private let featureFlagger: FeatureFlagger
    private let scheduler: BGTaskScheduling
    private let notificationCenter: NotificationCenter
    private let notificationSettings: any SyncNotificationSettingsReading
    private let application: BackgroundRefreshCapable
    private var updates: AnyCancellable?
    private var schedulingTask: Task<Void, Never>?
    private var activePoll: BackgroundPoll?
    private var isRegistered = false

    init(syncService: DDGSyncing,
         featureFlagger: FeatureFlagger,
         scheduler: BGTaskScheduling = BGTaskScheduler.shared,
         notificationCenter: NotificationCenter = .default,
         notificationSettings: (any SyncNotificationSettingsReading)? = nil,
         application: BackgroundRefreshCapable = UIApplication.shared) {
        self.syncService = syncService
        self.featureFlagger = featureFlagger
        self.scheduler = scheduler
        self.notificationCenter = notificationCenter
        self.notificationSettings = notificationSettings ?? SyncNotificationSettings()
        self.application = application
    }

    func start() {
        guard !isRegistered else { return }
        // Every permitted identifier needs a handler, even while its feature flag is off.
        isRegistered = scheduler.register(forTaskWithIdentifier: Self.identifier) { [weak self] task in
            let poll = BackgroundPoll(task: task)
            Task { @MainActor in
                guard let self else {
                    poll.finish(success: false)
                    return
                }
                self.handle(poll)
            }
        }
        guard isRegistered else {
            Logger.sync.error("Failed to register the audit-log background task")
            return
        }
        updates = Publishers.MergeMany([
            featureFlagger.updatesPublisher,
            syncService.authStatePublisher.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification).map { _ in () }.eraseToAnyPublisher(),
            notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification).map { _ in () }.eraseToAnyPublisher(),
            notificationCenter.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            notificationCenter.publisher(for: SyncNotificationSettings.didChange).map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updateScheduling() }
        updateScheduling()
    }

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.syncAuditLogBackgroundPolling)
            && featureFlagger.isFeatureOn(.syncLoginAuditLog)
            && featureFlagger.isFeatureOn(.syncLoginNotification)
            && notificationSettings.isEnabled
            && application.backgroundRefreshStatus == .available
    }

    private func notificationsAllowed() async -> Bool {
        switch await notificationSettings.authorizationStatus() {
        case .notDetermined, .provisional, .authorized:
            return true
        default:
            return false
        }
    }

    private func cancel() {
        activePoll?.cancel()
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
    }

    private func updateScheduling() {
        schedulingTask?.cancel()
        guard isEnabled else {
            cancel()
            return
        }
        schedulingTask = Task {
            let allowed = await notificationsAllowed()
            guard !Task.isCancelled else { return }
            guard allowed, isEnabled else {
                cancel()
                return
            }
            let pending = await scheduler.pendingTaskRequests()
            guard !Task.isCancelled, isEnabled else { return }
            do {
                guard try syncService.isAuditLogPollingAvailable(forAccountID: nil) else {
                    cancel()
                    return
                }
            } catch {
                // Storage may be locked. Stop current work but keep a later opportunity to retry.
                activePoll?.cancel()
                Logger.sync.error("Could not check background audit-log availability: \(String(reflecting: error), privacy: .private)")
            }
            guard !pending.contains(where: { $0.identifier == Self.identifier }) else { return }
            do {
                let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
                try scheduler.submit(request)
            } catch {
                Logger.sync.error("Failed to schedule background audit-log polling: \(String(reflecting: error), privacy: .private)")
            }
        }
    }

    private func handle(_ poll: BackgroundPoll) {
        updateScheduling()
        guard !poll.isCompleted else { return }
        guard isEnabled else {
            poll.finish(success: true)
            return
        }
        guard activePoll == nil || activePoll?.isCompleted == true else {
            poll.finish(success: true)
            return
        }
        activePoll = poll
        let work = Task {
            defer {
                if activePoll === poll { activePoll = nil }
            }
            guard isEnabled, !poll.isCompleted else {
                poll.finish(success: true)
                return
            }
            do {
                let allowed = await notificationsAllowed()
                try Task.checkCancellation()
                guard allowed, isEnabled, !poll.isCompleted else {
                    poll.finish(success: true)
                    return
                }
                _ = try await syncService.pollAuditLog()
                try Task.checkCancellation()
                poll.finish(success: true)
            } catch {
                if !(error is CancellationError) {
                    Logger.sync.error("Background audit-log polling failed: \(String(reflecting: error), privacy: .private)")
                }
                poll.finish(success: false)
            }
        }
        poll.attach(work)
    }
}

// Expiration can arrive off the main queue and must complete the system task without waiting for the network.
private final class BackgroundPoll {
    private let task: BGTaskInterface
    private let lock = NSLock()
    private var work: Task<Void, Never>?
    private var completed = false

    var isCompleted: Bool { lock.withLock { completed } }

    init(task: BGTaskInterface) {
        self.task = task
        task.expirationHandler = { [weak self] in self?.cancel() }
    }

    func attach(_ work: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            if completed { return true }
            self.work = work
            return false
        }
        if shouldCancel { work.cancel() }
    }

    func cancel() {
        complete(success: false, cancelWork: true)
    }

    func finish(success: Bool) {
        complete(success: success, cancelWork: false)
    }

    private func complete(success: Bool, cancelWork: Bool) {
        let result: (shouldComplete: Bool, work: Task<Void, Never>?) = lock.withLock {
            guard !completed else { return (false, nil) }
            completed = true
            defer { work = nil }
            return (true, work)
        }
        guard result.shouldComplete else { return }
        if cancelWork { result.work?.cancel() }
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
    }
}
