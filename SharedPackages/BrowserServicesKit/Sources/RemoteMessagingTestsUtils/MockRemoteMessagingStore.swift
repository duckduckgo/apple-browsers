//
//  MockRemoteMessagingStore.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import RemoteMessaging

public class MockRemoteMessagingStore: RemoteMessagingStoring {

    public var saveProcessedResultCalls = 0
    public var fetchRemoteMessagingConfigCalls = 0
    public var fetchScheduledRemoteMessageCalls = 0
    public var hasShownRemoteMessageCalls = 0
    public var fetchShownRemoteMessageIDsCalls = 0
    public var dismissRemoteMessageCalls = 0
    public var fetchDismissedRemoteMessageIDsCalls = 0
    public var updateRemoteMessageCalls = 0

    public var remoteMessagingConfig: RemoteMessagingConfig?
    public var scheduledRemoteMessage: RemoteMessageModel?
    public var remoteMessages: [String: RemoteMessageModel]
    public var shownRemoteMessagesIDs: [String]
    public var dismissedRemoteMessagesIDs: [String]

    public init(
        remoteMessagingConfig: RemoteMessagingConfig? = nil,
        scheduledRemoteMessage: RemoteMessageModel? = nil,
        remoteMessages: [String: RemoteMessageModel] = [:],
        shownRemoteMessagesIDs: [String] = [],
        dismissedRemoteMessagesIDs: [String] = []
    ) {
        self.remoteMessagingConfig = remoteMessagingConfig
        self.scheduledRemoteMessage = scheduledRemoteMessage
        self.remoteMessages = remoteMessages
        self.shownRemoteMessagesIDs = shownRemoteMessagesIDs
        self.dismissedRemoteMessagesIDs = dismissedRemoteMessagesIDs
    }

    public func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) {
        saveProcessedResultCalls += 1
    }

    public func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? {
        fetchRemoteMessagingConfigCalls += 1
        return remoteMessagingConfig
    }

    public func fetchScheduledRemoteMessage() -> RemoteMessageModel? {
        fetchScheduledRemoteMessageCalls += 1
        return scheduledRemoteMessage
    }

    public func hasShownRemoteMessage(withID id: String) -> Bool {
        hasShownRemoteMessageCalls += 1
        return shownRemoteMessagesIDs.contains(id)
    }

    public func fetchShownRemoteMessageIDs() -> [String] {
        fetchShownRemoteMessageIDsCalls += 1
        return shownRemoteMessagesIDs
    }

    public func dismissRemoteMessage(withID id: String) {
        dismissRemoteMessageCalls += 1
    }

    public func fetchDismissedRemoteMessageIDs() -> [String] {
        fetchDismissedRemoteMessageIDsCalls += 1
        return dismissedRemoteMessagesIDs
    }

    public func updateRemoteMessage(withID id: String, asShown shown: Bool) {
        updateRemoteMessageCalls += 1
    }

    public func resetRemoteMessages() {}
}
