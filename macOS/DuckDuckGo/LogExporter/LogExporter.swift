//
//  LogExporter.swift
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

/*

 */

import Foundation

func useit() {
    
}

struct LogFilter {
    var keyWords: [String]
    var destinationFileName: String
}

func exportFilteredLogsToDesktop(minutesBack: Int = 10, logFilters: [LogFilter]) async throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    for filter in logFilters {
        let logFileURL = tempDir.appendingPathComponent("ddg.log")
    }



    let predicate = #"process CONTAINS "duckduckgo" OR process CONTAINS "DuckDuckGo""#
    let timeRange = "\(minutesBack)m"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "show",
        "--info",
        "--debug",
        "--signpost",
        "--predicate", predicate,
        "--style", "compact",
        "--last", timeRange
    ]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    try process.run()

    return try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { _ in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                continuation.resume(throwing: NSError(domain: "LogExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read filtered logs."]))
                return
            }

            do {
                try output.write(to: logFileURL, atomically: true, encoding: .utf8)

                // Create ZIP archive on Desktop
                let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                let zipURL = desktopURL.appendingPathComponent("ddg_logs.zip")

                let zipProcess = Process()
                zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                zipProcess.arguments = ["-j", zipURL.path, logFileURL.path]

                try zipProcess.run()
                zipProcess.waitUntilExit()

                // Clean up temp dir
                try FileManager.default.removeItem(at: tempDir)

                continuation.resume(returning: zipURL)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
