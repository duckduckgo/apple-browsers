//
//  AIChatAttachmentPrivacyNotice.swift
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
import FoundationExtensions

struct AIChatAttachmentPrivacyNotice: Equatable {

    static let learnMoreURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/duckai/ai-chat-privacy")!

    static let title = NotLocalizedString(
        "aichat.attachment.privacy.title",
        value: "Files are automatically scanned for illegal content. Flagged chats have limited data retention.",
        comment: "Privacy disclosure shown in the Duck.ai input drawer while a file is attached"
    )

    static let learnMoreTitle = NotLocalizedString(
        "aichat.attachment.privacy.learnMore",
        value: "Learn more",
        comment: "Inline link in the attachment privacy disclosure, opens the Duck.ai privacy help page"
    )
}

final class AIChatAttachmentPrivacyDismissalStore {

    private enum Constants {
        static let key = "aichat.attachmentPrivacy.dismissedAt"
        static let suppression: TimeInterval = 21 * 24 * 60 * 60
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isSuppressed: Bool {
        guard let dismissedAt = defaults.object(forKey: Constants.key) as? Date else { return false }
        return Date().timeIntervalSince(dismissedAt) < Constants.suppression
    }

    func recordDismissal(at date: Date = Date()) {
        defaults.set(date, forKey: Constants.key)
    }

    func reset() {
        defaults.removeObject(forKey: Constants.key)
    }
}
