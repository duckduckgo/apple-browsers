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

/// One store per Fire Window, keyed by its data store like `BurnerDuckAiStorageRegistry`.
final class AttachmentPrivacyDisplayCountRegistry {

    private let lock = NSLock()
    private let persistentStore: AttachmentPrivacyDisplayCountStoring
    private var burnerStores: [ObjectIdentifier: AttachmentPrivacyDisplayCountStoring] = [:]

    init(persistentStore: AttachmentPrivacyDisplayCountStoring = AttachmentPrivacyDisplayCountStore()) {
        self.persistentStore = persistentStore
    }

    func store(for burnerMode: BurnerMode) -> AttachmentPrivacyDisplayCountStoring {
        guard case .burner(let dataStore) = burnerMode else { return persistentStore }

        let key = ObjectIdentifier(dataStore)
        lock.lock()
        defer { lock.unlock() }
        if let existing = burnerStores[key] {
            return existing
        }
        let new = InMemoryAttachmentPrivacyDisplayCountStore()
        burnerStores[key] = new
        return new
    }

    func resetPersistent() {
        persistentStore.reset()
    }
}

// MARK: - Counter

/// Check and increment are one operation, so no caller can pass the cap.
final class AttachmentPrivacyDisplayCounter {

    static let cap = 3

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
    /// must not get three more. Once only.
    private func migrateWebCountIfNeeded() {
        guard !store.hasMigratedWebCount else { return }

        store.markWebCountMigrated()
        guard let webCount, webCount > 0 else { return }

        let migrated = min(webCount, Self.cap)
        store.setCount(migrated)
        Logger.aiChat.debug("Attachment privacy: migrated web count \(migrated, privacy: .public)")
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

    /// The marker goes back on, or the burn would re-migrate the web count and the message would
    /// never return.
    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
        store.markWebCountMigrated()
    }

    /// Absent counts as zero: erring towards showing a required disclosure.
    private var count: Int {
        store.count ?? 0
    }

    private var webCount: Int? {
        guard let value = try? webKeySource?.getEntry(key: Self.webEntryKey) else { return nil }

        switch value {
        case let int as Int: return max(0, int)
        case let double as Double: return max(0, Int(double))
        case let string as String: return Int(string).map { max(0, $0) }
        default: return nil
        }
    }
}

// MARK: - Display gate

/// One display per continuous attachment session, per tab. Emptying the attachments ends it, so
/// re-attaching spends another — matching iOS.
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
