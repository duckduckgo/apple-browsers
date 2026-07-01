//
//  TimeoutError.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct TimeoutError: Error, LocalizedError, CustomDebugStringConvertible {

#if DEBUG
    public let interval: TimeInterval?
    public let description: String?
    public let date: Date
    public let file: StaticString
    public let line: UInt

    public var errorDescription: String? {
        "TimeoutError(started: \(date), \(interval != nil ? "timeout: \(interval!)s, " : "")\(description != nil ? " description: " + description! : "") at \(file):\(line))"
    }

#else

    public var errorDescription: String? {
        "Timeout"
    }
#endif

    public init(interval: TimeInterval? = nil, description: String? = nil, date: Date = Date(), file: StaticString = #file, line: UInt = #line) {
#if DEBUG
        self.interval = interval
        self.description = description
        self.date = date
        self.file = file
        self.line = line
#endif
    }

    public var debugDescription: String {
        errorDescription!
    }

}
