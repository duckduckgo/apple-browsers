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
public class SafariTestRunner: SafariTestExecuting {

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
        #if SWIFT_PACKAGE
        // SPM test environment
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

        // App bundle environment
        let bundle = Bundle(for: SafariTestRunner.self)
        guard let resourcePath = bundle.resourcePath,
              let performanceBundle = Bundle(path: "\(resourcePath)/PerformanceTest_PerformanceTest.bundle"),
              let resourceURL = performanceBundle.resourceURL else {
            return nil
        }

        let scriptURL = resourceURL
            .appendingPathComponent("SafariTestRunner")
            .appendingPathComponent("bin")
            .appendingPathComponent("safari-performance-test")

        return FileManager.default.fileExists(atPath: scriptURL.path) ? scriptURL.path : nil
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
            logger.log("ERROR: Safari test script not found in bundle")
            throw RunnerError.scriptNotFound
        }

        // Check for Node.js
        let nodePath = try await findNodePath()

        // Check for npm dependencies and install if needed
        try await ensureNpmDependencies(nodePath: nodePath, scriptPath: scriptPath)

        // Create output directory
        let outputDir = outputDirectory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        logger.log("Starting Safari performance test: \(self.url.absoluteString), \(self.iterations) iterations")

        // Create and configure process
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: nodePath)
        let args = buildProcessArguments(scriptPath: scriptPath, outputPath: outputDir.path)
        process.arguments = args

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
        // Parse format: "[INFO] Running iteration 5 of 10"
        if line.contains("iteration") && line.contains(" of ") {
            let components = line.components(separatedBy: " ")
            if let iterationIndex = components.firstIndex(of: "iteration"),
               iterationIndex + 1 < components.count,
               let iteration = Int(components[iterationIndex + 1]) {
                // Clean up the status message
                let cleanStatus = line
                    .replacingOccurrences(of: "[INFO] ", with: "")
                    .replacingOccurrences(of: "[DEBUG] ", with: "")
                    .replacingOccurrences(of: "[WARN] ", with: "")
                return (iteration, cleanStatus)
            }
        }

        // Parse status lines like "[INFO] Clearing cache..."
        let cleanLine = line
            .replacingOccurrences(of: "[INFO] ", with: "")
            .replacingOccurrences(of: "[DEBUG] ", with: "")
            .replacingOccurrences(of: "[WARN] ", with: "")

        if !cleanLine.isEmpty {
            return (nil, cleanLine)
        }

        return (nil, line)
    }

    // MARK: - Private Methods

    // Makes sure Node and NPM are installed and the dependencies are installed
    private func ensureNpmDependencies(nodePath: String, scriptPath: String) async throws {
        // Get the SafariTestRunner directory (parent of bin/)
        let scriptURL = URL(fileURLWithPath: scriptPath)
        let safariTestRunnerDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let nodeModulesPath = safariTestRunnerDir.appendingPathComponent("node_modules")
        let packageJsonPath = safariTestRunnerDir.appendingPathComponent("package.json")

        // Check if package.json exists
        guard FileManager.default.fileExists(atPath: packageJsonPath.path) else {
            return
        }

        // Check if node_modules exists
        if FileManager.default.fileExists(atPath: nodeModulesPath.path) {
            return
        }

        // Need to install dependencies
        logger.log("Installing npm dependencies...")
        progressHandler?(0, iterations, "Installing npm dependencies...")

        // Find npm (should be in same directory as node)
        let nodeURL = URL(fileURLWithPath: nodePath)
        let npmPath = nodeURL.deletingLastPathComponent().appendingPathComponent("npm").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npmPath)
        process.arguments = ["install", "--no-audit", "--no-fund"]
        process.currentDirectoryURL = safariTestRunnerDir

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.log("npm install failed: \(errorOutput)")
                throw RunnerError.npmInstallFailed
            }

            logger.log("npm dependencies installed successfully")
        } catch {
            logger.log("Failed to install npm dependencies: \(error.localizedDescription)")
            throw RunnerError.npmInstallFailed
        }
    }

    private func findNodePath() async throws -> String {
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

                    for line in lines.dropLast().filter({ !$0.isEmpty }) {
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

                    for line in lines.dropLast().filter({ !$0.isEmpty }) {
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
        case npmInstallFailed
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
                 (.npmInstallFailed, .npmInstallFailed),
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
