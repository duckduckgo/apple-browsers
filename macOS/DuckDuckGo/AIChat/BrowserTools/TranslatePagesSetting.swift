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
        case offeredLanguages = "aichat.translate-pages.offered-languages"
    }

    static let didChange = Notification.Name("com.duckduckgo.aiChat.translatePagesSettingDidChange")

    private let store: KeyValueStoring
    private let notificationCenter: NotificationCenter

    init(store: KeyValueStoring = UserDefaults.standard, notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.notificationCenter = notificationCenter
    }

    /// Fires after a write by any instance on the same center, so an open Settings pane follows the offer's writes.
    var changes: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChange).map { _ in }.eraseToAnyPublisher()
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

    /// Page languages the offer has been shown for. Kept for good: Reset leaves them in the Settings menu.
    var offeredLanguageCodes: [String] {
        store.object(forKey: Key.offeredLanguages.rawValue) as? [String] ?? []
    }

    var isCustomized: Bool {
        mode != .alwaysAsk || !excludedLanguageCodes.isEmpty
    }

    func isExcluded(languageCode: String) -> Bool {
        excludedLanguageCodes.contains(Self.normalized(languageCode))
    }

    func recordOffered(languageCode: String) {
        let code = Self.normalized(languageCode)
        guard !code.isEmpty, !offeredLanguageCodes.contains(code) else { return }
        store.set(offeredLanguageCodes + [code], forKey: Key.offeredLanguages.rawValue)
        notificationCenter.post(name: Self.didChange, object: self)
    }

    func exclude(languageCode: String) {
        let code = Self.normalized(languageCode)
        guard !code.isEmpty, !excludedLanguageCodes.contains(code) else { return }
        store.set(excludedLanguageCodes + [code], forKey: Key.excludedLanguages.rawValue)
        notificationCenter.post(name: Self.didChange, object: self)
    }

    func include(languageCode: String) {
        let code = Self.normalized(languageCode)
        guard excludedLanguageCodes.contains(code) else { return }
        let remaining = excludedLanguageCodes.filter { $0 != code }
        if remaining.isEmpty {
            store.removeObject(forKey: Key.excludedLanguages.rawValue)
        } else {
            store.set(remaining, forKey: Key.excludedLanguages.rawValue)
        }
        notificationCenter.post(name: Self.didChange, object: self)
    }

    func reset() {
        store.removeObject(forKey: Key.mode.rawValue)
        store.removeObject(forKey: Key.excludedLanguages.rawValue)
        notificationCenter.post(name: Self.didChange, object: self)
    }

    static func normalized(_ languageCode: String) -> String {
        let primary = languageCode.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return primary.lowercased()
    }
}

/// The languages the Settings menu lists, and how it names them.
enum TranslatePagesLanguages {

    /// The languages the app is localized into, as primary subtags. `Bundle.main.localizations` at runtime.
    static func appLocalizations(from localizations: [String] = Bundle.main.localizations) -> [String] {
        localizations.filter { $0 != "Base" }.map(TranslatePagesSetting.normalized)
    }

    /// The first preferred language's primary subtag, the one the offer never covers.
    static func systemCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
        preferredLanguages.first.map(TranslatePagesSetting.normalized)
    }

    static func name(of code: String, locale: Locale = .current) -> String? {
        locale.localizedString(forLanguageCode: code)
    }

    /// The codes the locale can name, without the system language, by name. The one ordering the menu and summary share.
    private static func named(_ codes: [String], systemCode: String?, locale: Locale) -> [(code: String, name: String)] {
        Set(codes).subtracting([systemCode].compactMap { $0 })
            .compactMap { code in name(of: code, locale: locale).map { (code: code, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// App localizations, offered and excluded languages, without the system language, by name.
    static func menuCodes(localizations: [String], offered: [String], excluded: [String], systemCode: String?,
                          locale: Locale = .current) -> [String] {
        named(localizations + offered + excluded, systemCode: systemCode, locale: locale).map(\.code)
    }

    /// The system language, then each excluded language by name.
    static func summary(excluded: [String], systemCode: String?, locale: Locale = .current) -> String {
        let system = systemCode.flatMap { name(of: $0, locale: locale) }
        return ([system].compactMap { $0 } + named(excluded, systemCode: systemCode, locale: locale).map(\.name))
            .joined(separator: ", ")
    }
}
