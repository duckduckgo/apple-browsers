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

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { get }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { get }
    var aiChatStatus: AIChatStatusValue { get set }
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility { get set }
}

public enum AIChatStatusValue: String, Codable {
    case startStreamNewPrompt = "start_stream:new_prompt"
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
}
#endif
