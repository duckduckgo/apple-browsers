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
    public let maxIterations: Int

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
    private var errorOutput: [String] = []

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

    public init(url: URL, iterations: Int, maxIterations: Int = 30) {
        self.url = url
        self.iterations = iterations
        self.maxIterations = maxIterations
    }

    // MARK: - Public Methods

    public func runTest() async throws -> String {
        // Clear previous error output
        errorOutput.removeAll()

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

        // Set up test runner in temp directory (allows npm install in writable location)
        let runtimeDir = try await setupRuntimeDirectory(sourcePath: scriptPath)
        let runtimeScript = runtimeDir.appendingPathComponent("bin/safari-performance-test")

        // Create output directory
        let outputDir = outputDirectory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        logger.log("Starting Safari performance test: \(self.url.absoluteString), \(self.iterations) iterations")

        // Create and configure process
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: nodePath)
        let args = buildProcessArguments(scriptPath: runtimeScript.path, outputPath: outputDir.path)
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
                logger.log("Test cancelled")
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
            let errorDetails = errorOutput.joined(separator: "\n")
            logger.log("Safari test process failed with exit code: \(exitCode)")
            if !errorDetails.isEmpty {
                logger.log("Error output: \(errorDetails)")
                throw RunnerError.processFailedWithError(Int(exitCode), errorDetails)
            } else {
                throw RunnerError.processFailedWithExitCode(Int(exitCode))
            }
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

    internal func buildProcessArguments(scriptPath: String, outputPath: String) -> [String] {
        return [
            scriptPath,
            url.absoluteString,
            "\(iterations)",
            "\(maxIterations)",
            outputPath
        ]
    }

    internal func parseProgressLog(_ line: String) -> (iteration: Int?, status: String) {
        // Clean log prefixes first
        let cleanLine = line
            .replacingOccurrences(of: "[INFO] ", with: "")
            .replacingOccurrences(of: "[DEBUG] ", with: "")
            .replacingOccurrences(of: "[WARN] ", with: "")

        // Check for consistency metrics
        if cleanLine.contains("Consistency metrics:") {
            // Extract just the metrics part
            if let metricsRange = cleanLine.range(of: "Consistency metrics: ") {
                let metrics = String(cleanLine[metricsRange.upperBound...])
                return (nil, metrics)
            }
        }

        // Parse iteration number from lines like "==> Starting iteration 10"
        if cleanLine.contains("iteration") {
            let components = cleanLine.components(separatedBy: " ")
            if let iterationIndex = components.firstIndex(of: "iteration"),
               iterationIndex + 1 < components.count,
               let iteration = Int(components[iterationIndex + 1]) {
                return (iteration, "Running tests")
            }
        }

        // Return other status lines as-is
        if !cleanLine.isEmpty {
            return (nil, cleanLine)
        }

        return (nil, line)
    }

    // MARK: - Private Methods

    private func setupRuntimeDirectory(sourcePath: String) async throws -> URL {
        let scriptURL = URL(fileURLWithPath: sourcePath)
        let sourceDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

        // Use a persistent temp location that survives across runs
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("safari-test-runner")
        let runtimeDir = tempBase.appendingPathComponent("current")

        // Check if cache exists and is up to date
        let nodeModulesPath = runtimeDir.appendingPathComponent("node_modules")
        let srcDir = runtimeDir.appendingPathComponent("src")

        if FileManager.default.fileExists(atPath: nodeModulesPath.path),
           FileManager.default.fileExists(atPath: srcDir.path) {
            // Check if source files are newer than cache
            let sourceFile = sourceDir.appendingPathComponent("src/core/PerformanceTestRunner.js")
            let cachedFile = srcDir.appendingPathComponent("core/PerformanceTestRunner.js")

            if let sourceModDate = try? FileManager.default.attributesOfItem(atPath: sourceFile.path)[.modificationDate] as? Date,
               let cachedModDate = try? FileManager.default.attributesOfItem(atPath: cachedFile.path)[.modificationDate] as? Date,
               sourceModDate <= cachedModDate {
                logger.log("Using cached Safari test runner at \(runtimeDir.path)")
                return runtimeDir
            } else {
                logger.log("Source files changed - rebuilding cache...")
            }
        }

        // Clean up any old installation
        if FileManager.default.fileExists(atPath: runtimeDir.path) {
            try? FileManager.default.removeItem(at: runtimeDir)
        }

        logger.log("Setting up Safari test runner in temp directory...")
        progressHandler?(0, iterations, "Setting up test environment...")

        // Create temp directory
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        // Copy SafariTestRunner folder to temp
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)

        for item in contents where item.lastPathComponent != "node_modules" {
            let destination = runtimeDir.appendingPathComponent(item.lastPathComponent)
            try fileManager.copyItem(at: item, to: destination)
        }

        // Copy performanceMetrics.js (required by build:metrics script)
        // In SPM bundle, it's at bundle root, not in a Resources folder
        let bundleRoot = sourceDir.deletingLastPathComponent()
        let metricsSource = bundleRoot.appendingPathComponent("performanceMetrics.js")

        if fileManager.fileExists(atPath: metricsSource.path) {
            // Create Resources folder in temp and copy the metrics file there
            let resourcesDestination = tempBase.appendingPathComponent("Resources")
            try? fileManager.createDirectory(at: resourcesDestination, withIntermediateDirectories: true)

            let metricsDestination = resourcesDestination.appendingPathComponent("performanceMetrics.js")
            try? fileManager.removeItem(at: metricsDestination) // Remove if exists
            try fileManager.copyItem(at: metricsSource, to: metricsDestination)
            logger.log("Copied performanceMetrics.js: \(metricsSource.path) -> \(metricsDestination.path)")
        } else {
            logger.log("WARNING: performanceMetrics.js not found at \(metricsSource.path)")
        }

        // Install npm dependencies
        try await installDependencies(at: runtimeDir)

        logger.log("Safari test runner ready at \(runtimeDir.path)")
        return runtimeDir
    }

    private func installDependencies(at directory: URL) async throws {
        logger.log("Installing npm dependencies at \(directory.path)...")
        progressHandler?(0, iterations, "Installing dependencies...")

        // Find both node and npm paths
        let nodePath = try await findNodePath()
        let npmPath = try await findNpmPath()

        // Get the directory containing node (for PATH)
        let nodeDir = URL(fileURLWithPath: nodePath).deletingLastPathComponent().path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npmPath)
        process.arguments = ["install", "--production", "--no-audit", "--no-fund"]
        process.currentDirectoryURL = directory

        // Set environment with proper PATH so npm can find node
        var environment = ProcessInfo.processInfo.environment
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "\(nodeDir):\(existingPath)"
        } else {
            environment["PATH"] = nodeDir
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        // Capture output for debugging
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            logger.log("npm install failed with exit code \(exitCode)")
            logger.log("npm stdout: \(outputText)")
            logger.log("npm stderr: \(errorText)")
            throw RunnerError.dependenciesInstallFailed("Exit code: \(exitCode)\n\n\(errorText)")
        }

        // Log output for successful install too
        if !outputText.isEmpty {
            logger.log("npm install output: \(outputText)")
        }

        logger.log("Dependencies installed successfully")
    }

    private func findNpmPath() async throws -> String {
        // First, try using 'which npm' to find whatever is in the user's PATH
        // This works with all node version managers (nvm, fnm, volta, etc.)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which npm"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to common npm installation locations
        let commonPaths = [
            "/usr/local/bin/npm",
            "/opt/homebrew/bin/npm",
            "/usr/bin/npm",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.nvm/versions/node/*/bin/npm"
        ]

        for pathPattern in commonPaths {
            if pathPattern.contains("*") {
                // Handle glob pattern for nvm
                let pathComponents = pathPattern.components(separatedBy: "*")
                if pathComponents.count == 2,
                   let baseURL = URL(string: "file://" + pathComponents[0]),
                   let contents = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
                    for dir in contents {
                        let npmPath = dir.path + pathComponents[1]
                        if FileManager.default.fileExists(atPath: npmPath) {
                            return npmPath
                        }
                    }
                }
            } else if FileManager.default.fileExists(atPath: pathPattern) {
                return pathPattern
            }
        }

        throw RunnerError.npmNotFound
    }

    private func findNodePath() async throws -> String {
        // First, try using 'which node' to find whatever is in the user's PATH
        // This works with all node version managers (nvm, fnm, volta, etc.)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which node"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to common Node.js installation locations
        let commonPaths = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.nvm/versions/node/*/bin/node"
        ]

        for pathPattern in commonPaths {
            if pathPattern.contains("*") {
                // Handle glob pattern for nvm
                let pathComponents = pathPattern.components(separatedBy: "*")
                if pathComponents.count == 2 {
                    let baseDir = pathComponents[0]
                    let suffix = pathComponents[1]

                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: baseDir) {
                        // Sort to get the latest version
                        for version in contents.sorted().reversed() {
                            let nodePath = baseDir + version + suffix
                            if FileManager.default.fileExists(atPath: nodePath) {
                                return nodePath
                            }
                        }
                    }
                }
            } else if FileManager.default.fileExists(atPath: pathPattern) {
                return pathPattern
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
                        self.errorOutput.append(line)
                        // Also show in progress handler so user sees it immediately
                        self.progressHandler?(0, self.iterations, "ERROR: \(line)")
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

    public enum RunnerError: Error, Equatable, Sendable, LocalizedError {
        case invalidIterationCount
        case invalidURL
        case scriptNotFound
        case nodeNotFound
        case npmNotFound
        case dependenciesInstallFailed(String)
        case processExecutionFailed(String)
        case processFailedWithExitCode(Int)
        case processFailedWithError(Int, String)
        case cancelled
        case resultsFileNotFound

        public var errorDescription: String? {
            switch self {
            case .invalidIterationCount:
                return "Invalid iteration count."
            case .invalidURL:
                return "Invalid URL."
            case .scriptNotFound:
                return "Test script not found in bundle."
            case .nodeNotFound:
                return "Node.js not installed. Install from nodejs.org and restart the app."
            case .npmNotFound:
                return "npm not found. Install Node.js from nodejs.org and restart the app."
            case .dependenciesInstallFailed(let details):
                if details.contains("node: No such file or directory") {
                    return "Node.js not installed. Install from nodejs.org and restart the app."
                }
                return "Failed to install dependencies."
            case .processExecutionFailed:
                return "Failed to start test process."
            case .processFailedWithExitCode:
                return "Test process exited with error."
            case .processFailedWithError(_, let details):
                if details.contains("Remote Automation") || details.contains("WebDriver") {
                    return "Enable Remote Automation in Safari → Develop menu."
                }
                return "Test process error."
            case .cancelled:
                return "Test cancelled"
            case .resultsFileNotFound:
                return "Results file not found."
            }
        }

        public static func == (lhs: RunnerError, rhs: RunnerError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidIterationCount, .invalidIterationCount),
                 (.invalidURL, .invalidURL),
                 (.scriptNotFound, .scriptNotFound),
                 (.nodeNotFound, .nodeNotFound),
                 (.npmNotFound, .npmNotFound),
                 (.cancelled, .cancelled),
                 (.resultsFileNotFound, .resultsFileNotFound):
                return true
            case (.dependenciesInstallFailed(let lhsMsg), .dependenciesInstallFailed(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.processExecutionFailed(let lhsMsg), .processExecutionFailed(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.processFailedWithExitCode(let lhsCode), .processFailedWithExitCode(let rhsCode)):
                return lhsCode == rhsCode
            case (.processFailedWithError(let lhsCode, let lhsMsg), .processFailedWithError(let rhsCode, let rhsMsg)):
                return lhsCode == rhsCode && lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }
}
