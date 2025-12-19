//
//  WhatsNewRepository.swift
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
import RemoteMessaging
import Persistence

protocol WhatsNewMessageRepository {
    /// Fetches scheduled message from RMF for modal prompt display
    func fetchScheduledMessage() -> RemoteMessageModel?

    /// Fetches last shown message from local storage for on-demand display
    func fetchLastShownMessage() -> RemoteMessageModel?

    /// Marks message as shown in RMF and persists to local storage
    /// - Parameter message: The message to mark as shown
    func markMessageAsShown(_ message: RemoteMessageModel) async

    /// Checks if a message has been shown before
    /// - Parameter messageId: The message ID to check
    /// - Returns: true if the message has been shown before
    func hasShownMessage(withID messageId: String) -> Bool
}


final class DefaultWhatsNewMessageRepository: WhatsNewMessageRepository {
    private static let storageKey = "com.duckduckgo.whatsNew.lastShownMessage"

    private let remoteMessageStore: RemoteMessagingStoring
    private let keyValueStore: ThrowingKeyValueStoring

    init(
        remoteMessageStore: RemoteMessagingStoring,
        keyValueStore: ThrowingKeyValueStoring
    ) {
        self.remoteMessageStore = remoteMessageStore
        self.keyValueStore = keyValueStore
    }

    func fetchScheduledMessage() -> RemoteMessageModel? {
        remoteMessageStore.fetchScheduledRemoteMessage(surfaces: .modal)
    }

    func fetchLastShownMessage() -> RemoteMessageModel? {
        guard let data = try? keyValueStore.object(forKey: Self.storageKey) as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(RemoteMessageModel.self, from: data)
    }

    func markMessageAsShown(_ message: RemoteMessageModel) async {
        // 1. Mark in RMF
        await remoteMessageStore.updateRemoteMessage(withID: message.id, asShown: true)
        await remoteMessageStore.dismissRemoteMessage(withID: message.id)

        // 2. Persist to local storage (for on-demand access)
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? keyValueStore.set(data, forKey: Self.storageKey)
    }

    func hasShownMessage(withID messageId: String) -> Bool {
        remoteMessageStore.hasShownRemoteMessage(withID: messageId)
    }

}
