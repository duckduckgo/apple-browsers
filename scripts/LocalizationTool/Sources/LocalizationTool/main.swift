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
        subcommands: [Upload.self, Status.self, Approve.self, Download.self]
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
        abstract: "Upload XLIFF and stringsdict files to create a translation job"
    )

    @OptionGroup var smartling: SmartlingOptions

    @Option(name: .long, help: "Job name")
    var jobName: String

    @Option(name: .long, help: "XLIFF file path")
    var xliff: String

    @Option(name: .long, help: "Stringsdict file path")
    var stringsdict: String

    func run() async throws {
        let credentials = try smartling.validateCredentials()
        try await LocalizationTool.handleUpload(
            jobName: jobName,
            xliffPath: xliff,
            stringsdictPath: stringsdict,
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
        xliffPath: String,
        stringsdictPath: String,
        credentials: Credentials
    ) async throws {
        let xliffURL = URL(fileURLWithPath: xliffPath)
        let stringsdictURL = URL(fileURLWithPath: stringsdictPath)

        let xliffData = try Data(contentsOf: xliffURL)
        let fileName = xliffURL.lastPathComponent
        print("📄 XLIFF: \(xliffURL.path)")

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
        let fileUri = "\(branchName)/\(fileName)"
        let sdName = stringsdictURL.lastPathComponent
        let sdUri = "\(branchName)/\(sdName)"
        let declaredFileUris: [String] = [fileUri, sdUri]

        // Create batch (not authorizing yet) with declared file URIs
        let batchReq = CreateBatchRequest(authorize: false, translationJobUid: job.jobId, fileUris: declaredFileUris)
        let batch = try await client.createBatch(request: batchReq)
        print("📦 Created batch: \(batch.batchUid)")

        // Upload files into batch using the same declared URIs
        let validLocalesForBatch = try await client.fetchProjectLocales()
        try await client.uploadFileToBatch(batchUid: batch.batchUid, fileData: xliffData, fileName: fileName, fileUri: fileUri, localeIds: validLocalesForBatch)
        print("📤 Uploaded to batch: \(fileName)")

        let stringsdictData = try Data(contentsOf: stringsdictURL)
        try await client.uploadFileToBatch(batchUid: batch.batchUid, fileData: stringsdictData, fileName: sdName, fileUri: sdUri, localeIds: validLocalesForBatch)
        print("📤 Uploaded to batch: \(sdName)")

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

    // MARK: - Download (stub)
    static func handleDownload(jobId: String, outDir: String, credentials: Credentials) async throws {
        // Note: Download implementation pending - requires batch file listing
        let smartlingCredentials = SmartlingCredentials(userIdentifier: credentials.userId, userSecret: credentials.userSecret, projectId: credentials.projectId)
        let client = SmartlingAPIClient(credentials: smartlingCredentials)
        try await client.authenticate()

        print("DOWNLOADED=0")
        print("⚠️  Download not implemented yet for job \(jobId). Add batch file discovery + download.")
        Foundation.exit(2)
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
