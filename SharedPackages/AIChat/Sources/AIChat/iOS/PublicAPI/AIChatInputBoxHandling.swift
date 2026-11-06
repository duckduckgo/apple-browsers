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
    /// Sends `true` when the native input gains focus and `false` when it loses it.
    var didChangeInputFocus: PassthroughSubject<Bool, Never> { get }

    var persistedModelId: String? { get }
    var persistedReasoningEffort: AIChatReasoningEffort? { get }

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { get }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { get }
    var aiChatStatus: AIChatStatusValue { get set }
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility { get set }

    /// Set by the FE's `disableChatInput` (cleared by `enableChatInput`) while the subscription
    /// recovery card is active for the current chat.
    var isSubmitBlockedByRecoveryCard: Bool { get set }

    var attachmentUsagePublisher: Published<AIChatAttachmentUsage?>.Publisher { get }
    var attachmentUsage: AIChatAttachmentUsage? { get set }

    func editPrompt(_ request: EditPromptRequest) async -> EditPromptReply
    func cancelEdit()
}

public extension AIChatInputBoxHandling {
    func editPrompt(_ request: EditPromptRequest) async -> EditPromptReply { .cancelled }
    func cancelEdit() {}
}

public enum AIChatInputBoxVisibility: String, Codable {
    case hidden
    case visible
    case unknown
}

#endif
