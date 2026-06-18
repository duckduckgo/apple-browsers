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
import Common

/// Persists pixels awaiting retry. Implementations must be safe to call from multiple threads.
protocol PixelRetryQueueStoring {
    func append(_ items: [PixelRetryQueueItem]) throws
    func remove(itemsWithIDs ids: Set<UUID>) throws
    func storedItems() throws -> [PixelRetryQueueItem]
}

enum PixelRetryQueueStorageError: DDGError {
    case readError(Error)
    case writeError(Error)
    case encodingError(Error)
    case decodingError(Error)

    static func == (lhs: PixelRetryQueueStorageError, rhs: PixelRetryQueueStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.readError(let lhsError), .readError(let rhsError)),
            (.writeError(let lhsError), .writeError(let rhsError)),
            (.encodingError(let lhsError), .encodingError(let rhsError)),
            (.decodingError(let lhsError), .decodingError(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }

    static var errorDomain: String { "com.duckduckgo.pixelkit.PixelRetryQueueStorageError" }

    var errorCode: Int {
        switch self {
        case .readError: 13000
        case .writeError: 13001
        case .encodingError: 13002
        case .decodingError: 13003
        }
    }

    var underlyingError: Error? {
        switch self {
        case .readError(let error), .writeError(let error), .encodingError(let error), .decodingError(let error):
            return error
        }
    }

    var description: String {
        switch self {
        case .readError: "Failed to read the pixel retry queue from disk"
        case .writeError: "Failed to write the pixel retry queue to disk"
        case .encodingError: "Failed to encode the pixel retry queue"
        case .decodingError: "Failed to decode the pixel retry queue"
        }
    }
}
