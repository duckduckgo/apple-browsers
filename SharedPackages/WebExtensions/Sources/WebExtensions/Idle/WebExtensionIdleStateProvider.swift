//
//  WebExtensionIdleStateProvider.swift
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

#if os(macOS)

import CoreGraphics
import Foundation

/// The values `chrome.idle` reports.
enum WebExtensionIdleState: String {
    case active
    case idle
    case locked
}

/// Answers `chrome.idle.queryState` for extension pages: `locked` while the screen is locked, `idle`
/// once the user has not touched the keyboard or mouse for the detection interval, `active` otherwise.
///
/// The lock state comes from the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// distributed notifications, so it is only known from the moment the provider is created.
final class WebExtensionIdleStateProvider {

    /// Chrome does not accept a detection interval below this, in seconds.
    static let minimumDetectionInterval: TimeInterval = 15
    static let defaultDetectionInterval: TimeInterval = 60

    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    /// Seconds since the last keyboard, mouse or trackpad event of the login session.
    static let systemSecondsSinceLastInput: () -> TimeInterval = {
        // `kCGAnyInputEventType` (`~0`) is not imported into Swift as a case of `CGEventType`.
        guard let anyInputEventType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }

    static func clamped(detectionInterval: TimeInterval) -> TimeInterval {
        detectionInterval.isFinite ? max(minimumDetectionInterval, detectionInterval.rounded(.down)) : defaultDetectionInterval
    }

    private let secondsSinceLastInput: () -> TimeInterval
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var isScreenLocked = false
    private var observers: [NSObjectProtocol] = []

    init(secondsSinceLastInput: @escaping () -> TimeInterval = WebExtensionIdleStateProvider.systemSecondsSinceLastInput,
         notificationCenter: NotificationCenter = DistributedNotificationCenter.default()) {
        self.secondsSinceLastInput = secondsSinceLastInput
        self.notificationCenter = notificationCenter
        observers = [
            (Self.screenLockedNotification, true),
            (Self.screenUnlockedNotification, false)
        ].map { name, isLocked in
            notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.setScreenLocked(isLocked)
            }
        }
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    func state(detectionInterval: TimeInterval) -> WebExtensionIdleState {
        lock.lock()
        let isLocked = isScreenLocked
        lock.unlock()

        if isLocked {
            return .locked
        }
        return secondsSinceLastInput() >= Self.clamped(detectionInterval: detectionInterval) ? .idle : .active
    }

    private func setScreenLocked(_ isLocked: Bool) {
        lock.lock()
        isScreenLocked = isLocked
        lock.unlock()
    }
}

#endif
