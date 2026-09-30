//
//  AttachmentPrivacyDisplayCounter.swift
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

import AIChat
import AppKit
import FeatureFlags_macOS
import Foundation
import os.log
import Persistence
import PrivacyConfig

// MARK: - Storage

/// One count for the whole app: Fire Windows share it and the fire button leaves it alone.
/// Not the Duck.ai entries namespace: the web app replaces that wholesale on hydration, which
/// wiped the count.
protocol AttachmentPrivacyDisplayCountStoring: AnyObject {
    var count: Int? { get }
    func setCount(_ count: Int)
    var hasMigratedWebCount: Bool { get }
    func markWebCountMigrated()
    func reset()
}

final class AttachmentPrivacyDisplayCountStore: AttachmentPrivacyDisplayCountStoring {

    private static let key = "aichat.attachment-privacy.display-count"
    private static let migratedKey = "aichat.attachment-privacy.web-count-migrated"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var count: Int? {
        guard let value = try? keyValueStore.object(forKey: Self.key) else { return nil }
        return value as? Int
    }

    func setCount(_ count: Int) {
        try? keyValueStore.set(count, forKey: Self.key)
    }

    var hasMigratedWebCount: Bool {
        guard let value = try? keyValueStore.object(forKey: Self.migratedKey) else { return false }
        return value as? Bool ?? false
    }

    func markWebCountMigrated() {
        try? keyValueStore.set(true, forKey: Self.migratedKey)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Self.key)
        try? keyValueStore.removeObject(forKey: Self.migratedKey)
    }
}

final class InMemoryAttachmentPrivacyDisplayCountStore: AttachmentPrivacyDisplayCountStoring {

    private var stored: Int?
    private var migrated = false

    var count: Int? { stored }
    func setCount(_ count: Int) { stored = count }
    var hasMigratedWebCount: Bool { migrated }
    func markWebCountMigrated() { migrated = true }

    func reset() {
        stored = nil
        migrated = false
    }
}

// MARK: - Counter

/// Check and increment are one operation, so no caller can pass the cap.
final class AttachmentPrivacyDisplayCounter {

    static let cap = 1

    /// Name pending confirmation with the front end: wrong, and the takeover silently does nothing.
    static let webEntryKey = "duckaiFileUploadDisclaimerShownCount"

    private let store: AttachmentPrivacyDisplayCountStoring
    private let webKeySource: DuckAiNativeStorageHandling?
    private let featureFlagger: FeatureFlagger

    init(store: AttachmentPrivacyDisplayCountStoring,
         webKeySource: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.store = store
        self.webKeySource = webKeySource
        self.featureFlagger = featureFlagger
        migrateWebCountIfNeeded()
    }

    /// The web app ships first and counts with its own key, so a user who already saw it there
    /// must not get it again. Once only, and only once the key has actually been read: marking on
    /// a failed read would spend the takeover on nothing and show the message a second time.
    private func migrateWebCountIfNeeded() {
        guard !store.hasMigratedWebCount else { return }

        switch readWebCount() {
        case .unavailable:
            Logger.aiChat.debug("Attachment privacy: web count unreadable, takeover deferred")
        case .absent:
            store.markWebCountMigrated()
        case .count(let webCount):
            store.markWebCountMigrated()
            guard webCount > 0 else { return }

            let migrated = min(webCount, Self.cap)
            store.setCount(migrated)
            Logger.aiChat.debug("Attachment privacy: migrated web count \(migrated, privacy: .public)")
        }
    }

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatAttachmentPrivacyDisclosure)
    }

    var canDisplay: Bool {
        isEnabled && count < Self.cap
    }

    var displayCount: Int { count }

    @discardableResult
    func consumeDisplay() -> Bool {
        guard isEnabled else { return false }

        let current = count
        Logger.aiChat.debug("Attachment privacy: display requested, count read as \(current, privacy: .public)")
        guard current < Self.cap else { return false }

        store.setCount(current + 1)
        return true
    }

    /// The marker goes back on, or the next read would re-migrate the web count and the message
    /// would never return. Debug only.
    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
        store.markWebCountMigrated()
    }

    /// Absent counts as zero: erring towards showing a required disclosure.
    private var count: Int {
        store.count ?? 0
    }

    /// `unavailable` is the one that must not be taken for an answer: no storage handler, or the
    /// read threw. A value that's there but unparseable is an answer — it will never parse.
    private enum WebCountRead {
        case count(Int)
        case absent
        case unavailable
    }

    private func readWebCount() -> WebCountRead {
        guard let webKeySource else { return .unavailable }

        let entry: Any?
        do {
            entry = try webKeySource.getEntry(key: Self.webEntryKey)
        } catch {
            return .unavailable
        }
        guard let entry else { return .absent }

        switch entry {
        case let int as Int:
            return .count(max(0, int))
        case let double as Double:
            return .count(max(0, Int(double)))
        case let string as String:
            guard let int = Int(string) else { return .absent }
            return .count(max(0, int))
        default:
            return .absent
        }
    }
}

// MARK: - Display gate

/// One grant per continuous attachment session, per tab: emptying the attachments ends it.
final class AttachmentPrivacyDisplayGate {

    private static let tablessKey = "no-tab"

    private let counter: AttachmentPrivacyDisplayCounter
    private var grants: [String: Bool] = [:]

    init(counter: AttachmentPrivacyDisplayCounter) {
        self.counter = counter
    }

    func shouldShow(hasStagedAttachment: Bool, tabID: String?) -> Bool {
        let key = tabID ?? Self.tablessKey
        guard hasStagedAttachment else {
            grants[key] = nil
            return false
        }

        if let granted = grants[key] {
            return granted
        }
        let granted = counter.consumeDisplay()
        grants[key] = granted
        return granted
    }

    func displayEnded(tabID: String?) {
        grants[tabID ?? Self.tablessKey] = nil
    }
}

struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}
