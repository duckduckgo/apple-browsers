//
//  AttachmentPrivacyDisclosure.swift
//  DuckDuckGo
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
import Foundation
import Persistence

struct AttachmentPrivacyDisclosureStore {

    private enum Key: String {
        case shown = "aichat.attachment-privacy.disclosure-shown"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var hasShown: Bool {
        (try? keyValueStore.object(forKey: Key.shown.rawValue) as? Bool) ?? false
    }

    func markShown() {
        try? keyValueStore.set(true, forKey: Key.shown.rawValue)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.shown.rawValue)
    }
}

@MainActor
final class AttachmentPrivacyDisclosure {
    static let webEntryKey = DuckAiNativeStorageReservedEntryKeys.fileUploadDisclaimerShown.rawValue

    private let store: AttachmentPrivacyDisclosureStore
    private let webKeySource: DuckAiNativeStorageHandling?
    private let isEnabled: () -> Bool

    init(store: AttachmentPrivacyDisclosureStore = AttachmentPrivacyDisclosureStore(),
         webKeySource: DuckAiNativeStorageHandling?,
         isEnabled: @escaping () -> Bool) {
        self.store = store
        self.webKeySource = webKeySource
        self.isEnabled = isEnabled
    }

    var canShow: Bool {
        isEnabled() && !hasBeenShown()
    }

    @discardableResult
    func claim() -> Bool {
        guard canShow else { return false }
        store.markShown()
        return true
    }

    func reset() {
        store.reset()
        try? webKeySource?.deleteEntry(key: Self.webEntryKey)
    }

    private func hasBeenShown() -> Bool {
        if store.hasShown { return true }
        guard webFlagSaysShown() else { return false }
        store.markShown()
        return true
    }

    private func webFlagSaysShown() -> Bool {
        guard let entry = try? webKeySource?.getEntry(key: Self.webEntryKey) else { return false }
        switch entry {
        case let shown as Bool:
            return shown
        case let count as Int:
            return count > 0
        case let count as Double:
            return count > 0
        case let text as String:
            if let flag = Bool(text.lowercased()) { return flag }
            return (Int(text) ?? 0) > 0
        default:
            return false
        }
    }
}

struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}

@MainActor
final class IPadAttachmentPrivacyNotice {

    private let attachmentKind: () -> UTIAttachmentPrivacyKind?
    private let isEnabled: () -> Bool
    private let disclosure: AttachmentPrivacyDisclosure
    private var isDisplayed = false

    private(set) var isPresented = false
    private(set) var kind: UTIAttachmentPrivacyKind?

    init(attachmentKind: @escaping () -> UTIAttachmentPrivacyKind?,
         isEnabled: @escaping () -> Bool,
         disclosure: AttachmentPrivacyDisclosure) {
        self.attachmentKind = attachmentKind
        self.isEnabled = isEnabled
        self.disclosure = disclosure
    }

    func refresh() {
        kind = attachmentKind()
        let enabled = isEnabled()
        if !enabled || kind == nil { endDisplay() }
        isPresented = enabled && kind != nil && (isDisplayed || disclosure.canShow)
    }

    func recordDisplay() -> Bool {
        guard isPresented, !isDisplayed, isEnabled(), disclosure.claim() else { return false }
        isDisplayed = true
        return true
    }

    func endDisplay() {
        isDisplayed = false
    }

    static func message() -> UTIFooterMessage {
        let learnMoreText = UserText.aiChatAttachmentPrivacyNoticeLearnMore
        return UTIFooterMessage(
            icon: .info,
            title: String(format: UserText.aiChatAttachmentPrivacyNoticeFormat, learnMoreText),
            subtitle: nil,
            primaryAction: nil,
            isDismissible: false,
            link: URL(string: "https://duckduckgo.com/duckduckgo-help-pages/duckai/ai-chat-privacy#how-we-moderate-uploaded-images-and-files").map {
                .init(text: learnMoreText, url: $0)
            }
        )
    }
}
