//
//  PageRefreshMonitor.swift
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
import Common

public extension Notification.Name {

    static let pageRefreshMonitorDidDetectRefreshPattern = Notification.Name("com.duckduckgo.app.pageRefreshMonitorDidDetectRefreshPattern")

}

public protocol PageRefreshMonitoring {

    func register(for url: URL, date: Date)
    func register(for url: URL)

}

public extension PageRefreshMonitoring {

    func register(for url: URL) {
        register(for: url, date: Date())
    }

}

/// Monitors page refresh events for a specific URL without storing URLs or any personally identifiable information.
///
/// Triggers `onDidDetectRefreshPattern` and posts a `pageRefreshMonitorDidDetectRefreshPattern` notification
/// if three refreshes occur within a 20-second window.
/// Triggers `onDidDetectRefreshPattern`
/// if two refresh occur within a 12-second window
public final class PageRefreshMonitor: PageRefreshMonitoring {

    public typealias NumberOfRefreshes = Int
    private let onDidDetectRefreshPattern: (_ numberOfRefreshes: NumberOfRefreshes) -> Void
    private var lastRefreshedURL: URL?

    public init(onDidDetectRefreshPattern: @escaping (NumberOfRefreshes) -> Void) {
        self.onDidDetectRefreshPattern = onDidDetectRefreshPattern
    }

    var refreshTimestamps2x: [Date] = []
    var refreshTimestamps3x: [Date] = []

    public func register(for url: URL, date: Date = Date()) {
        resetIfURLChanged(to: url)

        // Add the new refresh timestamp
        refreshTimestamps2x.append(date)
        refreshTimestamps3x.append(date)

        let refreshesInLast12Secs = refreshTimestamps2x.filter { date.timeIntervalSince($0) < 12.0 }
        let refreshesInLast20Secs = refreshTimestamps3x.filter { date.timeIntervalSince($0) < 20.0 }

        // Trigger detection if two refreshes occurred within 12 seconds
        if refreshesInLast12Secs.count > 1 {
            onDidDetectRefreshPattern(2)
            refreshTimestamps2x.removeAll()
        }
        // Trigger detection if three refreshes occurred within 20 seconds
        if refreshesInLast20Secs.count > 2 {
            onDidDetectRefreshPattern(3)
            NotificationCenter.default.post(name: .pageRefreshMonitorDidDetectRefreshPattern, object: self)
            refreshTimestamps3x.removeAll() // Reset timestamps after detection
        }
    }

    private func resetIfURLChanged(to newURL: URL) {
        if lastRefreshedURL != newURL {
            refreshTimestamps2x.removeAll()
            refreshTimestamps3x.removeAll()
            lastRefreshedURL = newURL
        }
    }

}
