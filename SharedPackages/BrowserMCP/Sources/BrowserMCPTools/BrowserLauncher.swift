//
//  BrowserLauncher.swift
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

public enum BrowserLauncherError: Error, Equatable, CustomStringConvertible {
    case appNotFound(String)
    case notReady(TimeInterval)

    public var description: String {
        switch self {
        case .appNotFound(let path):
            return "No launchable browser found at \(path). Set DDG_APP_PATH or pass app_path to browser_launch."
        case .notReady(let timeout):
            return "The browser did not report its content blocker ready within \(Int(timeout))s."
        }
    }
}

/// Starts the browser so the automation server comes up. Abstracted for tests.
public protocol BrowserLaunching: Sendable {
    func launch(appPath: String, port: Int, authToken: String?) throws
}

/// Launches the app bundle's executable directly (not via `open`) so that the environment,
/// including an optional `AUTOMATION_TOKEN`, is inherited by the browser process.
public struct ProcessBrowserLauncher: BrowserLaunching {
    public init() {}

    public func launch(appPath: String, port: Int, authToken: String?) throws {
        guard let bundle = Bundle(path: appPath), let executableURL = bundle.executableURL else {
            throw BrowserLauncherError.appNotFound(appPath)
        }
        let process = Process()
        process.executableURL = executableURL
        // LaunchOptionsHandler reads `automationPort` from UserDefaults, which picks up `-key value` arguments.
        process.arguments = ["-automationPort", String(port)]
        var environment = ProcessInfo.processInfo.environment
        if let authToken, !authToken.isEmpty {
            environment["AUTOMATION_TOKEN"] = authToken
        } else {
            environment.removeValue(forKey: "AUTOMATION_TOKEN")
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

public enum BrowserReadiness {
    /// Polls `/contentBlockerReady` until the browser answers `true`, mirroring what WebDriver clients do before a session.
    public static func waitUntilReady(transport: AutomationTransport,
                                      timeout: TimeInterval,
                                      pollInterval: TimeInterval = 0.5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = try? await transport.get("/contentBlockerReady"), response.message == "true" {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw BrowserLauncherError.notReady(timeout)
    }
}
