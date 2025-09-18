//
//  main.swift
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
import SmartlingAPIClient
import ArgumentParser

struct Credentials {
    let userId: String
    let userSecret: String
    let projectId: String
}

@main
struct LocalizationTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "localization-tool",
        abstract: "A tool for managing localization workflows with Smartling",
        subcommands: [Upload.self, Status.self, Approve.self, Download.self, Import.self]
    )
}

// MARK: - Options

struct SmartlingOptions: ParsableArguments {
    @Option(name: .long, help: "Smartling user ID")
    var userId: String?

    @Option(name: .long, help: "Smartling user secret")
    var userSecret: String?

    @Option(name: .long, help: "Smartling project ID")
    var projectId: String?

    func validateCredentials() throws -> Credentials {
        let uid = userId ?? ProcessInfo.processInfo.environment["SMARTLING_USER_ID"]
        let secret = userSecret ?? ProcessInfo.processInfo.environment["SMARTLING_USER_SECRET"]
        let proj = projectId ?? ProcessInfo.processInfo.environment["SMARTLING_PROJECT_ID"]

        guard let uid, let secret, let proj else {
            throw ValidationError("Missing required credentials. Provide --user-id, --user-secret, --project-id or set environment variables SMARTLING_USER_ID, SMARTLING_USER_SECRET, SMARTLING_PROJECT_ID")
        }

        return Credentials(userId: uid, userSecret: secret, projectId: proj)
    }
}

// MARK: - Upload Command
struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload translation files to create a translation job"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Job name")
    var jobName: String

    @Option(name: .long, parsing: .upToNextOption, help: "File paths to upload")
    var files: [String] = []

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleUpload(
            jobName: jobName,
            filePaths: files,
            credentials: credentials
        )
    }
}

// MARK: - Status Command
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the status of a translation job"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Job ID")
    var jobId: String

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleStatus(jobId: jobId, credentials: credentials)
    }
}

// MARK: - Approve Command
struct Approve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Approve a translation job"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Job ID")
    var jobId: String

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleApprove(jobId: jobId, credentials: credentials)
    }
}

// MARK: - Download Command
struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download translated files from a job"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Job ID")
    var jobId: String

    @Option(name: .long, help: "Output directory")
    var outDir: String

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleDownload(jobId: jobId, outDir: outDir, credentials: credentials)
    }
}

// MARK: - Command implementation
extension LocalizationTool {
    static func handleUpload(
        jobName: String,
        filePaths: [String],
        credentials: Credentials
    ) async throws {
        guard !filePaths.isEmpty else {
            throw ValidationError("At least one file must be provided")
        }

        // Validate all file paths exist
        for filePath in filePaths {
            guard FileManager.default.fileExists(atPath: filePath) else {
                throw ValidationError("File not found: \(filePath)")
            }
        }

        print("📄 Files to upload:")
        for filePath in filePaths {
            print("   • \(filePath)")
        }

        // Initialize client
        let smartlingCredentials = SmartlingCredentials(userIdentifier: credentials.userId, userSecret: credentials.userSecret, projectId: credentials.projectId)
        let client = SmartlingAPIClient(credentials: smartlingCredentials)
        try await client.authenticate()

        // Get current git branch name
        let branchName = try getCurrentGitBranch()

        // Create job with project's valid locales fetched from Smartling
        let validLocales = try await client.fetchProjectLocales()
        let createJobReq = CreateJobRequest(jobName: jobName, targetLocaleIds: validLocales, description: "Created via LocalizationTool")
        let job = try await client.createJob(createJobReq)
        print("✅ Created job: \(job.jobId)")

        // Prepare declared file URIs for the batch (must be provided up-front)
        let declaredFileUris: [String] = filePaths.map { filePath in
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            return "\(branchName)/\(fileName)"
        }

        // Create batch (not authorizing yet) with declared file URIs
        let batchReq = CreateBatchRequest(authorize: false, translationJobUid: job.jobId, fileUris: declaredFileUris)
        let batch = try await client.createBatch(request: batchReq)
        print("📦 Created batch: \(batch.batchUid)")

        // Upload files into batch using the same declared URIs
        let validLocalesForBatch = try await client.fetchProjectLocales()
        for (index, filePath) in filePaths.enumerated() {
            let fileURL = URL(fileURLWithPath: filePath)
            let fileName = fileURL.lastPathComponent
            let fileUri = declaredFileUris[index]
            let fileData = try Data(contentsOf: fileURL)

            try await client.uploadFileToBatch(batchUid: batch.batchUid, fileData: fileData, fileName: fileName, fileUri: fileUri, localeIds: validLocalesForBatch)
            print("📤 Uploaded to batch: \(fileName)")
        }

        // Poll batch status briefly (with initial delay)
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds for batch to be ready
            var finalStatus = try await client.getBatchStatus(batchUid: batch.batchUid)
            var attempts = 0
            while attempts < 10 && finalStatus.status.lowercased() == "in_progress" {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                finalStatus = try await client.getBatchStatus(batchUid: batch.batchUid)
                attempts += 1
            }
            print("📝 Batch status: \(finalStatus.status)")
        } catch {
            print("⚠️  Could not check batch status: \(error)")
            print("📝 Batch created successfully, status check failed")
        }

