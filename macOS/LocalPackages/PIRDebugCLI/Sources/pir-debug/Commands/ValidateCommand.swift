//
//  ValidateCommand.swift
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

import AppKit
import ArgumentParser
import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

struct ValidateCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Decode broker JSON with the exact runtime decoder; report per-file OK/failure. Exits 1 if any file fails.")

    @Option(name: .long, help: "Directory of broker JSON files to validate.", completion: .directory)
    var rulesDir: String?

    @Option(name: .long, help: "A broker JSON file to validate (repeatable).", completion: .file(extensions: ["json"]))
    var brokerFile: [String] = []

    @OptionGroup var out: OutputOptions

    struct FileResult: Encodable {
        let file: String
        let ok: Bool
        let brokerName: String?
        let error: String?
    }

    struct Report: Encodable {
        let total: Int
        let failures: Int
        let results: [FileResult]
    }

    func execute() async -> Int32 {
        do {
            let files = try collectFiles()
            guard !files.isEmpty else {
                throw CLIUsageError("No JSON files to validate. Pass --rules-dir or --broker-file.")
            }

            let decoder = makeBrokerRulesDecoder()
            var results: [FileResult] = []
            for fileURL in files {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let broker = try decoder.decode(DataBroker.self, from: data)
                    results.append(FileResult(file: fileURL.path, ok: true, brokerName: broker.name, error: nil))
                    Log.debug("OK  \(fileURL.lastPathComponent)")
                } catch {
                    results.append(FileResult(file: fileURL.path, ok: false, brokerName: nil, error: String(describing: error)))
                    Log.error("FAIL \(fileURL.lastPathComponent): \(String(describing: error))")
                }
            }

            let failures = results.filter { !$0.ok }.count
            let report = Report(total: results.count, failures: failures, results: results)
            try out.resultWriter.write(report)
            return failures == 0 ? CLIExit.success : CLIExit.operationFailed
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }

    private func collectFiles() throws -> [URL] {
        var urls: [URL] = []
        if let rulesDir {
            let dir = URL(fileURLWithPath: (rulesDir as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CLIUsageError("Not a directory: \(dir.path)")
            }
            let contents = try FileManager.default.contentsOfDirectory(at: dir,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles])
            urls += contents.filter { $0.pathExtension.lowercased() == "json" }
        }
        urls += brokerFile.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return urls.sorted { $0.path < $1.path }
    }
}
