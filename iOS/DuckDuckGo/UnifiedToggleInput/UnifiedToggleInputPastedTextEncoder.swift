//
//  UnifiedToggleInputPastedTextEncoder.swift
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

enum UnifiedToggleInputPastedTextEncoder {

    static func encode(_ attachments: [UnifiedToggleInputAttachment]) -> [AIChatNativePrompt.NativePromptPastedText]? {
        let pasted = attachments.compactMap(\.pastedText).map(\.payload)
        return pasted.isEmpty ? nil : pasted
    }

    /// PoC only: the live FE drops `textPasted`, so a DEBUG build launched with
    /// `-pastedTextDebugInlineFallback YES` also inlines it into `prompt` to demo a chat end to end.
    static func debugInlinedPrompt(_ prompt: String, textPasted: [AIChatNativePrompt.NativePromptPastedText]?) -> String {
#if DEBUG
        guard UserDefaults.standard.bool(forKey: "pastedTextDebugInlineFallback"), let textPasted, !textPasted.isEmpty else { return prompt }
        return (textPasted.map(\.content) + [prompt]).joined(separator: "\n\n")
#else
        return prompt
#endif
    }

    /// PoC only: writes each native prompt handed to the FE to the app's tmp dir, so the payload can be inspected from the host.
    static func debugDump(_ prompt: AIChatNativePrompt, channel: String) {
#if DEBUG
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(prompt) else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pasted-text-poc-\(channel).json")
        try? data.write(to: url)
#endif
    }
}
