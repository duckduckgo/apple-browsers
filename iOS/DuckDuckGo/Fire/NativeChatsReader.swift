//
//  NativeChatsReader.swift
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

import AIChat
import Combine
import Foundation

enum NativeChatsReadFailure: String, Error {
    case storageUnavailable = "storage_unavailable"
    case notMigrated = "not_migrated"
    case timeout
    case readFailed = "read_failed"
}

enum NativeChatsReader {
    static func read(storageHandler: DuckAiNativeStorageHandling?,
                     isStorageEnabled: Bool) async -> Result<[DuckAiChat], NativeChatsReadFailure> {
        await firstValue(storageHandler: storageHandler, isStorageEnabled: isStorageEnabled, requiresMigration: false) {
            ChatHistoryReader(observer: $0).chatsPublisher()
        }
    }

    static func readCount(storageHandler: DuckAiNativeStorageHandling?,
                          isStorageEnabled: Bool,
                          timeout: DispatchQueue.SchedulerTimeType.Stride = .seconds(1)) async -> Result<Int, NativeChatsReadFailure> {
        await firstValue(storageHandler: storageHandler, isStorageEnabled: isStorageEnabled, requiresMigration: true, timeout: timeout) {
            $0.chatCountPublisher()
        }
    }

    private static func firstValue<Value>(storageHandler: DuckAiNativeStorageHandling?,
                                          isStorageEnabled: Bool,
                                          requiresMigration: Bool,
                                          timeout: DispatchQueue.SchedulerTimeType.Stride = .seconds(1),
                                          makePublisher: @escaping (DuckAiNativeChatsObserving) -> AnyPublisher<Value, Error>) async -> Result<Value, NativeChatsReadFailure> {
        guard isStorageEnabled, let storageHandler,
              let observer = storageHandler as? DuckAiNativeChatsObserving else { return .failure(.storageUnavailable) }
        let storageRead = Deferred { () -> AnyPublisher<Value, NativeChatsReadFailure> in
            if requiresMigration, (try? storageHandler.isMigrationDone()) != true {
                return Fail(error: .notMigrated).eraseToAnyPublisher()
            }
            return makePublisher(observer)
                .mapError { _ in NativeChatsReadFailure.readFailed }.eraseToAnyPublisher()
        }
        .subscribe(on: DispatchQueue.global(qos: .userInitiated))
        // Deliver a subscription before the background Deferred can block on readiness or disk I/O.
        let publisher = Just(()).setFailureType(to: NativeChatsReadFailure.self)
            .flatMap { storageRead }
            .timeout(timeout,
                     scheduler: DispatchQueue(label: "com.duckduckgo.native-chats-reader", qos: .userInitiated),
                     customError: { .timeout })
        do {
            guard let value = try await publisher.values.first(where: { _ in true }) else { return .failure(.readFailed) }
            return .success(value)
        } catch {
            return .failure(error as? NativeChatsReadFailure ?? .readFailed)
        }
    }
}
