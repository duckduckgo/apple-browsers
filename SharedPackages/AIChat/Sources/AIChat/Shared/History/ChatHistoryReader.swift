//
//  ChatHistoryReader.swift
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
import os.log

public protocol ChatHistoryReading {
    func chatsPublisher() -> AnyPublisher<[DuckAiChat], Error>
}

public final class ChatHistoryReader: ChatHistoryReading {

    private let observer: DuckAiNativeChatsObserving

    public init(observer: DuckAiNativeChatsObserving) {
        self.observer = observer
    }

    public func chatsPublisher() -> AnyPublisher<[DuckAiChat], Error> {
        observer.chatsPublisher()
            .map { records in
                records
                    .compactMap { try? DuckAiChat.decode(from: $0.data).chat }
                    .sorted { lhs, rhs in
                        if lhs.pinned != rhs.pinned { return lhs.pinned }
                        return lhs.lastEdit > rhs.lastEdit
                    }
            }
            .eraseToAnyPublisher()
    }
}
