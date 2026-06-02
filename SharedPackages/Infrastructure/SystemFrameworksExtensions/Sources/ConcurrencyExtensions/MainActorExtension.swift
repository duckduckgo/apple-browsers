//
//  MainActorExtension.swift
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

extension MainActor {

    /// - Note: https://github.com/swiftlang/swift/blob/dbf7fe6aa01c958fa6711df30423e88ff22c0b75/stdlib/public/Concurrency/MainActor.swift#L128
    @available(*, noasync)
    public nonisolated static func assumeMainThread<T: Sendable>(_ operation: @MainActor () throws -> T) rethrows -> T {
        precondition(Thread.isMainThread)

        return try withoutActuallyEscaping(operation) {
            return try unsafeBitCast($0, to: (() throws -> T).self)()
        }

    }

}
