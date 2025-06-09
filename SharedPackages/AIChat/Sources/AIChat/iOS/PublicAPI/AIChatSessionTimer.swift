//
//  AIChatSessionTimer.swift
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

#if os(iOS)
import Foundation
import UIKit

/// A protocol that defines the timing behavior for chat sessions.
///
/// Conforming types are responsible for managing a timer that tracks the duration
/// of a chat session and provides functionality to start, cancel, and check the elapsed time.
protocol AIChatSessionTiming {

    /// Initializes a new instance of a chat session timer.
    ///
    /// - Parameters:
    ///   - durationInSeconds: The duration of the timer in seconds.
    ///   - completion: A closure that is called when the timer completes its duration.
    init(durationInSeconds: TimeInterval, completion: @escaping () -> Void)

    /// Starts the timer for the chat session.
    ///
    /// This method begins the timer using the duration specified during initialization.
    func start()

    /// Cancels the timer if it is currently running.
    ///
    /// This method invalidates the timer and resets the start date.
    func cancel()

    /// Returns the elapsed time since the timer started, in minutes.
    ///
    /// - Returns: The number of minutes that have elapsed since the timer started,
    ///            or `nil` if the timer has not been started.
    func timeElapsedInMinutes() -> Int?
}

public final class AIChatSessionTimer: AIChatSessionTiming {
    private let durationInSeconds: TimeInterval
    private var timer: Timer?
    private var startDate: Date?
    private let completion: () -> Void

    /// Property to keep track of the current duration for the timer in case the app moves to the background multiple times
    private var currentDuration: TimeInterval

    public init(durationInSeconds: TimeInterval, completion: @escaping () -> Void) {
        self.durationInSeconds = durationInSeconds
        self.currentDuration = durationInSeconds
        self.completion = completion
        registerLifecycleNotifications()
    }

    private func registerLifecycleNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    public func start() {
        startDate = Date()
        start(duration: durationInSeconds)
    }

    private func start(duration: TimeInterval) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.completion()
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func appWillEnterForeground() {
        handleTimerAfterBackgrounding()
    }

    ///    This function is called when the app re-enters the foreground.
    ///    It calculates the elapsed time since the timer started and determines whether to fire the timer immediately or restart it with the remaining time.
    ///     - Fires the timer if the elapsed time is greater than or equal to the duration.
    ///     - Restarts the timer with the remaining time if the elapsed time is less.
    ///
    private func handleTimerAfterBackgrounding() {
        guard let startDate = startDate else {
            return
        }

        let elapsedTime = Date().timeIntervalSince(startDate)

        if elapsedTime >= durationInSeconds {
            timer?.fire()
        } else {
            self.currentDuration = currentDuration - elapsedTime
            start(duration: self.currentDuration)
        }
    }

    public func timeElapsedInMinutes() -> Int? {
        guard let startDate = startDate else {
            return nil
        }
        let elapsedTime = Date().timeIntervalSince(startDate)
        return Int(elapsedTime / 60.0)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cancel()
    }

}
#endif
