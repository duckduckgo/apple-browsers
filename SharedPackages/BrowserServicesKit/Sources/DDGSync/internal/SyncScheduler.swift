//
//  SyncScheduler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine

/**
 * Internal interface for sync schedulers.
 */
protocol SchedulingInternal: AnyObject, Scheduling {
    /// Used to control scheduling. If set to false, scheduler is off.
    var isEnabled: Bool { get set }
    /// Publishes events to notify Sync Queue that sync operation should be started.
    var startSyncPublisher: AnyPublisher<Void, Never> { get }
    /// Publishes events to notify Sync Queue that sync operation should be cancelled.
    var cancelSyncPublisher: AnyPublisher<Void, Never> { get }
    /// Publishes events to notify Sync Queue that sync operations can be resumed.
    var resumeSyncPublisher: AnyPublisher<Void, Never> { get }
}

final class SyncScheduler: SchedulingInternal {
    func notifyDataChanged() {
        if isEnabled {
            syncTriggerSubject.send()
        }
    }

    func notifyAppLifecycleEvent() {
        if isEnabled {
            appLifecycleEventSubject.send()
        }
    }

    func requestSyncImmediately() {
        if isEnabled {
            syncTriggerSubject.send()
        }
    }

    func cancelSyncAndSuspendSyncQueue() {
        cancelSyncSubject.send()
    }

    func resumeSyncQueue() {
        resumeSyncSubject.send()
    }

    var isEnabled: Bool = false
    let startSyncPublisher: AnyPublisher<Void, Never>
    let cancelSyncPublisher: AnyPublisher<Void, Never>
    let resumeSyncPublisher: AnyPublisher<Void, Never>

    init() {
        let throttledAppLifecycleEvents = appLifecycleEventSubject
            .throttle(for: .seconds(Const.appLifecycleEventsDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        let throttledSyncTriggerEvents = syncTriggerSubject
            .throttle(for: .seconds(Const.immediateSyncDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()
        cancelSyncPublisher = cancelSyncSubject.eraseToAnyPublisher()
        resumeSyncPublisher = resumeSyncSubject.eraseToAnyPublisher()

        startSyncCancellable = Publishers.Merge(throttledAppLifecycleEvents, throttledSyncTriggerEvents)
            .sink(receiveValue: { [weak self] _ in
                self?.startSyncSubject.send()
            })
    }

    private let appLifecycleEventSubject: PassthroughSubject<Void, Never> = .init()
    private let syncTriggerSubject: PassthroughSubject<Void, Never> = .init()
    private let startSyncSubject: PassthroughSubject<Void, Never> = .init()
    private let cancelSyncSubject: PassthroughSubject<Void, Never> = .init()
    private let resumeSyncSubject: PassthroughSubject<Void, Never> = .init()
    private var startSyncCancellable: AnyCancellable?

    enum Const {
        static let immediateSyncDebounceInterval = 1
#if DEBUG
        static let appLifecycleEventsDebounceInterval = 60
#else
        static let appLifecycleEventsDebounceInterval = 600
#endif
    }
}
