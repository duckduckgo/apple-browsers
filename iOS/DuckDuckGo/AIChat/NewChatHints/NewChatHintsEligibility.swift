//
//  NewChatHintsEligibility.swift
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

/// Hints are for returning users: someone who has sent a Duck.ai prompt and accepted the Terms of Service.
struct NewChatHintsEligibility {

    static let promptConversion = "duckai_prompt"

    private let storage: DuckAiNativeStorageHandling?
    private let fireModeStorage: DuckAiNativeStorageHandling?
    private let termsOfServiceStore: DuckAiTermsOfServiceStore

    init(storage: DuckAiNativeStorageHandling?,
         fireModeStorage: DuckAiNativeStorageHandling?,
         termsOfServiceStore: DuckAiTermsOfServiceStore = DuckAiTermsOfServiceStore()) {
        self.storage = storage
        self.fireModeStorage = fireModeStorage
        self.termsOfServiceStore = termsOfServiceStore
    }

    /// A Fire tab writes to its own store, so a prompt sent there counts too, while the normal store still holds
    /// the prompts sent before it.
    func isEligibleUser(isFireTab: Bool) -> Bool {
        guard termsOfServiceStore.hasAccepted else { return false }
        return hasSentPrompt(in: storage) || (isFireTab && hasSentPrompt(in: fireModeStorage))
    }

    private func hasSentPrompt(in storage: DuckAiNativeStorageHandling?) -> Bool {
        let value = try? storage?.getEntry(key: DuckAiNativeStorageReservedEntryKeys.originConversions.rawValue)
        return Self.containsPromptConversion(value ?? nil)
    }

    /// The web app stores the conversions as a JSON array, which can arrive as the encoded string or already decoded.
    static func containsPromptConversion(_ value: Any?) -> Bool {
        let conversions: Any?
        if let string = value as? String, let data = string.data(using: .utf8) {
            conversions = try? JSONSerialization.jsonObject(with: data)
        } else {
            conversions = value
        }
        return (conversions as? [Any])?.contains { $0 as? String == promptConversion } == true
    }
}
