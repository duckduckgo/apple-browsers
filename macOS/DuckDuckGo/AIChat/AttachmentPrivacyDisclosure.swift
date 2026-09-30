//
//  AttachmentPrivacyDisclosure.swift
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

protocol AttachmentPrivacyDisclosureStoring: AnyObject {
    var hasShown: Bool { get }
    func markShown()
    var hasTakenOverWebFlag: Bool { get }
    func markWebFlagTakenOver()
    func reset()
}

/// Not the Duck.ai entries namespace: the web app replaces that wholesale on hydration.
final class AttachmentPrivacyDisclosureStore: AttachmentPrivacyDisclosureStoring {

    private static let shownKey = "aichat.attachment-privacy.disclosure-shown"
    private static let takenOverKey = "aichat.attachment-privacy.web-flag-taken-over"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var hasShown: Bool { flag(Self.shownKey) }

    func markShown() {
        try? keyValueStore.set(true, forKey: Self.shownKey)
    }

    var hasTakenOverWebFlag: Bool { flag(Self.takenOverKey) }

    func markWebFlagTakenOver() {
        try? keyValueStore.set(true, forKey: Self.takenOverKey)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Self.shownKey)
        try? keyValueStore.removeObject(forKey: Self.takenOverKey)
    }

    private func flag(_ key: String) -> Bool {
        guard let value = try? keyValueStore.object(forKey: key) else { return false }
        return value as? Bool ?? false
    }
}

// MARK: - Disclosure

/// One display for the whole app: Fire Windows share it, and the fire button leaves it alone.
final class AttachmentPrivacyDisclosure {

    static let webEntryKey = DuckAiNativeStorageReservedEntryKeys.fileUploadDisclaimerShown.rawValue

    private let store: AttachmentPrivacyDisclosureStoring
    private let webKeySource: DuckAiNativeStorageHandling?
    private let featureFlagger: FeatureFlagger

    init(store: AttachmentPrivacyDisclosureStoring,
         webKeySource: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.store = store
        self.webKeySource = webKeySource
        self.featureFlagger = featureFlagger
    }

    var canShow: Bool {
        guard isEnabled else { return false }

        takeOverWebFlagIfNeeded()
        return !store.hasShown
    }

    /// The raw state, with no takeover: a debug read shouldn't decide when the handover happens.
    var hasShown: Bool { store.hasShown }

    /// Main thread only, like every caller: that is what keeps the check and the write from
    /// interleaving with another surface's.
    @discardableResult
    func claim() -> Bool {
        guard isEnabled else { return false }

        takeOverWebFlagIfNeeded()
        guard !store.hasShown else { return false }

        store.markShown()
        return true
    }

    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
        store.markWebFlagTakenOver()
    }

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatAttachmentPrivacyDisclosure)
    }

    /// Whatever ships first, the web app owns the disclosure until our flag is on, so the handover
    /// waits for the flag: taken early, or taken on a failed read, a `true` written later goes
    /// unread and the message shows a second time.
    private func takeOverWebFlagIfNeeded() {
        guard !store.hasTakenOverWebFlag else { return }

        switch readWebFlag() {
        case .unavailable:
            Logger.aiChat.debug("Attachment privacy: web flag unreadable, takeover deferred")
        case .notShown:
            store.markWebFlagTakenOver()
        case .shown:
            store.markWebFlagTakenOver()
            store.markShown()
            Logger.aiChat.debug("Attachment privacy: took over the web app's flag")
        }
    }

    private enum WebFlagRead {
        case shown
        case notShown
        case unavailable
    }

    /// `unavailable` is the one that must not be taken for an answer: no storage handler, or the
    /// read threw. A value that's there but unparseable is an answer, since it will never parse.
    /// Numbers are read too, for the count the web app wrote before it settled on a flag.
    private func readWebFlag() -> WebFlagRead {
        guard let webKeySource else { return .unavailable }

        let entry: Any?
        do {
            entry = try webKeySource.getEntry(key: Self.webEntryKey)
        } catch {
            return .unavailable
        }
        guard let entry else { return .notShown }

        switch entry {
        case let shown as Bool:
            return shown ? .shown : .notShown
        case let count as Int:
            return count > 0 ? .shown : .notShown
        case let count as Double:
            return count > 0 ? .shown : .notShown
        case let count as String:
            return (Int(count) ?? 0) > 0 ? .shown : .notShown
        default:
            return .notShown
        }
    }
}

// MARK: - Display gate

/// Remembers which tab is showing it, so re-resolving while the attachment is staged doesn't turn
/// the notice off once the display is spent.
final class AttachmentPrivacyDisclosureGate {

    private static let tablessKey = "no-tab"

    private let disclosure: AttachmentPrivacyDisclosure
    private var showingTab: String?

    init(disclosure: AttachmentPrivacyDisclosure) {
        self.disclosure = disclosure
    }

    func shouldShow(hasStagedAttachment: Bool, tabID: String?) -> Bool {
        let key = tabID ?? Self.tablessKey
        guard hasStagedAttachment else {
            if showingTab == key { showingTab = nil }
            return false
        }
        if showingTab == key { return true }
        guard disclosure.claim() else { return false }

        showingTab = key
        return true
    }
}

struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}
