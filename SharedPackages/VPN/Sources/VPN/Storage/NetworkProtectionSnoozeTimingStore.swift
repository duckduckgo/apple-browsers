//
//  NetworkProtectionSnoozeTimingStore.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine

public extension UserDefaults {
    @objc dynamic var networkProtectionSnoozeTiming: Data? {
        return data(forKey: NetworkProtectionSnoozeTimingStore.snoozeTimingKey)
    }
}

final public class NetworkProtectionSnoozeTimingStore {

    public struct SnoozeTiming: Codable, Equatable {
        let startDate: Date
        let duration: TimeInterval

        public var endDate: Date {
            return startDate.addingTimeInterval(duration)
        }
    }

    static let snoozeTimingKey = "networkProtectionSnoozeTiming"

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    public let snoozeTimingChangedSubject: PassthroughSubject<Void, Never> = .init()
    private var userDefaultsCancellable: AnyCancellable?

    public init(userDefaults: UserDefaults, notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter

        self.userDefaultsCancellable = userDefaults.publisher(for: \.networkProtectionSnoozeTiming).removeDuplicates().sink { [weak self] _ in
            self?.snoozeTimingChangedSubject.send()
        }
    }

    public var isSnoozing: Bool {
        return activeTiming != nil
    }

    public var activeTiming: SnoozeTiming? {
        get {
            guard let data = userDefaults.data(forKey: Self.snoozeTimingKey) else { return nil }
            return try? JSONDecoder().decode(SnoozeTiming.self, from: data)
        }

        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: Self.snoozeTimingKey)
            } else {
                userDefaults.removeObject(forKey: Self.snoozeTimingKey)
            }

            notificationCenter.post(name: .VPNSnoozeRefreshed, object: nil)
        }
    }

    public var hasExpired: Bool {
        guard let activeTiming else {
            return true
        }

        return Date() > activeTiming.endDate
    }

    public func reset() {
        activeTiming = nil
    }

}

extension NSNotification.Name {

    public static let VPNSnoozeRefreshed: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.browserServicesKit.vpn.snoozeDidChange")

}
