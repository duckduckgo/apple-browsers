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
/// from a remote source to disk.
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

    private struct MainConfig: Decodable {
        let activeDataBrokers: [String]
        let testDataBrokers: [String]
        enum CodingKeys: String, CodingKey {
            case activeDataBrokers = "active_data_brokers"
            case testDataBrokers = "test_data_brokers"
        }
    }

    struct Report: Encodable {
        let outputDirectory: String
        let mainConfig: String
        let brokers: [String]
        let missing: [String]
    }

    func execute() async -> Int32 {
        do {
            let base = try rules.makeRemoteEndpoint().baseURL
            let outDir = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            Log.info("Fetching main_config.json…")
            let mainConfigData = try await get(url: mainConfigURL(base: base))
            let mainConfigOut = outDir.appendingPathComponent("main_config.json")
            try mainConfigData.write(to: mainConfigOut)
            let mainConfig = try JSONDecoder().decode(MainConfig.self, from: mainConfigData)

            var wanted = mainConfig.activeDataBrokers
            if includeTestBrokers { wanted += mainConfig.testDataBrokers }

            Log.info("Downloading and extracting all.zip…")
            let extractionDir = try await downloadAndUnzip(url: allBrokersURL(base: base))
            defer { try? FileManager.default.removeItem(at: extractionDir) }

            let jsonDir = extractionDir.appendingPathComponent("json", isDirectory: true)
            let searchDir = FileManager.default.fileExists(atPath: jsonDir.path) ? jsonDir : extractionDir
            let extracted = try FileManager.default.contentsOfDirectory(at: searchDir,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: [.skipsHiddenFiles])
            let extractedByName = Dictionary(uniqueKeysWithValues: extracted.map { ($0.lastPathComponent, $0) })

            var written: [String] = []
            var missing: [String] = []
            for name in wanted.sorted() {
                guard let source = extractedByName[name] else {
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
            Log.error(error.localizedDescription)
            return CLIExit.usageError
        }
    }

    // MARK: - Networking

    private func mainConfigURL(base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        components?.path += "/dbp/remote/v0/main_config.json"
        return components?.url ?? base.appendingPathComponent("dbp/remote/v0/main_config.json")
    }

    private func allBrokersURL(base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        components?.path += "/dbp/remote/v0"
        components?.queryItems = [
            URLQueryItem(name: "name", value: "all.zip"),
            URLQueryItem(name: "type", value: "spec")
        ]
        return components?.url ?? base.appendingPathComponent("dbp/remote/v0")
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw CLIUsageError("Rules fetch failed for \(url.absoluteString) (HTTP \(code.map(String.init) ?? "?")).")
        }
        return data
    }

    private func downloadAndUnzip(url: URL) async throws -> URL {
        let data = try await get(url: url)
        let uniqueName = UUID().uuidString
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName).appendingPathExtension("zip")
        let extractionDir = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)
        try data.write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", archiveURL.path, "-d", extractionDir.path]
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIUsageError("Failed to unzip broker archive (unzip exited \(process.terminationStatus)).")
        }
        return extractionDir
    }
}
