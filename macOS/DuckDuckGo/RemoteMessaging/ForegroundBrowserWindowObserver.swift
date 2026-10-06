//
//  ForegroundBrowserWindowObserver.swift
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

/// Observes the foreground visibility conditions shared by browser surfaces that record impressions.
final class ForegroundBrowserWindowObserver {
    private weak var window: NSWindow?
    private let changesSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(window: NSWindow) {
        self.window = window
        let windowChanges = NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification))
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResignMainNotification))
            .filter { [weak self] notification in self?.isNotificationForObservedWindow(notification) == true }
        let appChanges = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
        windowChanges
            .merge(with: appChanges)
            .sink { [weak self] _ in self?.changesSubject.send() }
            .store(in: &cancellables)
    }

    private func isNotificationForObservedWindow(_ notification: Notification) -> Bool {
        guard let window else { return false }
        return (notification.object as? NSWindow) === window
    }

    var isEligible: Bool {
        guard let window else { return false }
        return Self.isEligible(window: window)
    }

    static func isEligible(window: NSWindow) -> Bool {
        NSApp.isActive && window.isMainWindow && window.isVisible && window.occlusionState.contains(.visible)
    }

    var changes: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }
}
