//
//  FocusSessionCoordinator.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

enum FocusSessionTimer {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case sixHours

    var duration: TimeInterval {
        switch self {
        case .fifteenMinutes:
            return 15 * 60 // 15 minutes in seconds
        case .thirtyMinutes:
            return 30 * 60 // 30 minutes in seconds
        case .oneHour:
            return 60 * 60 // 1 hour in seconds
        case .twoHours:
            return 2 * 60 * 60 // 2 hours in seconds
        case .fourHours:
            return 4 * 60 * 60 // 4 hours in seconds
        case .sixHours:
            return 6 * 60 * 60 // 6 hours in seconds
        }
    }
}

final class FocusSessionCoordinator: ObservableObject {

    static let shared = FocusSessionCoordinator() // Singleton instance

    @Published var isCurrentOnFocusSession: Bool = false
    private var timer: Timer?
    private var totalDuration: TimeInterval = 0
    private var remainingTime: TimeInterval = 0

    // Publisher for remaining time in mm:ss format
    private var timeRemainingSubject = PassthroughSubject<String, Never>()
    var timeRemainingPublisher: AnyPublisher<String, Never> {
        timeRemainingSubject.eraseToAnyPublisher()
    }

    private var menu = NSMenu()
    private var timeRemainingMenuItem: NSMenuItem
    private var cancellables = Set<AnyCancellable>()

    private init() {
        timeRemainingMenuItem = NSMenuItem(title: "Time remaining: --:--", action: nil, keyEquivalent: "")
    }

    var canHaveAccessToTheFeature: Bool {
        NSApp.delegateTyped.internalUserDecider.isInternalUser
    }

    var isFeatureEnabled: Bool {
        NSApp.delegateTyped.internalUserDecider.isInternalUser && true // TODO: Add if feature was enabled from about section
    }

    func shouldBlock(url: URL) -> Bool {
        if (url.isSettingsURL || url.isDuckDuckGo || url.isDuckURLScheme) && !url.isDuckPlayer {
            return false
        }

        return true // TODO: Here we will need to check the allow list
    }

    func startFocusSession(session: FocusSessionTimer) {
        isCurrentOnFocusSession = true
        totalDuration = session.duration
        remainingTime = totalDuration

        // Invalidate any existing timer before starting a new one
        timer?.invalidate()

        // Schedule a new timer to update remaining time every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRemainingTime()
        }

        RunLoop.current.add(timer!, forMode: RunLoop.Mode.common)

        // Publish the initial time remaining
        publishRemainingTime()
    }

    private func updateRemainingTime() {
        if remainingTime > 0 {
            remainingTime -= 1
            publishRemainingTime()

        } else {
            cancelFocusSession()
        }
    }

    private func publishRemainingTime() {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)
        timeRemainingSubject.send(timeString)

        // Update menu item
        timeRemainingMenuItem.title = "Time remaining: \(timeString)"
        menu.itemChanged(timeRemainingMenuItem)
    }

    @objc func cancelFocusSession() {
        isCurrentOnFocusSession = false
        timer?.invalidate() // Invalidate the timer if it's still running
        timer = nil
        remainingTime = 0
        timeRemainingMenuItem.title = "Time remaining: --:--" // Reset the menu item title
    }

    func getMenu() -> NSMenu {
        menu.removeAllItems()

        if isCurrentOnFocusSession {
            menu.addItem(timeRemainingMenuItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Cancel session", action: #selector(cancelFocusSession), target: self, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Start 15 minutes session", action: #selector(startFifteenMinutesSession), target: self))
            menu.addItem(NSMenuItem(title: "Start 30 minutes session", action: #selector(startThirtyMinutesSession), target: self))
        }

        return menu
    }

    @objc func startFifteenMinutesSession() {
        startFocusSession(session: .fifteenMinutes)
    }

    @objc func startThirtyMinutesSession() {
        startFocusSession(session: .thirtyMinutes)
    }
}
