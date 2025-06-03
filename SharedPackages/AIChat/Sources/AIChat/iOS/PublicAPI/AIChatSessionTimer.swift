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

/// A protocol that defines the timing behavior for chat sessions.
///
/// Conforming types are responsible for managing a timer that tracks the duration
/// of a chat session and provides functionality to start, cancel, and check the elapsed time.
protocol AIChatSessionTiming {

    /// Starts the timer for the chat session.
    ///
    /// - Parameter completion: A closure that is called when the timer completes its duration.
    func start(completion: @escaping () -> Void)

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

    public init(durationInSeconds: TimeInterval) {
        self.durationInSeconds = durationInSeconds
    }

    public func start(completion: @escaping () -> Void) {
        cancel()
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: durationInSeconds, repeats: false) { _ in
            completion()
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
        startDate = nil
    }

    public func timeElapsedInMinutes() -> Int? {
        guard let startDate = startDate else {
            return nil
        }
        let elapsedTime = Date().timeIntervalSince(startDate)
        return Int(elapsedTime / 60.0)
    }

    deinit {
        cancel()
    }
}
#endif
