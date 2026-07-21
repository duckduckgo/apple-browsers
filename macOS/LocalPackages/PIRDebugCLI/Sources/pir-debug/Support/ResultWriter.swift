//
//  ResultWriter.swift
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

/// The preserved original-stdout file descriptor, captured by the fd-swap in `main.swift` before
/// any engine code runs. Result JSON is written here; the engine's stray `print`s land on the
/// swapped-over fd 1 (stderr) and never corrupt this channel.
enum ResultChannel {
    nonisolated(unsafe) static var fileDescriptor: Int32 = STDOUT_FILENO
}

/// Writes a command's result JSON either to the preserved result channel or to `--output <path>`.
struct ResultWriter {

    /// Destination file path from `--output`, or `nil` to use the result channel.
    let outputPath: String?

    /// Encodes `value` and writes it (with a trailing newline) to the destination.
    func write<T: Encodable>(_ value: T) throws {
        let data = try CLIJSON.prettyEncoder().encode(value)
        try writeRaw(data)
    }

    func writeRaw(_ data: Data) throws {
        var payload = data
        payload.append(0x0A) // trailing newline
        if let outputPath {
            try payload.write(to: URL(fileURLWithPath: outputPath))
            Log.info("Result written to \(outputPath)")
        } else {
            writeToChannel(payload)
        }
    }

    private func writeToChannel(_ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            let base = raw.baseAddress!
            while offset < data.count {
                let written = Foundation.write(ResultChannel.fileDescriptor,
                                               base.advanced(by: offset),
                                               data.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }
}
