//
//  MockAIChatContentHandlingDelegate.swift
//  DuckDuckGo
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

import Foundation
@testable import DuckDuckGo

public final class MockAIChatContentHandlingDelegate: AIChatContentHandlingDelegate {
    public var didReceiveOpenSettingsRequestCallCount = 0
    public var didReceiveCloseChatRequestCallCount = 0
    public var didReceiveOpenSyncSettingsRequestCallCount = 0
    public var didReceivePromptSubmissionCallCount = 0
    public var didReceivePageContextRequestCallCount = 0

    public init() {}

    public func aiChatContentHandlerDidReceiveOpenSettingsRequest(_ handler: AIChatContentHandling) {
        didReceiveOpenSettingsRequestCallCount += 1
    }

    public func aiChatContentHandlerDidReceiveCloseChatRequest(_ handler: AIChatContentHandling) {
        didReceiveCloseChatRequestCallCount += 1
    }

    public func aiChatContentHandlerDidReceiveOpenSyncSettingsRequest(_ handler: AIChatContentHandling) {
        didReceiveOpenSyncSettingsRequestCallCount += 1
    }

    public func aiChatContentHandlerDidReceivePromptSubmission(_ handler: AIChatContentHandling) {
        didReceivePromptSubmissionCallCount += 1
    }

    public func aiChatContentHandlerDidReceivePageContextRequest(_ handler: AIChatContentHandling) {
        didReceivePageContextRequestCallCount += 1
    }
}