        // Machine-readable outputs for CI parsing
        print("JOB_ID=\(job.jobId)")
        print("BATCH_ID=\(batch.batchUid)")
        print("\nDone. Job ID: \(job.jobId)  Batch ID: \(batch.batchUid)")
    }

    // MARK: - Status
    static func handleStatus(jobId: String, credentials: Credentials) async throws {
        let smartlingCredentials = SmartlingCredentials(userIdentifier: credentials.userId, userSecret: credentials.userSecret, projectId: credentials.projectId)
        let client = SmartlingAPIClient(credentials: smartlingCredentials)
        try await client.authenticate()

        let job = try await client.getJob(jobId: jobId)

        print("STATUS=\(job.jobStatus)")
        print("\n📊 Job Status: \(job.jobStatus)")
        print("📋 Job Name: \(job.jobName)")
        print("🎯 Target Locales: \(job.targetLocaleIds.count)")

        // Only try to get progress if job is authorized/in progress
        if job.jobStatus != "AWAITING_AUTHORIZATION" {
            do {
                let progress = try await client.getJobProgress(jobId: jobId)
                print("PERCENT=\(progress.progress.percentComplete)")
                print("📈 Progress: \(progress.progress.percentComplete)%")
            } catch {
                print("PERCENT=0")
                print("⚠️  Could not get progress: \(error)")
            }
        } else {
            print("PERCENT=0")
            print("⏳ Job is awaiting authorization")
        }
        print()
    }

    // MARK: - Approve (with readiness check)
    static func handleApprove(jobId: String, credentials: Credentials) async throws {
        let smartlingCredentials = SmartlingCredentials(userIdentifier: credentials.userId, userSecret: credentials.userSecret, projectId: credentials.projectId)
        let client = SmartlingAPIClient(credentials: smartlingCredentials)
        try await client.authenticate()

        // Check if job is ready for authorization
        print("🔍 Checking job readiness...")
        let job = try await client.getJob(jobId: jobId)

        // Validate job status
        guard job.jobStatus == "AWAITING_AUTHORIZATION" else {
            print("❌ Job is not ready for authorization")
            print("   Current status: \(job.jobStatus)")
            if job.jobStatus == "IN_PROGRESS" {
                print("   💡 Job is already authorized and in progress")
            } else if job.jobStatus == "COMPLETED" {
                print("   ✅ Job is already completed")
            }
            Foundation.exit(1)
        }

        print("✅ Job is ready for authorization")
        print("📋 Job: \(job.jobName)")
        print("🎯 Target locales: \(job.targetLocaleIds.count)")

        // Authorize the job (empty body uses default workflows)
        print("🔄 Authorizing job for translation...")
        do {
            try await client.authorizeJob(jobId: jobId)
            print("APPROVED=1")
            print("✅ Job authorized successfully!")
            print("🚀 Translation will begin for \(job.targetLocaleIds.count) locales")
        } catch {
            let errorMessage = "\(error)"
            if errorMessage.contains("Job has no content") {
                print("APPROVED=0")
                print("ℹ️  Job has no new content to translate")
                print("✅ All strings are already translated - no action needed")
            } else {
                print("APPROVED=0")
                print("❌ Authorization failed: \(error)")
                Foundation.exit(1)
            }
        }
    }

    // MARK: - Download
    static func handleDownload(jobId: String, outDir: String, credentials: Credentials) async throws {
        let smartlingCredentials = SmartlingCredentials(userIdentifier: credentials.userId, userSecret: credentials.userSecret, projectId: credentials.projectId)
        let client = SmartlingAPIClient(credentials: smartlingCredentials)
        try await client.authenticate()

        print("🔍 Getting job details...")
        let job = try await client.getJob(jobId: jobId)
        print("📋 Job: \(job.jobName)")
        print("📊 Job Status: \(job.jobStatus)")

        // Check if job is complete
        guard job.jobStatus == "COMPLETED" else {
            print("DOWNLOADED=0")
            print("⚠️  Job is not completed (status: \(job.jobStatus)). Only completed jobs can be downloaded.")
            return
        }

        // Discover all files in the job
        print("🔍 Discovering files in job...")
        let jobFiles = try await client.getJobFiles(jobId: jobId)

        guard !jobFiles.isEmpty else {
            print("DOWNLOADED=0")
            print("⚠️  No files found in job \(jobId)")
            return
        }

        let fileUris = jobFiles.map { $0.fileUri }
        print("📁 Found \(jobFiles.count) files in job:")
        for file in jobFiles {
            print("   • \(file.uri) (\(file.name))")
        }

        print("📁 Attempting to download files: \(fileUris)")
        print("🎯 Target locales: \(job.targetLocaleIds.count)")

        do {
            let downloadedFiles = try await client.downloadTranslatedFiles(forJob: jobId, fileUris: fileUris)

            if downloadedFiles.isEmpty {
                print("DOWNLOADED=0")
                print("⚠️  No files downloaded - they may not exist or have different URIs")
                return
            }

            print("💾 Saving \(downloadedFiles.count) files to \(outDir)...")

            // Create output directory if it doesn't exist
            let outputURL = URL(fileURLWithPath: outDir)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            for file in downloadedFiles {
                let fileURL = outputURL.appendingPathComponent(file.fileName)
                try file.data.write(to: fileURL)
                print("✅ \(file.fileName) (\(file.localeId))")
            }

            print("DOWNLOADED=\(downloadedFiles.count)")
            print("🎉 Downloaded \(downloadedFiles.count) files to \(outDir)")

        } catch {
            print("DOWNLOADED=0")
            print("❌ Download failed: \(error)")
            Foundation.exit(1)
        }
    }
}

