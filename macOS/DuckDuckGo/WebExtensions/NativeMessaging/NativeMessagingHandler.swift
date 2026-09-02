//
//  NativeMessagingHandler.swift
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
import os.log
import WebExtensions
import WebKit

/// Connects extensions to native messaging hosts on macOS.
///
/// This is what makes Bitwarden's biometric unlock work. That flow calls
/// `runtime.connectNative("com.8bit.bitwarden")` and waits for the host to answer over the
/// port. WebKit hands us the port; we run the host and carry messages both ways.
@available(macOS 15.4, *)
@MainActor
final class NativeMessagingHandler: WebExtensionNativeMessagingHandling {

    enum HandlerError: Error, LocalizedError {
        case noApplicationIdentifier
        case permissionMissing(host: String)
        case hostUnavailable(host: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noApplicationIdentifier:
                return "The extension named no native messaging host."
            case .permissionMissing(let host):
                return "The extension has no nativeMessaging permission, so it cannot reach \(host)."
            case .hostUnavailable(let host, let underlying):
                return "The native messaging host \(host) is unavailable: \(underlying.localizedDescription)"
            }
        }
    }

    /// One reply is enough for `sendNativeMessage`, so the wait has a bound.
    private static let singleMessageTimeout: TimeInterval = 10

    /// Sessions of open ports, keyed by the port that owns each one.
    private var sessions: [ObjectIdentifier: NativeMessagingHostSession] = [:]

    // MARK: - WebExtensionNativeMessagingHandling

    func connect(_ port: WKWebExtension.MessagePort,
                 applicationIdentifier: String?,
                 for context: WKWebExtensionContext) async throws {
        let hostName = try hostName(from: applicationIdentifier, for: context)
        let session = try makeSession(hostName: hostName, for: context)

        let key = ObjectIdentifier(port)
        sessions[key] = session

        // Host to extension.
        session.messageHandler = { [weak port] message in
            port?.sendMessage(message) { error in
                if let error {
                    Logger.webExtensions.error("❌ Port send failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        session.terminationHandler = { [weak self, weak port] error in
            self?.sessions[key] = nil
            if let error {
                port?.disconnect(throwing: error)
            } else {
                port?.disconnect()
            }
        }

        // Extension to host.
        port.messageHandler = { [weak session] message, error in
            if let error {
                Logger.webExtensions.error("❌ Port receive failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let message, let session else { return }
            do {
                try session.send(message)
            } catch {
                Logger.webExtensions.error("❌ Message to host rejected: \(error.localizedDescription, privacy: .public)")
            }
        }

        port.disconnectHandler = { [weak self] _ in
            Logger.webExtensions.debug("🔗 Extension closed the port to \(hostName, privacy: .public)")
            self?.sessions[key]?.stop()
            self?.sessions[key] = nil
        }

        try session.start()
        Logger.webExtensions.debug("🔗 Port bridged to \(hostName, privacy: .public)")
    }

    func sendMessage(_ message: Any,
                     applicationIdentifier: String?,
                     for context: WKWebExtensionContext) async throws -> Any? {
        let hostName = try hostName(from: applicationIdentifier, for: context)
        let session = try makeSession(hostName: hostName, for: context)

        defer { session.stop() }

        return try await withThrowingTaskGroup(of: Any?.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    var didResume = false

                    session.messageHandler = { reply in
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(returning: reply)
                    }
                    session.terminationHandler = { error in
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(throwing: error ?? NativeMessagingHostSession.SessionError.hostEnded)
                    }

                    do {
                        try session.start()
                        try session.send(message)
                    } catch {
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(throwing: error)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(Self.singleMessageTimeout))
                Logger.webExtensions.error("❌ Host \(hostName, privacy: .public) did not answer in time")
                return nil
            }

            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Helpers

    private func hostName(from applicationIdentifier: String?,
                          for context: WKWebExtensionContext) throws -> String {
        guard let applicationIdentifier, !applicationIdentifier.isEmpty else {
            throw HandlerError.noApplicationIdentifier
        }

        // WebKit grants `nativeMessaging` only when the manifest asks for it, so this check
        // mirrors the browser's own gate rather than replacing it.
        guard context.hasPermission(.nativeMessaging) else {
            throw HandlerError.permissionMissing(host: applicationIdentifier)
        }

        return applicationIdentifier
    }

    private func makeSession(hostName: String,
                             for context: WKWebExtensionContext) throws -> NativeMessagingHostSession {
        do {
            let located = try NativeMessagingHostManifestLocator.locate(name: hostName)
            return NativeMessagingHostSession(hostName: hostName,
                                              executable: located.executable,
                                              callerOrigin: context.baseURL.absoluteString)
        } catch {
            throw HandlerError.hostUnavailable(host: hostName, underlying: error)
        }
    }
}
