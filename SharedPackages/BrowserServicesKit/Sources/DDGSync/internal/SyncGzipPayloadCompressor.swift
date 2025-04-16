//
//  SyncGzipPayloadCompressor.swift
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
import Gzip

protocol SyncPayloadCompressing {
    func compress(_ payload: Data) throws -> Data
}

struct SyncGzipPayloadCompressor: SyncPayloadCompressing {
    func compress(_ payload: Data) throws -> Data {
        try payload.gzipped()
    }
}

extension GzipError {
    /// Mapping is taken from `GzipError.Kind` documentation which maps zlib error codes to enum cases,
    /// and we're effectively reversing that mapping here.
    var errorCode: Int {
        switch kind {
        case .stream:
            return -2
        case .data:
            return -3
        case .memory:
            return -4
        case .buffer:
            return -5
        case .version:
            return -6
        case .unknown(let code):
            return code
        }
    }
}
