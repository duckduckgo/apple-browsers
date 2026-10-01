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
    func reset()
}

/// Not the Duck.ai entries namespace: the web app replaces that wholesale on hydration.
final class AttachmentPrivacyDisclosureStore: AttachmentPrivacyDisclosureStoring {

    private static let shownKey = "aichat.attachment-privacy.disclosure-shown"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var hasShown: Bool { flag(Self.shownKey) }

    func markShown() {
        try? keyValueStore.set(true, forKey: Self.shownKey)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Self.shownKey)
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

        return !hasBeenShown()
    }

    /// The raw state, with no takeover: a debug read shouldn't decide when the handover happens.
    var hasShown: Bool { store.hasShown }

    /// Main thread only, like every caller: that is what keeps the check and the write from
    /// interleaving with another surface's.
    @discardableResult
    func claim() -> Bool {
        guard isEnabled else { return false }
        guard !hasBeenShown() else { return false }

        store.markShown()
        return true
    }

    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
    }

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatAttachmentPrivacyDisclosure)
    }

    /// Whatever ships first, the web app owns the disclosure until our flag is on and the front
    /// end delegates, so its flag counts as shown. Read on every decision until we have recorded
    /// one ourselves, then adopted, so the answer survives the web app replacing its own entries.
    private func hasBeenShown() -> Bool {
        if store.hasShown { return true }
        guard webFlagSaysShown() else { return false }

        store.markShown()
        Logger.aiChat.debug("Attachment privacy: adopted the web app's flag")
        return true
    }

    /// Numbers too, for the count the web app wrote before it settled on a flag. A failed read or
    /// an unreadable value is not an answer — the next decision reads again.
    private func webFlagSaysShown() -> Bool {
        guard let webKeySource,
              let entry = try? webKeySource.getEntry(key: Self.webEntryKey) else { return false }

        switch entry {
        case let shown as Bool:
            return shown
        case let count as Int:
            return count > 0
        case let count as Double:
            return count > 0
        // The web app mirrors its localStorage, so the flag arrives as the string "true".
        case let text as String:
            if let flag = Bool(text.lowercased()) { return flag }
            return (Int(text) ?? 0) > 0
        default:
            return false
        }
    }
}

// MARK: - Display gate

/// Showing the notice spends the one display, so `hasShown` on its own can't answer "should it be
/// on screen": the next resolve would turn it off with the attachment still staged. This holds the
/// missing bit — the display is mine, right now — per tab, since one container serves every tab in
/// the window.
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
