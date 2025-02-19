//
//  Watchdog.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

final class Watchdog {
    private var timer: DispatchSourceTimer?
    private var lastMainThreadCheck: Date
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
        self.lastMainThreadCheck = Date()
    }

    func start() {
        // Create a DispatchSourceTimer to monitor for responsiveness
        let queue = DispatchQueue.global(qos: .background)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.setEventHandler { [weak self] in
            self?.checkMainThreadResponsiveness()
        }
        timer?.schedule(deadline: .now(), repeating: DispatchTimeInterval.seconds(2))  // Check every 2 seconds
        timer?.resume()

        // Start monitoring the main thread with longer intervals
        DispatchQueue.main.async {
            self.startMainThreadHeartbeat()
        }
    }

    func stop() {
        timer?.cancel()
    }

    // This method simulates the heartbeat from the main thread
    private func startMainThreadHeartbeat() {
        // Reset the last check time periodically (e.g., every 2 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // 2-second heartbeat
            self.lastMainThreadCheck = Date()
            self.startMainThreadHeartbeat()  // Keep the heartbeat running
        }
    }

    private func checkMainThreadResponsiveness() {
        // If the last heartbeat was too long ago, kill the app
        if Date().timeIntervalSince(lastMainThreadCheck) > timeout {
            print("Main thread is unresponsive! Killing the app.")
            killApp()
        }
    }

    private func killApp() {
        // Terminate the app
        let pid = getpid()
        kill(pid, SIGKILL)
    }
}
