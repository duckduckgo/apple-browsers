//
//  MockWhatsNewMessageRepository.swift
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
@testable import DuckDuckGo

final class MockWhatsNewMessageRepository: WhatsNewMessageRepository {
    private(set) var didCallFetchScheduledMessage = false
    private(set) var didCallFetchLastShownMessage = false
    private(set) var didCallMarkMessageShown = false

    private(set) var capturedMessage: RemoteMessageModel?
    private(set) var capturedMessageId: String?


    private let remoteMessageModel: RemoteMessageModel?
    var hasShownMessage: Bool

    init(scheduledRemoteMessage: RemoteMessageModel?, hasShownMessage: Bool = false) {
        self.remoteMessageModel = scheduledRemoteMessage
        self.hasShownMessage = hasShownMessage
    }

    func fetchScheduledMessage() -> RemoteMessageModel? {
        didCallFetchScheduledMessage = true
        return remoteMessageModel
    }

    func fetchLastShownMessage() -> RemoteMessageModel? {
        didCallFetchLastShownMessage = true
        return remoteMessageModel
    }

    func markMessageAsShown(_ message: RemoteMessageModel) {
        didCallMarkMessageShown = true
        capturedMessage = message
    }

    func hasShownMessage(withID messageId: String) -> Bool {
        capturedMessageId = messageId
        return hasShownMessage
    }
}
