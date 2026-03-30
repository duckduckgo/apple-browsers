//
//  AIChatInputBoxHandling.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import SwiftUI

public protocol AIChatInputBoxHandling {
    var didPressFireButton: PassthroughSubject<Void, Never> { get }
    var didPressNewChatButton: PassthroughSubject<Void, Never> { get }
    var didSubmitPrompt: PassthroughSubject<String, Never> { get }
    var didSubmitQuery: PassthroughSubject<String, Never> { get }
    var didPressStopGeneratingButton: PassthroughSubject<Void, Never> { get }
    var didPressCustomizeResponsesButton: PassthroughSubject<Void, Never> { get }

    var persistedModelId: String? { get }

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { get }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { get }
    var aiChatStatus: AIChatStatusValue { get set }
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility { get set }

    var attachmentUsagePublisher: Published<AIChatAttachmentUsage?>.Publisher { get }
    var attachmentUsage: AIChatAttachmentUsage? { get set }
}

public enum AIChatStatusValue: String, Codable {
    case startStreamNewPrompt = "start_stream:new_prompt"
    case startStreamRestartStream = "start_stream:restart_stream"
    case loading
    case streaming
    case error
    case ready
    case blocked
    case unknown
}

public enum AIChatInputBoxVisibility: String, Codable {
    case hidden
    case visible
    case unknown
}

public struct AIChatStatus: Codable {
    public let status: AIChatStatusValue
    public let attachments: AIChatAttachmentUsage?
}

public struct AIChatAttachmentUsage: Codable, Equatable {
    public let imagesUsed: Int
    public let filesUsed: Int
    public let fileSizeBytesUsed: Int

    public init(imagesUsed: Int, filesUsed: Int, fileSizeBytesUsed: Int) {
        self.imagesUsed = imagesUsed
        self.filesUsed = filesUsed
        self.fileSizeBytesUsed = fileSizeBytesUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imagesUsed = try container.decodeIfPresent(Int.self, forKey: .imagesUsed) ?? 0
        filesUsed = try container.decodeIfPresent(Int.self, forKey: .filesUsed) ?? 0
        fileSizeBytesUsed = try container.decodeIfPresent(Int.self, forKey: .fileSizeBytesUsed) ?? 0
    }
}
#endif
