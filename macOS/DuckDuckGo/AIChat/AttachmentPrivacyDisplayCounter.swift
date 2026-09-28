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
    func reset()
}

final class AttachmentPrivacyDisplayCountStore: AttachmentPrivacyDisplayCountStoring {

    private static let key = "aichat.attachment-privacy.display-count"

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

    func reset() {
        try? keyValueStore.removeObject(forKey: Self.key)
    }
}

final class InMemoryAttachmentPrivacyDisplayCountStore: AttachmentPrivacyDisplayCountStoring {

    private var stored: Int?

    var count: Int? { stored }
    func setCount(_ count: Int) { stored = count }
    func reset() { stored = nil }
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

    /// Both stores: leaving the web app's key behind would have the next read fall back to it, so
    /// the message would never return after a burn.
    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
    }

    /// Ours once it exists, otherwise whatever the web app has counted. An absent or unreadable
    /// value counts as zero: erring towards showing a required disclosure.
    private var count: Int {
        store.count ?? webCount ?? 0
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

/// Answer to `attachmentPrivacyShouldDisplay`.
struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}
