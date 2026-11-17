//
//  CPMInterruptionObserver.swift
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

import Combine
import ConcurrencyExtensions
import Foundation
import os.log
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Tells the health monitor when the process may stop running, so waits do not count suspended time.
///
/// iOS suspends the app after it enters the background; macOS stops it while the system sleeps.
/// Merely becoming inactive does not stop either, so it is not an interruption.
/// Recovery gets a separate opportunity when iOS becomes active or macOS wakes.
///
/// Both platforms post these on the main thread, and the handler runs inside the post: a deferred
/// handler could run only after the system has already gone to sleep.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMInterruptionObserver {

    private var subscriptions = Set<AnyCancellable>()

    /// Observes the production notifications of the current platform.
    convenience init(monitor: CPMMessagingHealthMonitoring,
                     onRecoveryReady: @escaping @MainActor () -> Void = {}) {
#if os(iOS)
        self.init(monitor: monitor,
                  center: .default,
                  began: UIApplication.didEnterBackgroundNotification,
                  ended: UIApplication.willEnterForegroundNotification,
                  recoveryReady: UIApplication.didBecomeActiveNotification,
                  onRecoveryReady: onRecoveryReady)
#else
        self.init(monitor: monitor,
                  center: NSWorkspace.shared.notificationCenter,
                  began: NSWorkspace.willSleepNotification,
                  ended: NSWorkspace.didWakeNotification,
                  onRecoveryReady: onRecoveryReady)
#endif
    }

    init(monitor: CPMMessagingHealthMonitoring, center: NotificationCenter, began: Notification.Name, ended: Notification.Name,
         recoveryReady: Notification.Name? = nil, onRecoveryReady: @escaping @MainActor () -> Void = {}) {
        center.publisher(for: began)
            .sink { [weak monitor] _ in
                os_log("Interruption began", log: .default, type: .debug)
                DispatchQueue.main.asyncOrNow { monitor?.handle(.interruptionBegan) }
            }
            .store(in: &subscriptions)
        center.publisher(for: ended)
            .sink { [weak monitor] _ in
                os_log("Interruption ended", log: .default, type: .debug)
                DispatchQueue.main.asyncOrNow {
                    monitor?.handle(.interruptionEnded)
                    if recoveryReady == nil || recoveryReady == ended { onRecoveryReady() }
                }
            }
            .store(in: &subscriptions)
        // iOS willEnterForeground can still see applicationState == .background. Wait until active
        // for recovery, while the health monitor resumes its clocks at the earlier notification.
        if let recoveryReady, recoveryReady != ended {
            center.publisher(for: recoveryReady)
                .sink { _ in DispatchQueue.main.asyncOrNow { onRecoveryReady() } }
                .store(in: &subscriptions)
        }
    }
}
