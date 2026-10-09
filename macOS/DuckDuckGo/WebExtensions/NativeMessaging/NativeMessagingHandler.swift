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
/// An extension calls `runtime.connectNative` or `runtime.sendNativeMessage` with a host name.
/// WebKit hands us the port or the message; we run the host and carry messages both ways.
@available(macOS 15.4, *)
@MainActor
final class NativeMessagingHandler: WebExtensionNativeMessagingHandling {

    enum HandlerError: Error, LocalizedError {
        case containingApplicationRoute
        case permissionMissing(host: String)
        case hostUnavailable(host: String, underlying: Error)
        case originNotAllowed(host: String, origin: String?)
        case timedOut(host: String)

        var errorDescription: String? {
            switch self {
            case .containingApplicationRoute:
                return "The extension named no host, so it wants its own containing app. "
                    + "Safari answers that from the app extension, and we have no such app."
            case .permissionMissing(let host):
                return "The extension has no nativeMessaging permission, so it cannot reach \(host)."
            case .hostUnavailable(let host, let underlying):
                return "The native messaging host \(host) is unavailable: \(underlying.localizedDescription)"
            case .originNotAllowed(let host, let origin):
                return "The native messaging host \(host) does not allow "
                    + "\(origin ?? "an extension with no manifest key") to connect."
            case .timedOut(let host):
                return "The native messaging host \(host) did not answer in time."
            }
        }
    }

    /// One reply is enough for `sendNativeMessage`, so the wait has a bound.
    static let defaultSingleMessageTimeout: TimeInterval = 10

    private let singleMessageTimeout: TimeInterval

    /// Where an extension came from, which gives the Chrome identifier of a Web Store install.
    private let installationStore: InstalledWebExtensionStoring?

    init(installationStore: InstalledWebExtensionStoring? = nil,
         singleMessageTimeout: TimeInterval = NativeMessagingHandler.defaultSingleMessageTimeout) {
        self.installationStore = installationStore
        self.singleMessageTimeout = singleMessageTimeout
    }

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
            guard let port else {
                Logger.webExtensions.error("❌ Host \(hostName, privacy: .public) sent a message but its port is gone")
                return
            }
            port.sendMessage(message) { error in
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

        return try await Self.exchange(message, with: session, hostName: hostName, timeout: singleMessageTimeout)
    }

    /// Sends one message and returns the first reply.
    ///
    /// Ends with the first of a reply, the host ending or failing, and the timeout. Every
    /// exit stops the session, so no host process outlives the call.
    static func exchange(_ message: Any,
                         with session: NativeMessagingHostSession,
                         hostName: String,
                         timeout: TimeInterval) async throws -> Any? {
        defer { session.stop() }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var timeoutTask: Task<Void, Never>?

            func finish(_ result: Result<Any?, Error>) {
                guard !didResume else { return }
                didResume = true
                timeoutTask?.cancel()
                continuation.resume(with: result)
            }

            session.messageHandler = { reply in
                finish(.success(reply))
            }
            session.terminationHandler = { error in
                finish(.failure(error ?? NativeMessagingHostSession.SessionError.hostEnded))
            }

            timeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                Logger.webExtensions.error("❌ Host \(hostName, privacy: .public) did not answer in time")
                finish(.failure(HandlerError.timedOut(host: hostName)))
            }

            do {
                try session.start()
                try session.send(message)
            } catch {
                finish(.failure(error))
            }
        }
    }

    // MARK: - Helpers

    private func hostName(from applicationIdentifier: String?,
                          for context: WKWebExtensionContext) throws -> String {
        // An empty identifier means the containing app of a Safari app extension. Safari
        // answers those from the app extension's own handler class, which is an NSExtension
        // and not a host process. Those calls cannot succeed here, whereas
        // a Chrome build names a real host.
        guard let applicationIdentifier, !applicationIdentifier.isEmpty else {
            Logger.webExtensions.error("""
            ❌ \(context.webExtension.displayName ?? "An extension", privacy: .public) \
            asks its containing app, not a native messaging host. That route needs Safari.
            """)
            throw HandlerError.containingApplicationRoute
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
        let located: (manifest: NativeMessagingHostManifest, executable: URL)
        do {
            located = try NativeMessagingHostManifestLocator.locate(name: hostName)
        } catch {
            throw HandlerError.hostUnavailable(host: hostName, underlying: error)
        }

        let origin = try callerOrigin(for: context, hostName: hostName, manifest: located.manifest)
        return NativeMessagingHostSession(hostName: hostName,
                                          executable: located.executable,
                                          callerOrigin: origin)
    }

    /// Picks the origin to hand the host as its first argument.
    ///
    /// A host manifest lists the extensions it trusts as `chrome-extension://<id>/` origins in
    /// `allowed_origins`, and a host checks its argument against that list. So we present the
    /// extension's Chrome origin, and refuse the connection ourselves when the manifest has no
    /// list or the list lacks that origin.
    private func callerOrigin(for context: WKWebExtensionContext,
                              hostName: String,
                              manifest: NativeMessagingHostManifest) throws -> String {
        let chromeOrigin = context.webExtension.chromeExtensionOrigin ?? webStoreOrigin(of: context)

        // A missing or empty list trusts nobody, so it must not fall through.
        guard let chromeOrigin, manifest.allowedOrigins?.contains(chromeOrigin) == true else {
            throw HandlerError.originNotAllowed(host: hostName, origin: chromeOrigin)
        }

        return chromeOrigin
    }

    /// The Chrome origin of an extension installed from the Chrome Web Store, whose manifest carries no `key`:
    /// the Web Store keeps it in the package header instead.
    private func webStoreOrigin(of context: WKWebExtensionContext) -> String? {
        guard let identity = installationStore?.installedExtension(withUniqueIdentifier: context.uniqueIdentifier)?.storeIdentity,
              identity.store == .chromeWebStore else { return nil }
        return "chrome-extension://\(identity.id)/"
    }
}
