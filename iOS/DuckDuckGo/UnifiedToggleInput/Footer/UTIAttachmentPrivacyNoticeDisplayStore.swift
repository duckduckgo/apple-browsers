//
//  UTIAttachmentPrivacyNoticeDisplayStore.swift
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

protocol UTIAttachmentPrivacyNoticeDisplayStoring {
    var hasShown: Bool { get }
    func markShown()
    func reset()
}

struct UTIAttachmentPrivacyNoticeDisplayStore: UTIAttachmentPrivacyNoticeDisplayStoring {

    /// Registry confirmation is tracked in Asana 1217505446430505.
    private enum Key: String {
        case shown = "aichat.attachment-privacy-notice.shown"
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

    private let store: UTIAttachmentPrivacyNoticeDisplayStoring
    private let webKeySource: DuckAiNativeStorageHandling?
    private let isEnabled: () -> Bool

    init(store: UTIAttachmentPrivacyNoticeDisplayStoring = UTIAttachmentPrivacyNoticeDisplayStore(),
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

enum UTIAttachmentPrivacyKind: String {
    case image
    case file

    init?(attachment: UnifiedToggleInputAttachment) {
        switch attachment {
        case .image: self = .image
        case .file: self = .file
        case .invalidFile, .tab: return nil
        }
    }
}
