//
//  MockChatHistoryReader.swift
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

import Combine
import Foundation
import AIChat

final class MockChatHistoryReader: ChatHistoryReading {

    let subject: CurrentValueSubject<[DuckAiChat], Error>

    init(chats: [DuckAiChat] = []) {
        self.subject = CurrentValueSubject(chats)
    }

    /// Sorts emitted chats the same way the real `ChatHistoryReader` does: pinned first,
    /// then `lastEdit` descending. Tests that exercise ordering would otherwise rely on
    /// declaration order, which the real reader doesn't honour.
    func chatsPublisher() -> AnyPublisher<[DuckAiChat], Error> {
        subject
            .map { chats in
                chats.sorted { lhs, rhs in
                    if lhs.pinned != rhs.pinned { return lhs.pinned }
                    return lhs.lastEdit > rhs.lastEdit
                }
            }
            .eraseToAnyPublisher()
    }
}
