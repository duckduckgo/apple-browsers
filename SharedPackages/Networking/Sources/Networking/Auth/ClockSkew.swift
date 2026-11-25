//
//  ClockSkew.swift
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
import os.log
import FoundationExtensions

/// How far the device clock is from the auth server's clock, in buckets.
public enum ClockSkew: String, Codable, CaseIterable {
    /// The device clock is within 5 minutes of the server's.
    case within5Minutes = "within_5m"
    /// The device clock is 5 minutes to 1 hour ahead of the server's.
    case ahead5MinutesTo1Hour = "ahead_5m_1h"
    /// The device clock is 1 hour to 1 day ahead of the server's.
    case ahead1HourTo1Day = "ahead_1h_1d"
    /// The device clock is more than 1 day ahead of the server's.
    case aheadOver1Day = "ahead_over_1d"
    /// The device clock is 5 minutes to 1 hour behind the server's.
    case behind5MinutesTo1Hour = "behind_5m_1h"
    /// The device clock is 1 hour to 1 day behind the server's.
    case behind1HourTo1Day = "behind_1h_1d"
    /// The device clock is more than 1 day behind the server's.
    case behindOver1Day = "behind_over_1d"

    /// - Parameter offset: The device time minus the server time, in seconds. Positive when the device clock is ahead.
    public init(offset: TimeInterval) {
        let magnitude = abs(offset)
        let ahead = offset > 0
        switch magnitude {
        case ..<TimeInterval.minutes(5):
            self = .within5Minutes
        case ..<TimeInterval.hours(1):
            self = ahead ? .ahead5MinutesTo1Hour : .behind5MinutesTo1Hour
        case ..<TimeInterval.days(1):
            self = ahead ? .ahead1HourTo1Day : .behind1HourTo1Day
        default:
            self = ahead ? .aheadOver1Day : .behindOver1Day
        }
    }

    /// Whether the device clock is more than 5 minutes from the server's.
    public var isSkewed: Bool {
        self != .within5Minutes
    }
}

/// Measures the device clock against the auth server's, from the `Date` header of the server's responses.
public final class ClockSkewMonitor {

    /// The monitor the auth service and the subscription manager share by default, one per process.
    public static let shared = ClockSkewMonitor()

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private let now: () -> Date
    private let lock = NSLock()
    private var lastMeasurement: ClockSkew?

    /// - Parameter now: The device's current date.
    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// The last measured skew, or nil when no server response has been measured since launch.
    public var current: ClockSkew? {
        lock.lock()
        defer { lock.unlock() }
        return lastMeasurement
    }

    /// Measures the skew from the `Date` header of a response the server has just sent.
    /// - Parameter httpResponse: The response just received from the server.
    /// - Returns: The measured skew, or nil when the response has no valid `Date` header.
    @discardableResult
    public func measure(_ httpResponse: HTTPURLResponse) -> ClockSkew? {
        guard let header = httpResponse.value(forHTTPHeaderField: "Date"),
              let serverDate = Self.httpDateFormatter.date(from: header) else {
            return nil
        }
        return measure(serverDate: serverDate)
    }

    /// Measures the skew from the server's time when it sent a response.
    /// - Parameter serverDate: The server's time when it sent the response just received.
    /// - Returns: The measured skew.
    @discardableResult
    public func measure(serverDate: Date) -> ClockSkew {
        let skew = ClockSkew(offset: now().timeIntervalSince(serverDate))
        lock.lock()
        lastMeasurement = skew
        lock.unlock()
        if skew.isSkewed {
            Logger.OAuth.log("The device clock is skewed from the auth server's: \(skew.rawValue, privacy: .public)")
        }
        return skew
    }
}
