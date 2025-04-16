//
//  AIChatPreferencesStorage.swift
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

import Combine

protocol AIChatPreferencesStorage {
    var showShortcutInApplicationMenu: Bool { get set }
    var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> { get }

    var showShortcutInAddressBar: Bool { get set }
    var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> { get }

    func reset()
}

struct DefaultAIChatPreferencesStorage: AIChatPreferencesStorage {
    private let userDefaults: UserDefaults
    private let pinningManager: PinningManager
    private let notificationCenter: NotificationCenter

    var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInApplicationMenuPublisher
    }

    var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInAddressBarPublisher
    }

    init(userDefaults: UserDefaults = .standard,
         pinningManager: PinningManager = LocalPinningManager.shared,
         notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.pinningManager = pinningManager
        self.notificationCenter = notificationCenter
    }

    var showShortcutInApplicationMenu: Bool {
        get { userDefaults.showAIChatShortcutInApplicationMenu }
        set { userDefaults.showAIChatShortcutInApplicationMenu = newValue }
    }

    var showShortcutInAddressBar: Bool {
        get { userDefaults.showAIChatShortcutInAddressBar }
        set { userDefaults.showAIChatShortcutInAddressBar = newValue }
    }

    func reset() {
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
