//
//  PixelRetryQueueStoring.swift
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

import Foundation

/// Persists pixels awaiting retry. Implementations must be safe to call from multiple threads.
protocol PixelRetryQueueStoring {
    func append(_ items: [PixelRetryQueueItem]) throws
    func remove(itemsWithIDs ids: Set<UUID>) throws
    func storedItems() throws -> [PixelRetryQueueItem]
}

enum PixelRetryQueueStorageError: Error {
    case readError(Error)
    case writeError(Error)
    case encodingError(Error)
    case decodingError(Error)
}
