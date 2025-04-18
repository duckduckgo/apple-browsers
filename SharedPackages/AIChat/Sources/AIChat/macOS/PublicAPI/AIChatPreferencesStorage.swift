//
//  AIChatPreferencesStorage.swift
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

#if os(macOS)
import Combine
import Foundation

public protocol AIChatPreferencesStorage {
    var showShortcutInApplicationMenu: Bool { get set }
    var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> { get }

    var showShortcutInAddressBar: Bool { get set }
    var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> { get }

    func reset()
}

public struct DefaultAIChatPreferencesStorage: AIChatPreferencesStorage {
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInApplicationMenuPublisher
    }

    public var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInAddressBarPublisher
    }

    public init(userDefaults: UserDefaults = .standard,
                notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    public var showShortcutInApplicationMenu: Bool {
        get { userDefaults.showAIChatShortcutInApplicationMenu }
        set { userDefaults.showAIChatShortcutInApplicationMenu = newValue }
    }

    public var showShortcutInAddressBar: Bool {
        get { userDefaults.showAIChatShortcutInAddressBar }
        set { userDefaults.showAIChatShortcutInAddressBar = newValue }
    }

    public func reset() {
        userDefaults.showAIChatShortcutInApplicationMenu = UserDefaults.showAIChatShortcutInApplicationMenuDefaultValue
        userDefaults.showAIChatShortcutInAddressBar = UserDefaults.showAIChatShortcutInAddressBarDefaultValue
    }
}

private extension UserDefaults {
    enum Keys {
        static let showAIChatShortcutInApplicationMenuKey = "aichat.showAIChatShortcutInApplicationMenu"
        static let showAIChatShortcutInAddressBarKey = "aichat.showAIChatShortcutInAddressBar"
    }

    static let showAIChatShortcutInApplicationMenuDefaultValue = true
    static let showAIChatShortcutInAddressBarDefaultValue = true

    @objc dynamic var showAIChatShortcutInApplicationMenu: Bool {
        get {
            value(forKey: Keys.showAIChatShortcutInApplicationMenuKey) as? Bool ?? Self.showAIChatShortcutInApplicationMenuDefaultValue
        }

        set {
            guard newValue != showAIChatShortcutInApplicationMenu else { return }
            set(newValue, forKey: Keys.showAIChatShortcutInApplicationMenuKey)
        }
    }

    @objc dynamic var showAIChatShortcutInAddressBar: Bool {
        get {
            value(forKey: Keys.showAIChatShortcutInAddressBarKey) as? Bool ?? Self.showAIChatShortcutInAddressBarDefaultValue
        }

        set {
            guard newValue != showAIChatShortcutInAddressBar else { return }
            set(newValue, forKey: Keys.showAIChatShortcutInAddressBarKey)
        }
    }

    var showAIChatShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showAIChatShortcutInApplicationMenu).eraseToAnyPublisher()
    }

    var showAIChatShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showAIChatShortcutInAddressBar).eraseToAnyPublisher()
    }
}
#endif
