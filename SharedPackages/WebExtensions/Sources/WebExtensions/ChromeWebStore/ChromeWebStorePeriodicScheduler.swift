//
//  ChromeWebStorePeriodicScheduler.swift
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

import Foundation

protocol ChromeWebStorePeriodicScheduling: AnyObject {
    func schedule(_ operation: @escaping @Sendable () async -> Void)
    func invalidate()
}

/// Owned by the update coordinator. macOS chooses an energy-efficient time for periodic checks.
@available(macOS 15.4, iOS 18.4, *)
final class ChromeWebStorePeriodicScheduler: ChromeWebStorePeriodicScheduling {
#if os(macOS)
    private static let activityIdentifier = "com.duckduckgo.browser.web-extension-update-discovery"
    private static let toleranceFraction = 0.2
    private let activity: NSBackgroundActivityScheduler

    init(interval: TimeInterval,
         activity: NSBackgroundActivityScheduler = NSBackgroundActivityScheduler(identifier: ChromeWebStorePeriodicScheduler.activityIdentifier)) {
        self.activity = activity
        activity.interval = interval
        activity.tolerance = interval * Self.toleranceFraction
        activity.repeats = true
        activity.qualityOfService = .background
    }

    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        activity.schedule { completion in
            Task(priority: .background) {
                await operation()
                completion(.finished)
            }
        }
    }

    func invalidate() {
        activity.invalidate()
    }
#else
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func schedule(_ operation: @escaping @Sendable () async -> Void) {
        task?.cancel()
        let interval = interval
        task = Task(priority: .utility) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await operation()
            }
        }
    }

    func invalidate() {
        task?.cancel()
        task = nil
    }
#endif

    deinit {
        invalidate()
    }
}
