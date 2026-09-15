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
import os.log
import Swifter

/**

 tests-server used for Integration Tests HTTP requests mocking

 run as a Pre-action for Test targets (target -> Edit scheme.. -> Test -> Pre-actions/Post-actions)
 - current work directory: Integration Tests Resources directory, used for file lookup for requests without `data` parameter

 see TestURLExtension.swift for usage example

 **/

extension Logger {
    static let testsServer = Logger(subsystem: "tests-server", category: "HTTP")
}

let server = HttpServer()

private func parseSizeString(_ sizeString: String) -> Int64? {
    // Supports plain bytes, KB, MB, GB suffixes (case-insensitive)
    // Examples: 512, 100KB, 1MB, 500MB, 5GB
    let trimmed = sizeString.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = "^([0-9]+)([KkMmGg][Bb])?$"
    let regex = (try? NSRegularExpression(pattern: pattern))!
    guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) else {
        return nil
    }

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

/// Formats a dictionary for os.Logger. Long `data` values are truncated so HTML/base64 bodies don't flood CI logs.
private func descriptionForLog(_ dict: [String: String]) -> String {
    dict.sorted { $0.key < $1.key }.map { key, value in
        if key == "data", value.count > 120 {
            return "\(key)=\(value.prefix(120))…(\(value.count) chars)"
        }
        return "\(key)=\(value)"
    }.joined(separator: " ")
}

