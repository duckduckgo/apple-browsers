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

import Foundation
import os.log
import Common

struct LogExporter {

    struct LogFilter {
        var predicate: String
        var destinationFileName: String
    }

    static func useIt() {
        Logger.general.log("Exporting logs...")
        // Source: https://app.asana.com/1/137249556945/project/1202500774821704/task/1209989420331708?focus=true
        let allDDG = LogFilter(predicate: #"process CONTAINS "duckduckgo" OR process CONTAINS "DuckDuckGo""#,
                               destinationFileName: "duckduckgo.log")

        // Source: https://app.asana.com/1/137249556945/project/1202500774821704/task/1209066578041976?focus=true
        let sparkle = LogFilter(predicate: #"(process == "org.sparkle-project.Sparkle" OR processImagePath CONTAINS "Sparkle") OR (subsystem == "Updates") OR (process == "Autoupdate")"#,
                                destinationFileName: "updater.log")

        // Source: https://app.asana.com/1/137249556945/project/1205842948507349/task/1205648962129689?focus=true
        let vpnExtensionKit = LogFilter(predicate: #"subsystem == "com.apple.extensionkit" && category == "NSExtension""#,
                                        destinationFileName: "extensionkit_nsextension.log")
        let vpnNetworkextension = LogFilter(predicate: #"subsystem == "com.apple.networkextension"#,
                                            destinationFileName: "networkextension.log")
        let networkProtection = LogFilter(predicate: #"subsystem == "Network protection""#,
                                          destinationFileName: "network_protection.log")

        Task {
            do {
                try await exportFilteredLogsToDesktop(minutesBack: 5, logFilters: [allDDG,
                                                                                   sparkle,
                                                                                   vpnExtensionKit,
                                                                                   vpnNetworkextension,
                                                                                   networkProtection])
            } catch {
                Logger.general.error("Failed to export logs: \(error.localizedDescription)")
            }
        }
    }

    static func exportFilteredLogsToDesktop(minutesBack: Int, logFilters: [LogFilter]) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let timeRange = "\(minutesBack)m"

        for filter in logFilters {
            let logFileURL = tempDir.appendingPathComponent(filter.destinationFileName)
            let predicate = filter.predicate

            let logProcess = Process()
            logProcess.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            logProcess.arguments = [
                "show",
                "--info",
                "--debug",
                "--signpost",
                "--predicate", predicate,
                "--style", "compact",
                "--last", timeRange
            ]

            let outputPipe = Pipe()
            logProcess.standardOutput = outputPipe
            logProcess.standardError = Pipe()

            try logProcess.run()
            logProcess.waitUntilExit()

            guard let data = try outputPipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "LogExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read filtered logs."])
            }
            try output.write(to: logFileURL, atomically: true, encoding: .utf8)
        }

        // Create ZIP archive on Desktop
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let zipURL = desktopURL.appendingPathComponent("ddg_logs.zip")

        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-j", zipURL.path, "\(tempDir.path)/*.log"]

        try zipProcess.run()
        zipProcess.waitUntilExit()

        // Clean up temp dir
        try FileManager.default.removeItem(at: tempDir)
    }
}
