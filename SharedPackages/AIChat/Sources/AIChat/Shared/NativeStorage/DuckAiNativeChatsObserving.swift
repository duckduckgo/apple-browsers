//
//  DuckAiNativeChatsObserving.swift
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
import DuckAiDataStore
import Foundation

/// Reactive view over Duck.ai chats. Conformers emit the current chats on subscribe
/// and re-emit whenever the underlying storage changes (writes from the JS bridge,
/// sync engine, cleaner, fire mode, debug server, etc.).
///
/// Separate from `DuckAiNativeStorageHandling` so storage backends that don't
/// support observation (in-memory / null / test stubs) aren't forced to conform.
public protocol DuckAiNativeChatsObserving {
    func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error>
}

/// Storage handlers that both persist *and* observe — chat-history surfaces require
/// the combined contract.
public typealias DuckAiNativeObservableStorage =
    DuckAiNativeStorageHandling & DuckAiNativeChatsObserving
