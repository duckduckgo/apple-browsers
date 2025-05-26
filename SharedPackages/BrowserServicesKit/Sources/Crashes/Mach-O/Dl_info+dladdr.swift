//
//  Dl_info+dladdr.swift
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

/// Extension for `Dl_info` to initialize the structure from a pointer using `dladdr`.
/// - Throws: `Error`: If `dladdr` fails to retrieve information, an error is thrown with a description from `dlerror()`.
extension Dl_info {

    struct Error: LocalizedError {
        public let errorDescription: String?
    }

    init(_ ptr: UnsafeRawPointer) throws {
        var info = Dl_info()
        guard dladdr(ptr, &info) != 0 else {
            throw Error(errorDescription: dlerror().map { String(cString: $0) })
        }
        self = info
    }

}
