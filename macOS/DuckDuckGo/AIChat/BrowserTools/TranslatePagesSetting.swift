//
//  TranslatePagesSetting.swift
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

import Combine
import Foundation
import Persistence

enum TranslatePagesMode: String, CaseIterable {
    case alwaysAsk
    case neverAsk
}

/// Whether to offer translating pages, and the page languages the user opted out of.
/// Kept in `UserDefaults`, which the Fire button does not clear.
final class TranslatePagesSetting {

    enum Key: String {
        case mode = "aichat.translate-pages.mode"
        case excludedLanguages = "aichat.translate-pages.excluded-languages"
    }

    static let didChange = Notification.Name("com.duckduckgo.aiChat.translatePagesSettingDidChange")

    private let store: KeyValueStoring
    private let notificationCenter: NotificationCenter

    init(store: KeyValueStoring = UserDefaults.standard, notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.notificationCenter = notificationCenter
    }

    /// Fires after every write, on the center the setting was given.
    var changes: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChange, object: self).map { _ in }.eraseToAnyPublisher()
    }

    var mode: TranslatePagesMode {
        get { (store.object(forKey: Key.mode.rawValue) as? String).flatMap(TranslatePagesMode.init) ?? .alwaysAsk }
        set {
            if newValue == .alwaysAsk {
                store.removeObject(forKey: Key.mode.rawValue)
            } else {
                store.set(newValue.rawValue, forKey: Key.mode.rawValue)
            }
            notificationCenter.post(name: Self.didChange, object: self)
        }
    }

    /// Primary language subtags, e.g. `fr` for `fr-CA`, in the order they were added.
    var excludedLanguageCodes: [String] {
        store.object(forKey: Key.excludedLanguages.rawValue) as? [String] ?? []
    }

    var isCustomized: Bool {
        mode != .alwaysAsk || !excludedLanguageCodes.isEmpty
    }

    func isExcluded(languageCode: String) -> Bool {
        excludedLanguageCodes.contains(Self.normalized(languageCode))
    }

    func exclude(languageCode: String) {
        let code = Self.normalized(languageCode)
        guard !code.isEmpty, !excludedLanguageCodes.contains(code) else { return }
        store.set(excludedLanguageCodes + [code], forKey: Key.excludedLanguages.rawValue)
        notificationCenter.post(name: Self.didChange, object: self)
    }

    func reset() {
        store.removeObject(forKey: Key.mode.rawValue)
        store.removeObject(forKey: Key.excludedLanguages.rawValue)
        notificationCenter.post(name: Self.didChange, object: self)
    }

    private static func normalized(_ languageCode: String) -> String {
        let primary = languageCode.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return primary.lowercased()
    }
}
