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