// MARK: - Import Command

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Import translated files using loc_import.sh"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Directory containing translated files")
    var importDir: String

    @Flag(name: .long, help: "Skip safety checks and force import")
    var force: Bool = false

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleImport(importDir: importDir, force: force, credentials: credentials)
    }
}

// MARK: - Import Handler

extension LocalizationTool {
    static func handleImport(importDir: String, force: Bool, credentials: Credentials) async throws {
        print("🔍 Starting import from \(importDir)")

        // Verify import directory exists
        guard FileManager.default.fileExists(atPath: importDir) else {
            print("IMPORTED=0")
            print("❌ Import directory does not exist: \(importDir)")
            Foundation.exit(1)
        }

        // Get all translation files
        let importURL = URL(fileURLWithPath: importDir)
        let translationFiles: [URL]
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: importURL, includingPropertiesForKeys: nil)
            translationFiles = contents.filter { $0.pathExtension == "xliff" || $0.pathExtension == "stringsdict" }
        } catch {
            print("IMPORTED=0")
            print("❌ Failed to read import directory: \(error)")
            Foundation.exit(1)
        }

        guard !translationFiles.isEmpty else {
            print("IMPORTED=0")
            print("⚠️  No translation files found in \(importDir)")
            return
        }

        print("📋 Found \(translationFiles.count) translation files")

        // Separate XLIFFs and stringsdicts
        let xliffFiles = translationFiles.filter { $0.pathExtension == "xliff" }
        let stringsdictFiles = translationFiles.filter { $0.pathExtension == "stringsdict" }

        let scriptPath = "../../iOS/scripts/loc_import.sh"
        var totalImported = 0

        // Process XLIFFs first
        if !xliffFiles.isEmpty {
            print("📋 Processing \(xliffFiles.count) XLIFF files first...")
            let xliffTempDir = try reorganizeFiles(translationFiles: xliffFiles)
            let baseName = extractBaseName(from: xliffFiles[0].lastPathComponent)

            let xliffProcess = Process()
            xliffProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            xliffProcess.arguments = [scriptPath, xliffTempDir.path, baseName]

            print("📞 Calling loc_import.sh for XLIFFs...")
            try xliffProcess.run()
            xliffProcess.waitUntilExit()

            // Clean up temp directory
            try? FileManager.default.removeItem(at: xliffTempDir)

            guard xliffProcess.terminationStatus == 0 else {
                print("IMPORTED=0")
                print("❌ XLIFF import failed with exit code \(xliffProcess.terminationStatus)")
                Foundation.exit(1)
            }

            totalImported += xliffFiles.count
            print("✅ Successfully imported \(xliffFiles.count) XLIFF files")
        }

        // Then process stringsdicts
        if !stringsdictFiles.isEmpty {
            print("📋 Processing \(stringsdictFiles.count) stringsdict files...")
            let stringsdictTempDir = try reorganizeFiles(translationFiles: stringsdictFiles)
            let baseName = extractBaseName(from: stringsdictFiles[0].lastPathComponent)

            let stringsdictProcess = Process()
            stringsdictProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            stringsdictProcess.arguments = [scriptPath, stringsdictTempDir.path, baseName]

            print("📞 Calling loc_import.sh for stringsdicts...")
            try stringsdictProcess.run()
            stringsdictProcess.waitUntilExit()

            // Clean up temp directory
            try? FileManager.default.removeItem(at: stringsdictTempDir)

            guard stringsdictProcess.terminationStatus == 0 else {
                print("IMPORTED=0")
                print("❌ stringsdict import failed with exit code \(stringsdictProcess.terminationStatus)")
                Foundation.exit(1)
            }

            totalImported += stringsdictFiles.count
            print("✅ Successfully imported \(stringsdictFiles.count) stringsdict files")
        }

        print("IMPORTED=\(totalImported)")
        print("🎉 Successfully imported \(totalImported) translation files")
    }

    static func reorganizeFiles(translationFiles: [URL]) throws -> URL {
        // Create temp directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("smartling-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for file in translationFiles {
            let fileName = file.lastPathComponent

            // Extract locale from "filename_locale.xliff" format
            let components = fileName.components(separatedBy: "_")
            guard components.count >= 2 else { continue }

            let localeComponent = components.last ?? ""
            let locale = localeComponent.components(separatedBy: ".").first ?? ""
            let baseName = extractBaseName(from: fileName)
            let ext = file.pathExtension

            // Create locale directory
            let localeDir = tempDir.appendingPathComponent(locale)
            try FileManager.default.createDirectory(at: localeDir, withIntermediateDirectories: true)

            // Copy file with correct name
            let targetPath = localeDir.appendingPathComponent("\(baseName).\(ext)")
            try FileManager.default.copyItem(at: file, to: targetPath)
        }

        return tempDir
    }

    static func extractBaseName(from fileName: String) -> String {
        // Extract base name from "filename_locale.xliff" -> "filename"
        let components = fileName.components(separatedBy: "_")
        guard components.count >= 2 else { return fileName }
        return components.dropLast().joined(separator: "_")
    }
}

// MARK: - Helper Functions

func getCurrentGitBranch() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw ValidationError("Failed to get git branch name")
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !output.isEmpty else {
        throw ValidationError("Git branch name is empty")
    }

    return output
}
