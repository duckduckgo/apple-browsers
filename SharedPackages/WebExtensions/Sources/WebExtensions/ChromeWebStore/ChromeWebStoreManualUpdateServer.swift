//
//  ChromeWebStoreManualUpdateServer.swift
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

#if DEBUG && os(macOS)
import AppKit
import Foundation

/// Owns the local fixture process and its disposable files; the extension profile lives independently.
@available(macOS 15.4, *)
@MainActor
public final class ChromeWebStoreManualUpdateServer {
    private let testing: ChromeWebStoreManualUpdateTesting
    private let notificationCenter: NotificationCenter
    private var quitObserver: NSObjectProtocol?
    private var process: Process?
    private(set) var directory: URL?

    public var isRunning: Bool { process?.isRunning == true }

    public init(testing: ChromeWebStoreManualUpdateTesting? = nil, notificationCenter: NotificationCenter = .default) {
        self.testing = testing ?? ChromeWebStoreManualUpdateTesting()
        self.notificationCenter = notificationCenter
        quitObserver = notificationCenter.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    deinit {
        if let quitObserver { notificationCenter.removeObserver(quitObserver) }
        Self.cleanup(process: process, directory: directory)
    }

    public func start() async throws -> URL {
        if !isRunning {
            stop()
            let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("ddg-extension-update-testing-" + UUID().uuidString, isDirectory: true)
            self.directory = directory
            do {
                try testing.setUp(serverDirectory: directory)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [directory.appendingPathComponent("serve_updates.py").path]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                self.process = process
                try process.run()
            } catch {
                stop()
                throw error
            }
        }
        guard let process else { throw ServerError.stopped }
        do {
            try await waitUntilReady(process)
            return ChromeWebStoreManualUpdateTesting.controlPageURL
        } catch {
            // A stop followed by a new start while awaiting readiness must not kill the new process.
            if self.process === process { stop() }
            throw error
        }
    }

    public func stop() {
        let process = self.process
        let directory = self.directory
        self.process = nil
        self.directory = nil
        Self.cleanup(process: process, directory: directory)
    }

    private func waitUntilReady(_ process: Process) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            guard self.process === process, process.isRunning else { throw ServerError.stopped }
            if let status = try? await testing.serverStatus() {
                guard self.process === process, process.isRunning else { throw ServerError.stopped }
                guard status.processIdentifier == process.processIdentifier else { throw ServerError.portInUse }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ServerError.timedOut
    }

    private nonisolated static func cleanup(process: Process?, directory: URL?) {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private enum ServerError: LocalizedError {
        case stopped, portInUse, timedOut

        var errorDescription: String? {
            switch self {
            case .stopped: return "The local update server stopped before becoming ready."
            case .portInUse: return "Another process is using the local update server port."
            case .timedOut: return "The local update server did not become ready in time."
            }
        }
    }
}
#endif
