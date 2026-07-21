//
//  CLIExit.swift
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

/// The process exit codes defined by the `pir-debug` I/O contract.
enum CLIExit {
    /// Success — including a clean zero-record scan.
    static let success: Int32 = 0
    /// An operation failed (scan/opt-out error, any `validate` failure).
    static let operationFailed: Int32 = 1
    /// Usage or configuration error (bad flags, unreadable files, rules fetch failure).
    static let usageError: Int32 = 2
    /// The `--timeout` watchdog fired.
    static let timeout: Int32 = 3
}

/// A configuration/usage problem that should terminate the command with ``CLIExit/usageError``.
struct CLIUsageError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// An operation problem (scan/opt-out) that should terminate the command with ``CLIExit/operationFailed``.
struct CLIOperationError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
