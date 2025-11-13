//
//  AttributedMetricDataStorage.swift
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
import Common

/// Protocol for storing attributed metric data with rolling daily counters.
public protocol AttributedMetricDataStoring {

    /// App installation date for attribution calculations.
    var installDate: Date? { get set }
    /// Last calculated retention threshold for privacy-preserving metrics.
    var lastRetentionThreshold: QuantisedTimePast? { get set }

    /// Rolling 8-day counter for search events.
    var search8Days: RollingEightDaysInt { get set }
    /// Rolling 8-day counter for ad click events.
    var adClick8Days: RollingEightDaysInt { get set }
    /// Rolling 8-day counter for Duck AI chat events.
    var duckAIChat8Days: RollingEightDaysInt { get set }

    /// Date when user purchased the Subscription
    var subscriptionDate: Date? { get set }
    var subscriptionFreeTrialFired: Bool { get set }
    var subscriptionMonth1Fired: Bool { get set }

    /// Removes all stored metric data.
    func removeAll()
}

public enum DataStorageError: DDGError {
    case encodingFailed(Error)
    case decodingFailed(Error)

    public var description: String {
        switch self {
        case .encodingFailed(let error):
            "Encoding failed: \(error)"
        case .decodingFailed(let error):
            "Decoding failed: \(error)"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.attributedmetric.datastorage" }

    public var errorCode: Int {
        switch self {
        case .encodingFailed:
            return 16400
        case .decodingFailed:
            return 16401
        }
    }

    /// Compares two DataStorageError instances by their error type and underlying error.
    public static func == (lhs: DataStorageError, rhs: DataStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.encodingFailed(let lhsError), .encodingFailed(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.decodingFailed(let lhsError), .decodingFailed(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }
}

/// UserDefaults-backed implementation for storing attributed metric data.
public final class AttributedMetricDataStorage: AttributedMetricDataStoring {

    private let userDefaults: UserDefaults
    private let errorHandler: AttributedMetricErrorHandler

    public init(userDefaults: UserDefaults, errorHandler: AttributedMetricErrorHandler) {
        self.userDefaults = userDefaults
        self.errorHandler = errorHandler
    }

    /// UserDefaults keys for storing metric data.
    enum StorageKey: String, CaseIterable {

        case installDate

        // retention
        case lastRetentionThreshold
        case search8Days
        case adClick8Days
        case duckAIChat8Days
        case subscriptionDate
        case subscriptionFreeTrial
        case subscriptionMonth1
    }

    // MARK: - Utilities

    /// Remove all data stored in UserDefaults
    public func removeAll() {
        for key in StorageKey.allCases {
            userDefaults.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: - Coding

    /// JSON encodes and stores a Codable object to UserDefaults.
    func encode(_ object: Codable, to userDefaults: UserDefaults, key: StorageKey) {
        do {
            let data = try JSONEncoder().encode(object)
            userDefaults.set(data, forKey: key.rawValue)
        } catch {
            errorHandler.fire(DataStorageError.encodingFailed(error))
        }
    }

    /// Retrieves and JSON decodes a Codable object from UserDefaults.
    func decode<T: Codable>(from userDefaults: UserDefaults, key: StorageKey) -> T? {
        guard let data = userDefaults.data(forKey: key.rawValue) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            errorHandler.fire(DataStorageError.decodingFailed(error))
            return nil
        }
    }

    // MARK: - Retention

    public var installDate: Date? {
        get { return decode(from: userDefaults, key: .installDate) }
        set { encode(newValue, to: userDefaults, key: .installDate) }
    }

    public var lastRetentionThreshold: QuantisedTimePast? {
        get { return decode(from: userDefaults, key: .lastRetentionThreshold)}
        set { encode(newValue, to: userDefaults, key: .lastRetentionThreshold) }
    }

    public var search8Days: RollingEightDaysInt {
        get { return decode(from: userDefaults, key: .search8Days) ?? RollingEightDaysInt() }
        set { encode(newValue, to: userDefaults, key: .search8Days) }
    }

    public var adClick8Days: RollingEightDaysInt {
        get { return decode(from: userDefaults, key: .adClick8Days) ?? RollingEightDaysInt() }
        set { encode(newValue, to: userDefaults, key: .adClick8Days) }
    }

    public var duckAIChat8Days: RollingEightDaysInt {
        get { return decode(from: userDefaults, key: .duckAIChat8Days) ?? RollingEightDaysInt() }
        set { encode(newValue, to: userDefaults, key: .duckAIChat8Days) }
    }

    public var subscriptionDate: Date? {
        get { return decode(from: userDefaults, key: .subscriptionDate) }
        set { encode(newValue, to: userDefaults, key: .subscriptionDate) }
    }

    public var subscriptionFreeTrialFired: Bool {
        get { return decode(from: userDefaults, key: .subscriptionFreeTrial) ?? false }
        set { encode(newValue, to: userDefaults, key: .subscriptionFreeTrial) }
    }

    public var subscriptionMonth1Fired: Bool {
        get { return decode(from: userDefaults, key: .subscriptionMonth1) ?? false }
        set { encode(newValue, to: userDefaults, key: .subscriptionMonth1) }
    }
}
