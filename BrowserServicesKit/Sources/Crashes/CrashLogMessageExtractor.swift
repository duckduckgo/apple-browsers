//
//  CrashLogMessageExtractor.swift
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
//
// Inspired by kstenerud/KSCrash
// https://github.com/kstenerud/KSCrash
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Common
import CxxCrashHandler
import Foundation
import os.log

/// Collects crash diagnostic messages (NSException/C++ exception name, description and stack trace) and saves to file:
/// `applicationSupportDir/Diagnostics/2024-05-20T12:11:33Z-%pid%.log`
public struct CrashLogMessageExtractor {

    /// Structure representing an NSException/C++ diagnostic data file stored in the `Application Support/Diagnostics` directory.
    public struct CrashDiagnostic {

        // ""2024-05-22T08:17:23Z59070.log"
        static let fileNameRegex = regex(#"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-][0-2]\d:[0-5]\d|Z))-(\d+)\.log$"#)

        public let url: URL
        public let timestamp: Date
        public let pid: pid_t

        /// Failable constructor parsing the provided file name to extract crash timestamp and pid from the provided NSException/C++ diagnostic data file URL.
        /// - Returns: `nil` if the provided file name doesn’t match the `2024-05-20T12:11:33Z-%pid%.log` format.
        init?(url: URL) {
            let fileName = url.lastPathComponent

            guard let match = Self.fileNameRegex.firstMatch(in: fileName, range: fileName.fullRange),
                  match.numberOfRanges >= 3 else { return nil }

            let dateNsRange = match.range(at: 1)
            let pidNsRange = match.range(at: 2)
            guard dateNsRange.location != NSNotFound, pidNsRange.location != NSNotFound,
                  let dateRange = Range(dateNsRange, in: fileName),
                  let pidRange = Range(pidNsRange, in: fileName),
                  let timestamp = ISO8601DateFormatter().date(from: String(fileName[dateRange])),
                  let pid = pid_t(fileName[pidRange])
            else { return nil }

            self.url = url
            self.timestamp = timestamp
            self.pid = pid
        }

        /// JSON-codable NSException/C++ diagnostic data container.
        public struct DiagnosticData: Codable {
            public let message: String
            public let stackTrace: [String]

            public var isEmpty: Bool {
                message.trimmingWhitespace().isEmpty && stackTrace.isEmpty
            }

            init(message: String, stackTrace: [String]) {
                self.message = message
                self.stackTrace = stackTrace
            }
        }

        /// Try reading diagnostic data from the diagnostics file URL.
        public func diagnosticData() throws -> DiagnosticData {
            do {
                let data = try Data(contentsOf: url)
                let dianosticData = try JSONDecoder().decode(DiagnosticData.self, from: data)
                return dianosticData
            } catch {
                Logger.general.error("😵 could not read contents of \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    fileprivate static var nextUncaughtExceptionHandler: NSUncaughtExceptionHandler?
    fileprivate static var nextCppTerminateHandler: (() -> Void)!
    fileprivate static var diagnosticsDirectory: URL!

    /// Install uncaught NSException and C++ exception handlers.
    /// - Parameters:
    ///   - swapCxaThrow: whether the `__cxa_throw` hook should be installed.
    /// - Note:
    ///   `__cxa_throw` is a method called under the hood when `throw MyCppException();` is executed.
    ///   It unwinds the stack to look for a `catch` handler to handle the thrown exception. If the handler can’t
    ///   be found, `std::terminate` is called, which crashes the app.
    ///
    ///   We use the `__cxa_throw` hook (or call it _swizzle_) to record the stack trace of the original place
    ///   where the exception was thrown and write it to the current NSThread dictionary.
    ///
    ///   If the exception causes app termination, we check the NSThread dictionary for the recorded stack trace
    ///   in our custom `std::terminate` handler that we install using `std::set_terminate` and save
    ///   the exception message and the stack trace to the _Diagnostics_ directory.
    ///
    ///   After the custom `std::terminate` or `NSUncaughtExceptionHandler` is done, we call the
    ///   original exception handler, which causes the app termination.
    public static func setUp(swapCxaThrow: Bool = true) {
        prepareDiagnosticsDirectory()

        // Set unhandled NSException handler
        nextUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(handleException)
        // Set unhandled C++ exception handler
        nextCppTerminateHandler = SetCxxExceptionTerminateHandler(handleTerminateOnCxxException)
        // Swap C++ `throw` to collect stack trace when throw happens
        if swapCxaThrow {
            CxaThrowSwapper.swapCxaThrow(with: captureStackTrace)
        }
    }

    /// create App Support/Diagnostics folder
    private static func prepareDiagnosticsDirectory() {
        let fm = FileManager.default
        let diagnosticsUrl = fm.diagnosticsDirectory
        try? fm.createDirectory(at: diagnosticsUrl, withIntermediateDirectories: true)
        Self.diagnosticsDirectory = diagnosticsUrl

        // clean-up log files older than a week
        let weekAgo = Date.weekAgo
        for fileName in (try? fm.contentsOfDirectory(atPath: diagnosticsUrl.path)) ?? [] {
            let fileUrl = diagnosticsUrl.appending(fileName)
            let timestamp = CrashDiagnostic(url: fileUrl)?.timestamp ?? .distantPast

            if timestamp <= weekAgo {
                try? fm.removeItem(at: fileUrl)
            }
        }
    }

    let fileManager: FileManager
    let diagnosticsDirectory: URL

    public init(fileManager: FileManager? = nil, diagnosticsDirectory: URL? = nil) {
        self.fileManager = fileManager ?? .default
        self.diagnosticsDirectory = diagnosticsDirectory ?? Self.diagnosticsDirectory ?? self.fileManager.diagnosticsDirectory
    }

    /// Write exception diagnostics as JSON data, including the exception name, reason, and `userInfo` dictionary,
    /// to `applicationSupportDir/Diagnostics/2024-05-20T12:11:33Z-%pid%.log`.
    /// - Note: Data sanitization is applied to clean up any potential filename or email occurrences.
    func writeDiagnostic(for exception: NSException) throws {
        // collect exception diagnostics data
        let message = (
            [
                "\(exception.name.rawValue): \(exception.reason?.sanitized() /* clean-up possible filenames and emails */ ?? "")"
            ]
            + (exception.userInfo ?? [:]).map { "\($0.key): " + "\($0.value)".sanitized() }
        ).joined(separator: "\n")
        let diagnosticData = CrashLogMessageExtractor.CrashDiagnostic.DiagnosticData(message: message, stackTrace: exception.callStackSymbols)
        Logger.general.log("😵 crashing on: \(message, privacy: .public)")

        // save crash log with `2024-05-20T12:11:33Z-%pid%.log` file name format
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "\(timestamp)-\(ProcessInfo().processIdentifier).log"
        let fileURL = diagnosticsDirectory.appendingPathComponent(fileName)

        try JSONEncoder().encode(diagnosticData).write(to: fileURL)
    }

    /// Find saved crash diagnostics message for crash PID/timestamp
    public func crashDiagnostic(for timestamp: Date?, pid: pid_t?) -> CrashDiagnostic? {
        guard timestamp != nil || pid != nil,
              var crashLogs = try? fileManager.contentsOfDirectory(atPath: diagnosticsDirectory.path).compactMap({
                  CrashDiagnostic(url: diagnosticsDirectory.appending($0))
              }) else { return nil }

        let calendar = Calendar.current
        let roundedTimestamp = calendar.roundedToMinutes(timestamp)

        if let pid {
            crashLogs = crashLogs.filter {
                // filter by matching timestamp and Process Identifier if it‘s known
                $0.pid == pid && (roundedTimestamp == nil || calendar.roundedToMinutes($0.timestamp) == roundedTimestamp)
            }
        } else {
            crashLogs = crashLogs.filter {
                // filter by matching timestamp
                calendar.roundedToMinutes($0.timestamp) == roundedTimestamp
            }
        }
        crashLogs = crashLogs.sorted {
            // sort by timestamp
            $0.timestamp > $1.timestamp
        }
        // take latest
        guard let crashLog = crashLogs.first else {
            Logger.general.log("😵 no crash logs found for \(timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "<nil>", privacy: .public)/\(pid ?? 0)")
            return nil
        }
        return crashLog
    }

}

// `std::terminate` C++ unhandled exception handler
private func handleTerminateOnCxxException() {
    // convert C++ exception to NSException (with name, description and stack trace) and handle it
    if let exception = NSException.currentCxxException() {
        handleException(exception)
    }
    // default handler
    CrashLogMessageExtractor.nextCppTerminateHandler()
}

// NSUncaughtExceptionHandler
private func handleException(_ exception: NSException) {
    Logger.general.error("Trapped exception \(exception)")

    try? CrashLogMessageExtractor().writeDiagnostic(for: exception)

    // default handler
    CrashLogMessageExtractor.nextUncaughtExceptionHandler?(exception)
}

/// Throw test C++ exception – used for debug purpose
public func throwTestCppException() {
    _throwTestCppException("This a test C++ exception")
}

private extension Calendar {
    func roundedToMinutes(_ date: Date?) -> Date? {
        let components = date.map { self.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        return components.flatMap { self.date(from: $0) }
    }
}
