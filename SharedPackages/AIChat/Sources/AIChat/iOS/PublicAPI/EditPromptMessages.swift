//
//  EditPromptMessages.swift
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

#if os(iOS)
import Foundation

public struct EditPromptRequest: Decodable {
    public let prompt: String
    public let images: [AIChatNativePrompt.NativePromptImage]?
    public let files: [AIChatNativePrompt.NativePromptFile]?
    public let hasResponsesToLose: Bool

    public init(prompt: String,
                images: [AIChatNativePrompt.NativePromptImage]?,
                files: [AIChatNativePrompt.NativePromptFile]?,
                hasResponsesToLose: Bool) {
        self.prompt = prompt
        self.images = images
        self.files = files
        self.hasResponsesToLose = hasResponsesToLose
    }
}

public enum EditPromptReply: Encodable {
    case submit(prompt: String,
                images: [AIChatNativePrompt.NativePromptImage]?,
                files: [AIChatNativePrompt.NativePromptFile]?)

    case cancelled

    private enum CodingKeys: String, CodingKey {
        case cancelled, prompt, images, files
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cancelled:
            try container.encode(true, forKey: .cancelled)
        case let .submit(prompt, images, files):
            try container.encode(prompt, forKey: .prompt)
            try container.encode(images ?? [], forKey: .images)
            try container.encode(files ?? [], forKey: .files)
        }
    }
}
#endif
