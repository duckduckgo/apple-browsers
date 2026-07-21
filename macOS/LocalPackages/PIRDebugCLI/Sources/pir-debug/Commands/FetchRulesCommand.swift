//
//  FetchRulesCommand.swift
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
import Foundation
import PIRDebugKit

/// Materializes `main_config.json` + the active broker JSONs (byte-identical to the zip contents)
/// from a remote source to disk, reusing `RemoteBrokerRulesProvider` so there is a single remote
/// fetch/unzip path.
struct FetchRulesCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "fetch-rules",
        abstract: "Download main_config.json and all active broker JSONs from a remote source to --out.")

    @OptionGroup var rules: RulesSourceOptions

    @Option(name: .long, help: "Output directory for the materialized rules.", completion: .directory)
    var out: String

    @Flag(name: .long, help: "Also materialize test brokers listed in test_data_brokers.")
    var includeTestBrokers = false

    @OptionGroup var output: OutputOptions

    struct Report: Encodable {
        let outputDirectory: String
        let mainConfig: String
        let brokers: [String]
        let missing: [String]
    }

    func execute() async -> Int32 {
        do {
            let provider = RemoteBrokerRulesProvider(endpoint: try rules.makeRemoteEndpoint())
            let outDir = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            Log.info("Fetching main_config.json and all.zip…")
            let materialized = try await provider.materialize()
            defer { try? FileManager.default.removeItem(at: materialized.extractionDirectory) }

            let mainConfigOut = outDir.appendingPathComponent("main_config.json")
            try materialized.mainConfigData.write(to: mainConfigOut)

            var wanted = materialized.activeDataBrokers
            if includeTestBrokers { wanted += materialized.testDataBrokers }

            var written: [String] = []
            var missing: [String] = []
            for name in wanted.sorted() {
                guard let source = materialized.brokerFilesByName[name] else {
                    missing.append(name)
                    continue
                }
                let destination = outDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
                written.append(name)
            }

            if !missing.isEmpty {
                Log.error("Missing from zip: \(missing.joined(separator: ", "))")
            }
            let report = Report(outputDirectory: outDir.path,
                                mainConfig: mainConfigOut.lastPathComponent,
                                brokers: written,
                                missing: missing)
            try output.resultWriter.write(report)
            return missing.isEmpty ? CLIExit.success : CLIExit.operationFailed
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }
}
