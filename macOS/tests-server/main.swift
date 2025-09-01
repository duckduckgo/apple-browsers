//
//  main.swift
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
import Swifter

/**

 tests-server used for Integration Tests HTTP requests mocking

 run as a Pre-action for Test targets (target -> Edit scheme.. -> Test -> Pre-actions/Post-actions)
 - current work directory: Integration Tests Resources directory, used for file lookup for requests without `data` parameter

 see TestURLExtension.swift for usage example

 **/

let server = HttpServer()

private func parseSizeString(_ sizeString: String) -> Int64? {
    // Supports plain bytes, KB, MB, GB suffixes (case-insensitive)
    // Examples: 512, 100KB, 1MB, 500MB, 5GB
    let trimmed = sizeString.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = "^([0-9]+)([KkMmGg][Bb])?$"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
    else { return nil }

    func substring(_ range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let r = Range(range, in: trimmed) else { return nil }
        return String(trimmed[r])
    }

    let numberString = substring(match.range(at: 1)) ?? "0"
    let unitString = substring(match.range(at: 2))?.lowercased()

    guard let number = Int64(numberString) else { return nil }

    switch unitString {
    case nil:
        return number
    case "kb":
        return number * 1_000
    case "mb":
        return number * 1_000 * 1_000
    case "gb":
        return number * 1_000 * 1_000 * 1_000
    default:
        return nil
    }
}

private func httpDateString(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(secondsFromGMT: 0)
    fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
    return fmt.string(from: date)
}

// swiftlint:disable:next opening_brace
server.middleware = [{ request in
    let params = request.queryParams.reduce(into: [:]) { $0[$1.0] = $1.1.removingPercentEncoding }
    print(request.method, request.path, params)
    defer {
        print("\n")
    }

    let status = params["status"].flatMap(Int.init) ?? 200
    let reason = params["reason"] ?? "OK"

    // Handle file deletion requests
    if let filesToDelete = params["deleteFiles"] {
        let paths = filesToDelete.components(separatedBy: ",")
        var results: [(path: String, success: Bool)] = []

        // First try to delete all files
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            // Skip directories on first pass
            if !isDirectory {
                let success = (try? FileManager.default.removeItem(at: url)) != nil
                results.append((path: path, success: success))
            }
        }

        // Then try to delete any empty directories
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                // Only delete if empty
                if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
                   contents.isEmpty {
                    let success = (try? FileManager.default.removeItem(at: url)) != nil
                    results.append((path: path, success: success))
                }
            }
        }

        // Return results but don't fail even if some deletions failed
        let report = results.map { "\($0.path): \($0.success ? "deleted" : "failed")" }.joined(separator: "\n")
        return .ok(.text(report))
    }

    // Handle file reading requests
    if let fileToRead = params["readFile"] {
        let fileURL = URL(fileURLWithPath: fileToRead)

        do {
            let fileData = try Data(contentsOf: fileURL)
            return .raw(200, "OK", ["Content-Type": "application/octet-stream"]) { writer in
                try? writer.write(fileData)
            }
        } catch {
            print("Failed to read file at \(fileToRead): \(error)")
            return .notFound
        }
    }

    // Support /download/{size} to stream random data of specified size
    if request.path.hasPrefix("/download/") {
        let sizeSpec = String(request.path.dropFirst("/download/".count))
        guard let byteCount = parseSizeString(sizeSpec) else {
            return .badRequest(.text("Invalid size specification"))
        }

        // Determine if client requested a Range
        let rangeHeader = request.headers["range"] ?? request.headers["Range"]

        // Deterministic per-byte generator based on byte offset
        func byteAt(offset: Int64) -> UInt8 {
            // Simple bijective-ish transform to avoid heavy PRNG state iteration
            // value = low 8 bits of (offset * large_odd) xor (offset >> 7) xor seed
            let seed: UInt64 = 0xDEADBEEFCAFEBABE
            let x = UInt64(bitPattern: offset) &+ seed
            let y = (x &* 0x9E3779B185EBCA87)
            let v = (y ^ (y >> 7) ^ (y >> 17)) & 0xFF
            return UInt8(truncatingIfNeeded: v)
        }

        func writeBytes(writer: HttpResponseBodyWriter, start: Int64, length: Int64) {
            let chunkSize = 64 * 1024
            var written: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while written < length {
                let toWrite = Int(min(Int64(chunkSize), length - written))
                let base = start + written
                for i in 0..<toWrite {
                    buffer[i] = byteAt(offset: base + Int64(i))
                }
                try? writer.write(Data(bytes: buffer, count: toWrite))
                written += Int64(toWrite)
            }
        }

        // Common headers
        var dlHeaders: [String: String] = [
            "Content-Type": "application/octet-stream",
            "Content-Disposition": "attachment; filename=\(sizeSpec).bin",
            "Accept-Ranges": "bytes",
            // Strong validators and caching headers so resuming/restart logic has metadata
            "ETag": "\(sizeSpec)-\(byteCount)",
            "Last-Modified": httpDateString(Date(timeIntervalSince1970: 1_700_000_000)),
            "Cache-Control": "public, max-age=31536000"
        ]

        // Allow overriding headers via the standard ?headers= query used by appendingTestParameters(...)
        if let headersQuery = params["headers"],
           let url = URL(string: "/?" + headersQuery),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            let overrideHeaders = items.reduce(into: [:]) { $0[$1.name] = $1.value }
            for (k, v) in overrideHeaders {
                dlHeaders[k] = v
            }
        }

        if let rangeHeader, rangeHeader.lowercased().hasPrefix("bytes=") {
            // Support single range: bytes=start-end or bytes=start-
            let spec = rangeHeader.dropFirst("bytes=".count)
            let parts = spec.split(separator: ",").first ?? Substring("")
            let se = parts.split(separator: "-")
            if se.count >= 1, let startVal = Int64(se[0]) {
                let start = max(0, startVal)
                let end: Int64 = {
                    if se.count >= 2, let e = Int64(se[1]) { return min(byteCount - 1, e) }
                    return byteCount - 1
                }()
                guard start <= end else { return .badRequest(.text("Invalid Range")) }
                let length = end - start + 1
                dlHeaders["Content-Length"] = String(length)
                dlHeaders["Content-Range"] = "bytes \(start)-\(end)/\(byteCount)"
                return .raw(206, "Partial Content", dlHeaders) { writer in
                    writeBytes(writer: writer, start: start, length: length)
                }
            }
        }

        // Full content
        dlHeaders["Content-Length"] = String(byteCount)
        return .raw(status, reason, dlHeaders) { writer in
            writeBytes(writer: writer, start: 0, length: byteCount)
        }
    }

    // Default data handling for other routes
    let data: Data
    if request.path == "/", params["data"] == nil {
        data = Data()

    } else if let str = params["data"] {
        data = Data(base64Encoded: str) ?? str.data(using: .utf8)!

    } else {
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resourceURL = currentDirectoryURL.appendingPathComponent(request.path)
        do {
            data = try Data(contentsOf: resourceURL)
        } catch {
            print("file not found at", resourceURL.path)
            return .notFound
        }
    }

    let headers: [String: String]
    if let headersQuery = params["headers"] {
        guard let url = URL(string: "/?" + headersQuery),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            print(headersQuery + " is not a valid URL query string")
            return .badRequest(.text(headersQuery + " is not a valid URL query string"))
        }

        headers = components.queryItems?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    } else {
        headers = [:]
    }

    return .raw(status, reason, headers) { writer in
        try? writer.write(data)
    }
}]

print("starting web server at localhost:8085")
try server.start(8085)

RunLoop.main.run()
