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
    public let attachments: AIChatPromptAttachments
    public let hasResponsesToLose: Bool

    private enum CodingKeys: String, CodingKey {
        case prompt, images, files, hasResponsesToLose
    }

    public init(prompt: String, attachments: AIChatPromptAttachments, hasResponsesToLose: Bool) {
        self.prompt = prompt
        self.attachments = attachments
        self.hasResponsesToLose = hasResponsesToLose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(String.self, forKey: .prompt)
        attachments = AIChatPromptAttachments(
            images: try container.decodeIfPresent([AIChatNativePrompt.NativePromptImage].self, forKey: .images),
            files: try container.decodeIfPresent([AIChatNativePrompt.NativePromptFile].self, forKey: .files)
        )
        hasResponsesToLose = try container.decode(Bool.self, forKey: .hasResponsesToLose)
    }
}

public enum EditPromptReply: Encodable {
    case submit(prompt: String, attachments: AIChatPromptAttachments)

    case cancelled

    private enum CodingKeys: String, CodingKey {
        case cancelled, prompt, images, files
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cancelled:
            try container.encode(true, forKey: .cancelled)
        case let .submit(prompt, attachments):
            try container.encode(prompt, forKey: .prompt)
            try container.encodeIfPresent(attachments.images, forKey: .images)
            try container.encodeIfPresent(attachments.files, forKey: .files)
        }
    }
}
#endif
