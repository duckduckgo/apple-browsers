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

public final class Watchdog {
    private var lastMainThreadCheck = Date()
    private let timeout: TimeInterval
    private var isMonitoring: Bool = false
    private let monitorQueue = DispatchQueue(label: "com.watchdog.monitorQueue", qos: .background)

    public var isRunning: Bool {
        return isMonitoring
    }

    public init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
    }

    public func start() {
        lastMainThreadCheck = Date()
        // Start monitoring the main thread from a background thread
        startMainThreadHeartbeatInBackground()
    }

    public func stop() {
        monitorQueue.async { [weak self] in
            self?.isMonitoring = false
        }
    }

    // This method will simulate the heartbeat for the main thread in the background
    private func startMainThreadHeartbeatInBackground() {
        // Recursively check every 2 seconds from a background thread
        monitorQueue.async { [weak self] in
            guard let self = self else { return }
            self.isMonitoring = true

            while self.isMonitoring {
                // Check the main thread's responsiveness
                self.checkMainThreadResponsiveness()

                // Simulate the heartbeat every 2 seconds, ensuring it doesn't block the main thread
                DispatchQueue.main.async {
                    self.lastMainThreadCheck = Date()
                }

                // Recursively call itself after a delay, but on the background queue
                usleep(2 * 1000000)  // Sleep for 2 seconds before checking again
            }
        }
    }

    private func checkMainThreadResponsiveness() {
        // If the last heartbeat was too long ago, kill the app
        if Date().timeIntervalSince(lastMainThreadCheck) > timeout {
            killApp()
        }
    }

    private func killApp() {
        fatalError("Main thread is unresponsive! Killing the app.")
    }
}
