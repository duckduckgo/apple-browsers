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

public extension NSNotification.Name {

    static let focusModeFeatureEnabled = Notification.Name(rawValue: "com.duckduckgo.focus.mode.feature.enabled")

}

enum FocusSessionTimer {
    case twentyFive
    case fifty
    case seventyFive
    case oneHundred
    case custom(TimeInterval)

    var duration: TimeInterval {
        switch self {
        case .twentyFive:
            return 25 * 60 // 15 minutes in seconds
        case .fifty:
            return 50 * 60 // 30 minutes in seconds
        case .seventyFive:
            return 75 * 60 // 30 minutes in seconds
        case .oneHundred:
            return 100 * 60 // 1 hour in seconds
        case .custom(let duration):
            return duration
        }
    }
}

final class FocusSessionCoordinator: ObservableObject {

    static let shared = FocusSessionCoordinator() // Singleton instance

    private let notificationCenter: NotificationCenter

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

    @UserDefaultsWrapper(key: .focusModeEnabled, defaultValue: false)
    private var isFocusModeEnabled: Bool

    private init(notificationCenter: NotificationCenter = .default) {
        timeRemainingMenuItem = NSMenuItem(title: "Time remaining: --:--", action: nil, keyEquivalent: "")

        self.notificationCenter = notificationCenter
    }

    var canHaveAccessToTheFeature: Bool {
        NSApp.delegateTyped.internalUserDecider.isInternalUser
    }

    var isEnabled: Bool {
        NSApp.delegateTyped.internalUserDecider.isInternalUser && isFocusModeEnabled
    }

    func shouldBlock(url: URL) -> Bool {
        if (url.isSettingsURL || url.isDuckDuckGo || url.isDuckURLScheme) && !url.isDuckPlayer {
            return false
        }

        return true // TODO: Here we will need to check the allow list
    }

    func enableFeature() {
        if !isFocusModeEnabled {
            isFocusModeEnabled = true

            notificationCenter.post(name: .focusModeFeatureEnabled, object: nil)
        }
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
        let totalSeconds = Int(remainingTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        let timeString: String
        if hours > 0 {
            timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            timeString = String(format: "%02d:%02d", minutes, seconds)
        }

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
            menu.addItem(NSMenuItem(title: "25 minutes", action: #selector(startTwentyFiveMinutesSession), target: self))
            menu.addItem(NSMenuItem(title: "50 minutes", action: #selector(startFiftyMinutesSession), target: self))
            menu.addItem(NSMenuItem(title: "75 minutes", action: #selector(startSeventyFiveMinutessession), target: self))
            menu.addItem(NSMenuItem(title: "100 minutes", action: #selector(startOneHundredMinutesSession), target: self))
            menu.addItem(NSMenuItem(title: "Custom...", action: #selector(startCustomSession), target: self))
        }

        return menu
    }

    @objc func startTwentyFiveMinutesSession() {
        startFocusSession(session: .twentyFive)
    }

    @objc func startFiftyMinutesSession() {
        startFocusSession(session: .fifty)
    }

    @objc func startSeventyFiveMinutessession() {
        startFocusSession(session: .seventyFive)
    }

    @objc func startOneHundredMinutesSession() {
        startFocusSession(session: .oneHundred)
    }

    @objc func startCustomSession() {
        // TODO: Implement an input where the user can select the minutes
    }
}
