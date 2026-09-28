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
import PrivacyConfig

/// Owns the file-upload privacy disclosure's display count. Check and increment are one operation,
/// so no caller can take the total past the cap.
///
/// Built per surface with that surface's storage handler: a burner window resolves an in-memory
/// one, which is what makes a Fire Window start at zero and leave nothing behind.
final class AttachmentPrivacyDisplayCounter {

    static let entryKey = "attachmentPrivacyDisplayCount"
    static let cap = 3

    private let storageHandler: DuckAiNativeStorageHandling?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.storageHandler = storageHandler
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

    /// Spends one display if any remain. The answer is what a surface renders on.
    @discardableResult
    func consumeDisplay() -> Bool {
        guard isEnabled, let storageHandler else { return false }

        let current = count
        guard current < Self.cap else { return false }

        do {
            try storageHandler.putEntry(key: Self.entryKey, value: current + 1)
        } catch {
            // The disclosure is required, so a failed write shows the message and risks an extra
            // impression rather than suppressing one.
            Logger.aiChat.error("Attachment privacy: failed to record display: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    func reset() {
        try? storageHandler?.deleteEntry(key: Self.entryKey)
    }

    /// Exposed for the debug menu, which shows how many displays are spent.
    var displayCount: Int { count }

    /// An unreadable value counts as zero: erring towards showing a required disclosure.
    private var count: Int {
        guard let value = try? storageHandler?.getEntry(key: Self.entryKey) else { return 0 }

        switch value {
        case let int as Int: return max(0, int)
        case let double as Double: return max(0, Int(double))
        case let string as String: return max(0, Int(string) ?? 0)
        default: return 0
        }
    }
}

/// Answer to `attachmentPrivacyShouldDisplay`.
struct AttachmentPrivacyShouldDisplayResponse: Encodable {
    let show: Bool
}
