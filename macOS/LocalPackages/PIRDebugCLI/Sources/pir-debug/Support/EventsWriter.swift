//
//  EventsWriter.swift
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
import PIRDebugKit

/// Serializes a session's `PIRDebugEvent` stream as JSONL to a file, or (for `--events -`) to
/// stderr — deliberately not the result channel, to keep result JSON pure.
final class EventsWriter {

    /// `--events -` sends the stream to stderr interleaved with progress logs.
    static let stderrToken = "-"

    private let handle: FileHandle
    private let ownsHandle: Bool
    private let encoder = CLIJSON.lineEncoder()

    /// Creates a writer for the given `--events` value, or returns `nil` when no path was supplied.
    init?(path: String?) {
        guard let path else { return nil }
        if path == Self.stderrToken {
            self.handle = .standardError
            self.ownsHandle = false
        } else {
            let url = URL(fileURLWithPath: path)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
            self.handle = handle
            self.ownsHandle = true
        }
    }

    func write(_ event: PIRDebugEvent) {
        guard let data = try? encoder.encode(event) else { return }
        var line = data
        line.append(0x0A)
        handle.write(line)
    }

    func close() {
        guard ownsHandle else { return }
        try? handle.close()
    }
}