private func isDirectoryAt(_ url: URL) -> Bool {
    do {
        return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
    } catch {
        Logger.testsServer.error("🔴 failed to read isDirectory for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return false
    }
}

private func removeItemAt(_ url: URL) -> Bool {
    do {
        try FileManager.default.removeItem(at: url)
        return true
    } catch {
        Logger.testsServer.error("🔴 failed to delete \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return false
    }
}

private func writeResponse(_ writer: HttpResponseBodyWriter, data: Data, context: String) {
    do {
        try writer.write(data)
    } catch {
        Logger.testsServer.error("🔴 failed to write \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

/// Kept alive so GCD signal sources are not deallocated while the server runs.
private var terminationSignalSources: [any DispatchSourceSignal] = []

private func signalName(_ sig: Int32) -> String {
    switch sig {
    case SIGTERM: return "SIGTERM"
    case SIGINT: return "SIGINT"
    case SIGHUP: return "SIGHUP"
    case SIGQUIT: return "SIGQUIT"
    default: return "signal \(sig)"
    }
}

private let logTestsServerAtexit: @convention(c) () -> Void = {
    let pid = ProcessInfo.processInfo.processIdentifier
    Logger.testsServer.error("🔴 tests-server exiting (atexit) pid=\(pid, privacy: .public)")
}

private func installProcessDeathLogging() {
    // Client disconnect mid-write would otherwise kill the process with an unlogged SIGPIPE.
    signal(SIGPIPE, SIG_IGN)
    Logger.testsServer.info("SIGPIPE ignored; write failures are logged instead")

    atexit(logTestsServerAtexit)

    NSSetUncaughtExceptionHandler { exception in
        let reason = exception.reason ?? ""
        Logger.testsServer.error(
            "🔴 uncaught exception \(exception.name.rawValue, privacy: .public): \(reason, privacy: .public)")
    }

    // DispatchSource is used instead of a C signal handler so Logger (not async-signal-safe) can run.
    // SIGKILL and crashes (SIGSEGV/SIGBUS) cannot be caught.
    for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        let name = signalName(sig)
        source.setEventHandler {
            let pid = ProcessInfo.processInfo.processIdentifier
            Logger.testsServer.error("🔴 tests-server received \(name, privacy: .public) pid=\(pid, privacy: .public)")
            source.cancel()
            exit(128 + sig)
        }
        source.resume()
        terminationSignalSources.append(source)
    }
}

// swiftlint:disable:next opening_brace
server.middleware = [{ request in
    let params = request.queryParams.reduce(into: [:]) { $0[$1.0] = $1.1.removingPercentEncoding }
    let paramsDescription = descriptionForLog(params)
    Logger.testsServer.info("request \(request.method, privacy: .public) \(request.path, privacy: .public) \(paramsDescription, privacy: .public)")

    let status = params["status"].flatMap(Int.init) ?? 200
    let reason = params["reason"] ?? "OK"

    // Handle file deletion requests
    if let filesToDelete = params["deleteFiles"] {
        let paths = filesToDelete.components(separatedBy: ",")
        Logger.testsServer.info("deleteFiles: \(paths.count, privacy: .public) path(s)")
        var results: [(path: String, success: Bool)] = []

        // First try to delete all files
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let isDirectory = isDirectoryAt(url)

            // Skip directories on first pass
            if !isDirectory {
                let success = removeItemAt(url)
                if success {
                    Logger.testsServer.info("deleted file \(path, privacy: .public)")
                }
                results.append((path: path, success: success))
            } else {
                Logger.testsServer.info("delete skip directory on first pass \(path, privacy: .public)")
            }
        }

        // Then try to delete any empty directories
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard isDirectoryAt(url) else { continue }

            // Only delete if empty
            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            } catch {
                Logger.testsServer.error(
                    "🔴 failed to list directory \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }

            if contents.isEmpty {
                let success = removeItemAt(url)
                if success {
                    Logger.testsServer.info("deleted empty directory \(path, privacy: .public)")
                }
                results.append((path: path, success: success))
            } else {
                Logger.testsServer.info("delete skip non-empty directory \(path, privacy: .public)")
            }
        }

        // Return results but don't fail even if some deletions failed
        let report = results.map { "\($0.path): \($0.success ? "deleted" : "failed")" }.joined(separator: "\n")
        Logger.testsServer.info("deleteFiles result: \(report, privacy: .public)")
        return .ok(.text(report))
    }

    // Handle file reading requests
    if let fileToRead = params["readFile"] {
        let fileURL = URL(fileURLWithPath: fileToRead)
        Logger.testsServer.info("readFile \(fileToRead, privacy: .public)")

        do {
            let fileData = try Data(contentsOf: fileURL)
            Logger.testsServer.info("readFile succeeded \(fileData.count, privacy: .public) bytes")
            return .raw(200, "OK", ["Content-Type": "application/octet-stream"]) { writer in
                writeResponse(writer, data: fileData, context: "readFile body \(fileToRead)")
            }
        } catch {
            Logger.testsServer.error("🔴 readFile failed \(fileToRead, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .notFound
        }
    }

    // Support /download/{size} to stream random data of specified size
    if request.path.hasPrefix("/download/") {
        let sizeSpec = String(request.path.dropFirst("/download/".count))
        Logger.testsServer.info("download sizeSpec=\(sizeSpec, privacy: .public)")
        guard let byteCount = parseSizeString(sizeSpec) else {
            Logger.testsServer.error("🔴 download invalid size specification \(sizeSpec, privacy: .public)")
            return .badRequest(.text("Invalid size specification"))
        }

        // Determine if client requested a Range
        let rangeHeader = request.headers["range"] ?? request.headers["Range"]
        Logger.testsServer.info("download byteCount=\(byteCount, privacy: .public) range=\(rangeHeader ?? "none", privacy: .public)")

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
            Logger.testsServer.info("download writing \(length, privacy: .public) bytes from offset \(start, privacy: .public)")
            let chunkSize = 64 * 1024
            var written: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while written < length {
                let toWrite = Int(min(Int64(chunkSize), length - written))
                let base = start + written
                for i in 0..<toWrite {
                    buffer[i] = byteAt(offset: base + Int64(i))
                }
                do {
                    try writer.write(Data(bytes: buffer, count: toWrite))
                    written += Int64(toWrite)
                } catch {
                    Logger.testsServer.error(
                        "🔴 download write failed after \(written, privacy: .public) bytes: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
            Logger.testsServer.info("download finished writing \(written, privacy: .public) bytes")
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
            Logger.testsServer.info("download header overrides \(descriptionForLog(overrideHeaders), privacy: .public)")
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
                guard start <= end else {
                    Logger.testsServer.error("🔴 download invalid range \(rangeHeader, privacy: .public)")
                    return .badRequest(.text("Invalid Range"))
                }
                let length = end - start + 1
                dlHeaders["Content-Length"] = String(length)
                dlHeaders["Content-Range"] = "bytes \(start)-\(end)/\(byteCount)"
                Logger.testsServer.info(
                    "download 206 Partial Content bytes \(start, privacy: .public)-\(end, privacy: .public)/\(byteCount, privacy: .public)")
                return .raw(206, "Partial Content", dlHeaders) { writer in
                    writeBytes(writer: writer, start: start, length: length)
                }
            }
            Logger.testsServer.info("download range header unparsed, serving full content \(rangeHeader, privacy: .public)")
        }

        // Full content
        dlHeaders["Content-Length"] = String(byteCount)
        Logger.testsServer.info("download \(status, privacy: .public) \(reason, privacy: .public) \(byteCount, privacy: .public) bytes")
        return .raw(status, reason, dlHeaders) { writer in
            writeBytes(writer: writer, start: 0, length: byteCount)
        }
    }

    // Default data handling for other routes
    let data: Data
    if request.path == "/", params["data"] == nil {
        data = Data()
        Logger.testsServer.info("empty body (path=/ with no data param)")

    } else if let str = params["data"] {
        data = Data(base64Encoded: str) ?? str.data(using: .utf8)!
        Logger.testsServer.info("body from data param \(data.count, privacy: .public) bytes")

    } else {
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resourceURL = currentDirectoryURL.appendingPathComponent(request.path)
        Logger.testsServer.info("loading resource \(resourceURL.path, privacy: .public)")
        do {
            data = try Data(contentsOf: resourceURL)
            Logger.testsServer.info("loaded resource \(data.count, privacy: .public) bytes")
        } catch {
            Logger.testsServer.error("🔴 file not found at \(resourceURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .notFound
        }
    }

    let headers: [String: String]
    if let headersQuery = params["headers"] {
        guard let url = URL(string: "/?" + headersQuery),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            Logger.testsServer.error("🔴 invalid headers query \(headersQuery, privacy: .public)")
            return .badRequest(.text(headersQuery + " is not a valid URL query string"))
        }

        headers = components.queryItems?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
        Logger.testsServer.info("response headers \(descriptionForLog(headers), privacy: .public)")
    } else {
        headers = [:]
    }

    Logger.testsServer.info("responding \(status, privacy: .public) \(reason, privacy: .public) \(data.count, privacy: .public) bytes")
    return .raw(status, reason, headers) { writer in
        writeResponse(writer, data: data, context: "response body \(request.path)")
    }
}]

installProcessDeathLogging()

let pid = ProcessInfo.processInfo.processIdentifier
let cwd = FileManager.default.currentDirectoryPath
Logger.testsServer.info("starting web server at localhost:8085 pid=\(pid, privacy: .public) cwd=\(cwd, privacy: .public)")
do {
    try server.start(8085)
    Logger.testsServer.info("web server started at localhost:8085")
} catch {
    Logger.testsServer.error("🔴 failed to start web server: \(error.localizedDescription, privacy: .public)")
    throw error
}

Logger.testsServer.info("entering run loop")
RunLoop.main.run()
Logger.testsServer.error("🔴 run loop exited pid=\(pid, privacy: .public)")
