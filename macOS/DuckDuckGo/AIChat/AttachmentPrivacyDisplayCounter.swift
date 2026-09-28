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

/// Where the display count lives. One implementation persists; the other is scoped to a Fire
/// Window and goes away with it.
///
/// Deliberately not the Duck.ai entries namespace: that is the web app's `localStorage`, and the
/// web app replaces it wholesale on hydration, which reset the count and showed the disclosure
/// again in every new tab.
protocol AttachmentPrivacyDisplayCountStoring: AnyObject {
    /// `nil` when nothing has been recorded, which is distinct from a recorded zero.
    var count: Int? { get }
    func setCount(_ count: Int)
    /// Whether the web app's count has already been taken over. The migration runs once.
    var hasMigratedWebCount: Bool { get }
    func markWebCountMigrated()
    /// Clears the count and the migration marker.
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

/// One store per Fire Window, keyed by its data store the way `BurnerDuckAiStorageRegistry` is, so
/// every surface in that window shares a count that starts at zero and dies with the window.
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

    /// The Fire Button. A Fire Window's own count needs no clearing: it dies with the window.
    func resetPersistent() {
        persistentStore.reset()
    }
}

// MARK: - Counter

/// Owns the file-upload privacy disclosure's display count. Check and increment are one operation,
/// so no caller can take the total past the cap.
final class AttachmentPrivacyDisplayCounter {

    static let cap = 3

    /// The web app's own key, which governs while native does not. Read as a starting point so a
    /// user who already saw the message on web does not get three more once native takes over.
    /// Name pending confirmation with the front end — if it is wrong, seeding silently does
    /// nothing and the count restarts at zero.
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

    /// The web app ships this disclosure before native and counts with its own key, so a user who
    /// has already seen it there must not get three more. Runs once: after this the web app's key
    /// is never consulted again.
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

    /// Whether a display is still available, without spending one. For a resolver that re-runs on
    /// every change; spending happens once per composition through `consumeDisplay()`.
    var canDisplay: Bool {
        isEnabled && count < Self.cap
    }

    /// Exposed for the debug menu, which shows how many displays are spent.
    var displayCount: Int { count }

    /// Spends one display if any remain. The answer is what a surface renders on.
    @discardableResult
    func consumeDisplay() -> Bool {
        guard isEnabled else { return false }

        let current = count
        Logger.aiChat.debug("Attachment privacy: display requested, count read as \(current, privacy: .public)")
        guard current < Self.cap else { return false }

        store.setCount(current + 1)
        return true
    }

    /// The web app's key goes too, and the marker is put back: nothing is left to migrate, so the
    /// message can actually return after a burn.
    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
        store.markWebCountMigrated()
    }

    /// An absent or unreadable value counts as zero: erring towards showing a required disclosure.
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

// MARK: - Composition gate

/// Turns the counter's "may I show this" into the rule the disclosure actually follows: once per
/// prompt draft, per tab.
///
/// The draft is per tab, so a different tab is a different prompt. Within one, removing or swapping
/// the attachment does not end the composition — otherwise a user on their last display who
/// changes the file would watch the disclosure vanish mid-flow. Only a submit ends it.
final class AttachmentPrivacyCompositionGate {

    /// A surface with no originating tab — the Prompt Bar — has one composition at a time.
    private static let tablessKey = "no-tab"

    private let counter: AttachmentPrivacyDisplayCounter
    private var grants: [String: Bool] = [:]

    init(counter: AttachmentPrivacyDisplayCounter) {
        self.counter = counter
    }

    /// Asks the counter once per composition, then keeps the answer for the rest of it.
    func shouldShow(hasStagedAttachment: Bool, tabID: String?) -> Bool {
        // Nothing to show without an attachment, but the grant is kept: removing one does not end
        // the composition, so re-attaching must not spend another display.
        guard hasStagedAttachment else { return false }

        let key = tabID ?? Self.tablessKey
        if let granted = grants[key] {
            return granted
        }
        let granted = counter.consumeDisplay()
        grants[key] = granted
        return granted
    }

    /// The submitting tab's next attachment asks the counter again. Other tabs keep the drafts
    /// they are still composing.
    func compositionEnded(tabID: String?) {
        grants[tabID ?? Self.tablessKey] = nil
    }
}

/// Answer to `attachmentPrivacyShouldDisplay`.
struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}
