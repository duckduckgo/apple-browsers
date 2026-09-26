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
    var displayCount: Int { get }
    func recordDisplay()
    func reset()
}

struct UTIAttachmentPrivacyNoticeDisplayStore: UTIAttachmentPrivacyNoticeDisplayStoring {
    static let displayLimit = 3

    /// Registry confirmation is tracked in Asana 1217505446430505.
    private enum Key: String {
        case displayCount = "aichat.attachment-privacy-notice.display-count"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var displayCount: Int {
        max(0, (try? keyValueStore.object(forKey: Key.displayCount.rawValue) as? Int) ?? 0)
    }

    func recordDisplay() {
        let count = displayCount
        guard count < Self.displayLimit else { return }
        try? keyValueStore.set(count + 1, forKey: Key.displayCount.rawValue)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.displayCount.rawValue)
    }
}
