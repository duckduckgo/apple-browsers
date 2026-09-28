//
//  AIChatHistoryCleanerMock.swift
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

import Combine

public final class MockAIChatHistoryCleaner {
    public private(set) var didCleanAIChatHistory = false

    @Published
    public var shouldDisplayCleanAIChatHistoryOption: Bool

    public var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    /// Stub data for `AIChatHistoryCleaning.allChats()`, kept as plain tuples since this
    /// package doesn't depend on `AIChat` (where the real `DuckAiChat` type lives) — the
    /// `AIChatHistoryCleaning` conformance extension maps these into `DuckAiChat` values.
    public var allChatsStub: [(chatId: String, title: String)] = []

    @MainActor
    public func cleanAIChatHistory() async -> Result<Void, Error> {
        didCleanAIChatHistory = true
        return .success(())
    }

    public init(showCleanOption: Bool = false) {
        shouldDisplayCleanAIChatHistoryOption = showCleanOption
    }
}
