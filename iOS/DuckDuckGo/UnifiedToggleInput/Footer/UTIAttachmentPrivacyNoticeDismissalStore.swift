//
//  UTIAttachmentPrivacyNoticeDismissalStore.swift
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

protocol UTIAttachmentPrivacyNoticeDismissalStoring {
    var dismissedAt: Date? { get }
    func recordDismissal(at date: Date)
    func clearDismissal()
}

/// Unlike the high-usage notice, this one comes back: the dismissal expires after
/// `suppressionWindow`, so it stores the moment rather than a flag. The Fire Button and the debug
/// menu both clear it through `clearDismissal()`.
struct UTIAttachmentPrivacyNoticeDismissalStore: UTIAttachmentPrivacyNoticeDismissalStoring {

    static let suppressionWindow: TimeInterval = 21 * 24 * 60 * 60

    /// TODO: confirm against the storage registry before shipping — Asana 1217505446430505.
    private static let key = "aichat.attachment-privacy-notice.dismissed-at"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    /// Unreadable reads as "never dismissed": showing the disclosure again is the safe failure.
    var dismissedAt: Date? {
        try? keyValueStore.object(forKey: Self.key) as? Date
    }

    func recordDismissal(at date: Date) {
        try? keyValueStore.set(date, forKey: Self.key)
    }

    func clearDismissal() {
        try? keyValueStore.removeObject(forKey: Self.key)
    }
}
