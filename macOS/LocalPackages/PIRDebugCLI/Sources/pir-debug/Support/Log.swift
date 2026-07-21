//
//  Log.swift
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

/// Human-readable progress logging. Everything here goes to **stderr** (fd 2) so the result-JSON
/// channel (the preserved original stdout) stays pure.
enum Log {
    nonisolated(unsafe) static var verbose = false

    static func info(_ message: String) {
        write("• \(message)")
    }

    static func error(_ message: String) {
        write("✗ \(message)")
    }

    static func debug(_ message: String) {
        guard verbose else { return }
        write("  \(message)")
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
