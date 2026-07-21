//
//  ContentScopeScriptResolver.swift
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

import Foundation

/// Resolves a `contentScopeIsolated.js` URL from a local content-scope-scripts checkout (building
/// it) or from a `pr-releases/<branch>` CI build (downloaded at an immutable commit SHA and cached).
enum ContentScopeScriptResolver {

    private static let repoOwner = "duckduckgo"
    private static let repoName = "content-scope-scripts"
    private static let distSubpath = "Sources/ContentScopeScripts/dist/contentScopeIsolated.js"

    // MARK: - Local checkout

    /// Builds (unless `noBuild`) and returns the injected-script URL from a C-S-S checkout at `path`.
    static func fromCheckout(path: String, noBuild: Bool) async throws -> URL {
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let injected = root.appendingPathComponent("injected", isDirectory: true)
        let nodeModules = injected.appendingPathComponent("node_modules", isDirectory: true)

        guard FileManager.default.fileExists(atPath: injected.path) else {
            throw CLIUsageError("No 'injected' directory in checkout: \(injected.path)")
        }
        guard FileManager.default.fileExists(atPath: nodeModules.path) else {
            throw CLIUsageError("node_modules missing in \(injected.path); run npm ci in the checkout first.")
        }

        if noBuild {
            Log.info("Skipping C-S-S build (--css-no-build).")
        } else {
            Log.info("Building content-scope-scripts (node scripts/entry-points.js --platform apple-isolated)…")
            try runNode(arguments: ["scripts/entry-points.js", "--platform", "apple-isolated"],
                        workingDirectory: injected)
        }

        let dist = root.appendingPathComponent(distSubpath)
        guard FileManager.default.fileExists(atPath: dist.path) else {
            throw CLIUsageError("Built artifact not found at \(dist.path). Was the build successful?")
        }
        Log.info("Using injected script: \(dist.path)")
        return dist
    }

    private static func runNode(arguments: [String], workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node"] + arguments
        process.currentDirectoryURL = workingDirectory
        // Node's output is diagnostic; keep it off the result channel by routing to stderr.
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            throw CLIUsageError("Could not launch node: \(error.localizedDescription). Is node installed and on PATH?")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIUsageError("content-scope-scripts build failed (node exited \(process.terminationStatus)).")
        }
    }

    // MARK: - Branch (pr-releases CI build)

    /// Resolves `pr-releases/<branch>` to a commit SHA, downloads the dist artifact at that SHA,
    /// caches it by SHA, and returns the cached URL. `branch` is used verbatim (slashes included).
    static func fromBranch(_ branch: String, urlSession: URLSession = .shared) async throws -> URL {
        let sha = try await resolveSHA(branch: branch, urlSession: urlSession)
        Log.info("pr-releases/\(branch) → \(sha)")

        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("pir-debug-css-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cached = cacheDir.appendingPathComponent("contentScopeIsolated-\(sha).js")

        if FileManager.default.fileExists(atPath: cached.path) {
            Log.info("Using cached injected script for \(sha).")
            return cached
        }

        let rawURL = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/\(sha)/\(distSubpath)")!
        var request = URLRequest(url: rawURL)
        request.httpMethod = "GET"
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIUsageError("Could not download C-S-S artifact for branch \(branch).")
        }
        guard http.statusCode == 200 else {
            throw CLIUsageError("Branch \(branch) has no CI build: dist artifact missing at \(sha) (HTTP \(http.statusCode)).")
        }
        try data.write(to: cached)
        Log.info("Using injected script: \(cached.path)")
        return cached
    }

    private struct CommitResponse: Decodable {
        let sha: String
    }

    private static func resolveSHA(branch: String, urlSession: URLSession) async throws -> String {
        // pr-releases/<branch> is the ref; the branch name is verbatim and may contain slashes.
        let ref = "pr-releases/\(branch)"
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/commits/\(encodedRef)")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("pir-debug", forHTTPHeaderField: "User-Agent")
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIUsageError("Could not reach the GitHub API to resolve branch \(branch).")
        }
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(CommitResponse.self, from: data).sha
        case 404:
            throw CLIUsageError("No pr-releases build for branch '\(branch)' (ref \(ref) not found).")
        case 403:
            throw CLIUsageError("GitHub API rate-limited (unauthenticated limit is 60 req/hr). Set GITHUB_TOKEN to raise it.")
        default:
            throw CLIUsageError("GitHub API error resolving branch \(branch) (HTTP \(http.statusCode)).")
        }
    }
}
