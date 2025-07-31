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
    var isAIFeaturesEnabled: Bool { get set }
    var isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> { get }

    var showShortcutOnNewTabPage: Bool { get set }
    var showShortcutOnNewTabPagePublisher: AnyPublisher<Bool, Never> { get }

    var showShortcutInApplicationMenu: Bool { get set }
    var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> { get }

    var showShortcutInAddressBar: Bool { get set }
    var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> { get }

    var openAIChatInSidebar: Bool { get set }
    var openAIChatInSidebarPublisher: AnyPublisher<Bool, Never> { get }

    func reset()
}

public struct DefaultAIChatPreferencesStorage: AIChatPreferencesStorage {
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public var isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> {
        userDefaults.isAIFeaturesEnabledPublisher
    }

    public var showShortcutOnNewTabPagePublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutOnNewTabPagePublisher
    }

    public var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInApplicationMenuPublisher
    }

    public var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        userDefaults.showAIChatShortcutInAddressBarPublisher
    }

    public var openAIChatInSidebarPublisher: AnyPublisher<Bool, Never> {
        userDefaults.openAIChatInSidebarPublisher
    }

    public init(userDefaults: UserDefaults = .standard,
                notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    public var isAIFeaturesEnabled: Bool {
        get { userDefaults.isAIFeaturesEnabled }
        set { userDefaults.isAIFeaturesEnabled = newValue }
    }

    public var showShortcutOnNewTabPage: Bool {
        get { userDefaults.showAIChatShortcutOnNewTabPage }
        set { userDefaults.showAIChatShortcutOnNewTabPage = newValue }
    }

    public var showShortcutInApplicationMenu: Bool {
        get { userDefaults.showAIChatShortcutInApplicationMenu }
        set { userDefaults.showAIChatShortcutInApplicationMenu = newValue }
    }

    public var showShortcutInAddressBar: Bool {
        get { userDefaults.showAIChatShortcutInAddressBar }
        set { userDefaults.showAIChatShortcutInAddressBar = newValue }
    }

    public var openAIChatInSidebar: Bool {
        get { userDefaults.openAIChatInSidebar }
        set { userDefaults.openAIChatInSidebar = newValue }
    }

    public func reset() {
        userDefaults.isAIFeaturesEnabled = UserDefaults.isAIFeaturesEnabledDefaultValue
        userDefaults.showAIChatShortcutOnNewTabPage = UserDefaults.showAIChatShortcutOnNewTabPageDefaultValue
        userDefaults.showAIChatShortcutInApplicationMenu = UserDefaults.showAIChatShortcutInApplicationMenuDefaultValue
        userDefaults.showAIChatShortcutInAddressBar = UserDefaults.showAIChatShortcutInAddressBarDefaultValue
        userDefaults.openAIChatInSidebar = UserDefaults.openAIChatInSidebarDefaultValue
    }
}

private extension UserDefaults {
    enum Keys {
        static let aiFeatures = "aichat.enabled"
        static let showAIChatShortcutOnNewTabPage = "aichat.showAIChatShortcutOnNewTabPage"
        static let showAIChatShortcutInApplicationMenu = "aichat.showAIChatShortcutInApplicationMenu"
        static let showAIChatShortcutInAddressBar = "aichat.showAIChatShortcutInAddressBar"
        static let openAIChatInSidebar = "aichat.openAIChatInSidebar"
    }

    static let isAIFeaturesEnabledDefaultValue = true
    static let showAIChatShortcutOnNewTabPageDefaultValue = true
    static let showAIChatShortcutInApplicationMenuDefaultValue = true
    static let showAIChatShortcutInAddressBarDefaultValue = true
    static let openAIChatInSidebarDefaultValue = true

    @objc dynamic var isAIFeaturesEnabled: Bool {
        get {
            value(forKey: Keys.aiFeatures) as? Bool ?? Self.isAIFeaturesEnabledDefaultValue
        }

        set {
            guard newValue != isAIFeaturesEnabled else { return }
            set(newValue, forKey: Keys.aiFeatures)
        }
    }

    @objc dynamic var showAIChatShortcutOnNewTabPage: Bool {
        get {
            value(forKey: Keys.showAIChatShortcutOnNewTabPage) as? Bool ?? Self.showAIChatShortcutOnNewTabPageDefaultValue
        }

        set {
            guard newValue != showAIChatShortcutOnNewTabPage else { return }
            set(newValue, forKey: Keys.showAIChatShortcutOnNewTabPage)
        }
    }

    @objc dynamic var showAIChatShortcutInApplicationMenu: Bool {
        get {
            value(forKey: Keys.showAIChatShortcutInApplicationMenu) as? Bool ?? Self.showAIChatShortcutInApplicationMenuDefaultValue
        }

        set {
            guard newValue != showAIChatShortcutInApplicationMenu else { return }
            set(newValue, forKey: Keys.showAIChatShortcutInApplicationMenu)
        }
    }

    @objc dynamic var showAIChatShortcutInAddressBar: Bool {
        get {
            value(forKey: Keys.showAIChatShortcutInAddressBar) as? Bool ?? Self.showAIChatShortcutInAddressBarDefaultValue
        }

        set {
            guard newValue != showAIChatShortcutInAddressBar else { return }
            set(newValue, forKey: Keys.showAIChatShortcutInAddressBar)
        }
    }

    @objc dynamic var openAIChatInSidebar: Bool {
        get {
            value(forKey: Keys.openAIChatInSidebar) as? Bool ?? Self.openAIChatInSidebarDefaultValue
        }

        set {
            guard newValue != openAIChatInSidebar else { return }
            set(newValue, forKey: Keys.openAIChatInSidebar)
        }
    }

    var isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.isAIFeaturesEnabled).eraseToAnyPublisher()
    }

    var showAIChatShortcutOnNewTabPagePublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showAIChatShortcutOnNewTabPage).eraseToAnyPublisher()
    }

    var showAIChatShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showAIChatShortcutInApplicationMenu).eraseToAnyPublisher()
    }

    var showAIChatShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.showAIChatShortcutInAddressBar).eraseToAnyPublisher()
    }

    var openAIChatInSidebarPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.openAIChatInSidebar).eraseToAnyPublisher()
    }
}
#endif
