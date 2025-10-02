//
//  SafariTestRunner.swift
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

import Foundation
import os.log

@MainActor
public class SafariTestRunner {

    // MARK: - Public Properties

    public let url: URL
    public let iterations: Int

    /// Progress callback (iteration, total, status)
    public var progressHandler: ((Int, Int, String) -> Void)?

    /// Cancellation check
    public var isCancelled: () -> Bool = { false }

    // MARK: - Private Properties

    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "SafariTestRunner"
    )

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    // MARK: - Computed Properties

    public var scriptPath: String? {
        // Try Bundle.module first (SPM)
        #if SWIFT_PACKAGE
        if let resourceURL = Bundle.module.resourceURL {
            let scriptURL = resourceURL
                .appendingPathComponent("SafariTestRunner")
                .appendingPathComponent("bin")
                .appendingPathComponent("safari-performance-test")

            if FileManager.default.fileExists(atPath: scriptURL.path) {
                return scriptURL.path
            }
        }
        #endif

        // Try finding via Bundle(for:)
        let bundle = Bundle(for: SafariTestRunner.self)

        // First try direct resource URL
        if let resourceURL = bundle.resourceURL {
            let scriptURL = resourceURL
                .appendingPathComponent("SafariTestRunner")
                .appendingPathComponent("bin")
                .appendingPathComponent("safari-performance-test")

            if FileManager.default.fileExists(atPath: scriptURL.path) {
                return scriptURL.path
            }
        }

        // Try looking in app bundle's PerformanceTest_PerformanceTest.bundle
        if let resourcePath = bundle.resourcePath,
           let performanceBundle = Bundle(path: "\(resourcePath)/PerformanceTest_PerformanceTest.bundle"),
           let resourceURL = performanceBundle.resourceURL {
            let scriptURL = resourceURL
                .appendingPathComponent("SafariTestRunner")
                .appendingPathComponent("bin")
                .appendingPathComponent("safari-performance-test")

            if FileManager.default.fileExists(atPath: scriptURL.path) {
                return scriptURL.path
            }
        }

        logger.log("Failed to find safari-performance-test script in bundle")
        return nil
    }

    public var outputDirectory: URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("safari-perf-tests")
            .appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Initialization

    public init(url: URL, iterations: Int) {
        self.url = url
        self.iterations = iterations
    }

    // MARK: - Public Methods

    public func runTest() async throws -> String {
        // Validate inputs
        guard iterations > 0 else {
            throw RunnerError.invalidIterationCount
        }

        guard url.scheme == "http" || url.scheme == "https" else {
            throw RunnerError.invalidURL
        }

        guard let scriptPath = scriptPath else {
            throw RunnerError.scriptNotFound
        }

        // Check for Node.js
        let nodePath = try await findNodePath()

        // Create output directory
        let outputDir = outputDirectory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        logger.log("Starting Safari performance test: \(self.url.absoluteString), \(self.iterations) iterations")

        // Create and configure process
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = buildProcessArguments(scriptPath: scriptPath, outputPath: outputDir.path)

        // Set up pipes for output
        self.outputPipe = Pipe()
        self.errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Ensure cleanup happens on all exit paths
        defer {
            cleanup()
        }

        // Monitor output asynchronously
        self.outputTask = Task {
            await monitorOutput(pipe: self.outputPipe!)
        }

        self.errorTask = Task {
            await monitorError(pipe: self.errorPipe!)
        }

        // Run the process
        do {
            try process.run()
        } catch {
            logger.log("Failed to start Safari test process: \(error.localizedDescription)")
            throw RunnerError.processExecutionFailed(error.localizedDescription)
        }

        // Wait for completion or cancellation
        while process.isRunning {
            if isCancelled() {
                logger.log("Test cancelled by user")
                process.terminate()

                // Wait for process to actually exit (with timeout)
                var waitCount = 0
                while process.isRunning && waitCount < 50 { // 5 second timeout
                    try await Task.sleep(nanoseconds: 100_000_000)
                    waitCount += 1
                }

                // Force kill if still running
                if process.isRunning {
                    logger.log("Process did not respond to SIGTERM, sending SIGKILL")
                    process.interrupt()
                }

                throw RunnerError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Wait for output monitoring to complete
        await outputTask?.value
        await errorTask?.value

        // Check exit code
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            logger.log("Safari test process failed with exit code: \(exitCode)")
            throw RunnerError.processFailedWithExitCode(Int(exitCode))
        }

        // Find the results JSON file
        let resultsPath = try findResultsFile(in: outputDir)
        logger.log("Safari test completed successfully. Results at: \(resultsPath)")

        return resultsPath
    }

    public func cleanup() {
        // Cancel monitoring tasks
        outputTask?.cancel()
        errorTask?.cancel()

        // Close file handles to prevent resource leaks
        if let outputPipe = outputPipe {
            try? outputPipe.fileHandleForReading.close()
            self.outputPipe = nil
        }

        if let errorPipe = errorPipe {
            try? errorPipe.fileHandleForReading.close()
            self.errorPipe = nil
        }

        // Ensure process is terminated
        if let process = process, process.isRunning {
            process.terminate()
            // Wait briefly for termination
            let deadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            // Force kill if still running
            if process.isRunning {
                process.interrupt()
            }
        }

        self.process = nil

        logger.log("Cleanup completed")
    }

    // MARK: - Internal Methods (for testing)

    internal func buildProcessArguments() -> [String] {
        return [
            url.absoluteString,
            "\(iterations)"
        ]
    }

    internal func buildProcessArguments(scriptPath: String, outputPath: String) -> [String] {
        return [
            scriptPath,
            url.absoluteString,
            "\(iterations)",
            outputPath
        ]
    }

    internal func parseProgressLog(_ line: String) -> (iteration: Int?, status: String) {
        // Parse format: "[INFO] Starting iteration 5 of 10"
        if line.contains("Starting iteration") {
            let components = line.components(separatedBy: " ")
            if let iterationIndex = components.firstIndex(of: "iteration"),
               iterationIndex + 1 < components.count,
               let iteration = Int(components[iterationIndex + 1]) {
                return (iteration, line.replacingOccurrences(of: "[INFO] ", with: ""))
            }
        }

        // Parse status lines like "[INFO] Clearing cache..."
        if line.hasPrefix("[INFO] ") {
            return (nil, line.replacingOccurrences(of: "[INFO] ", with: ""))
        }

        return (nil, line)
    }

    // MARK: - Private Methods

    private func findNodePath() async throws -> String {
        // Try common Node.js installation paths
        let commonPaths = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
            "/opt/local/bin/node"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'which node'
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        throw RunnerError.nodeNotFound
    }

    private func monitorOutput(pipe: Pipe) async {
        let handle = pipe.fileHandleForReading
        var buffer = ""

        // Use async sequence reading to avoid busy-wait
        await withTaskCancellationHandler {
            // Read data in chunks to avoid blocking
            while !Task.isCancelled {
                // Read available data without blocking indefinitely
                let data = await Task.detached(priority: .userInitiated) {
                    handle.availableData
                }.value

                guard !data.isEmpty else {
                    // No more data available - process has likely finished
                    break
                }

                if let output = String(data: data, encoding: .utf8) {
                    buffer += output

                    // Process complete lines
                    let lines = buffer.components(separatedBy: .newlines)
                    buffer = lines.last ?? ""

                    for line in lines.dropLast() where !line.isEmpty {
                        logger.log("\(line)")

                        let (iteration, status) = parseProgressLog(line)
                        if let iteration = iteration {
                            progressHandler?(iteration, iterations, status)
                        } else if !status.isEmpty {
                            progressHandler?(0, iterations, status)
                        }
                    }
                }

                // Small delay to avoid spinning
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        } onCancel: {
            // Close the file handle when cancelled
            try? handle.close()
        }
    }

    private func monitorError(pipe: Pipe) async {
        let handle = pipe.fileHandleForReading
        var buffer = ""

        // Use async sequence reading to avoid busy-wait
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                let data = await Task.detached(priority: .userInitiated) {
                    handle.availableData
                }.value

                guard !data.isEmpty else {
                    break
                }

                if let error = String(data: data, encoding: .utf8) {
                    buffer += error

                    let lines = buffer.components(separatedBy: .newlines)
                    buffer = lines.last ?? ""

                    for line in lines.dropLast() where !line.isEmpty {
                        logger.log("ERROR: \(line)")
                    }
                }

                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        } onCancel: {
            try? handle.close()
        }
    }

    private func findResultsFile(in directory: URL) throws -> String {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        // Look for JSON files
        let jsonFiles = contents.filter { $0.pathExtension == "json" }

        guard let resultsFile = jsonFiles.first else {
            throw RunnerError.resultsFileNotFound
        }

        return resultsFile.path
    }

    // MARK: - Error Types

    public enum RunnerError: Error, Equatable, Sendable {
        case invalidIterationCount
        case invalidURL
        case scriptNotFound
        case nodeNotFound
        case processExecutionFailed(String)
        case processFailedWithExitCode(Int)
        case cancelled
        case resultsFileNotFound

        public static func == (lhs: RunnerError, rhs: RunnerError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidIterationCount, .invalidIterationCount),
                 (.invalidURL, .invalidURL),
                 (.scriptNotFound, .scriptNotFound),
                 (.nodeNotFound, .nodeNotFound),
                 (.cancelled, .cancelled),
                 (.resultsFileNotFound, .resultsFileNotFound):
                return true
            case (.processExecutionFailed(let lhsMsg), .processExecutionFailed(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.processFailedWithExitCode(let lhsCode), .processFailedWithExitCode(let rhsCode)):
                return lhsCode == rhsCode
            default:
                return false
            }
        }
    }
}
