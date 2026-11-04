//
//  IOSDebugOptions.swift
//  DuckDuckGo
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

import BrowserDebugOptions
import Combine
import Configuration
import Core
import DebugOptions
import FeatureFlags_iOS
import Foundation
import PrivacyConfig
import os.log
#if DEBUG
import DebugServer
#endif

/// Shares option providers between the debug menu and the developer-only HTTP server.
@MainActor
final class IOSDebugOptions: ObservableObject {
    static let shared = IOSDebugOptions()
    let objectWillChange = ObservableObjectPublisher()
    private static let logger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "DebugOptions")
    let featureFlags: FeatureFlagDebugOptions<FeatureFlag>
    private static var remoteMessagingRefresh: (() async throws -> Void)?
    private var cancellables = Set<AnyCancellable>()

    lazy var configurations = ConfigurationDebugOptions(
        urlProvider: AppDependencyProvider.shared.configurationURLProvider,
        configurations: [.privacyConfiguration, .remoteMessagingConfig]
    ) { configuration in
        // Force a complete debug fetch when switching sources; an old source's ETag must not reuse its data.
        try AppDependencyProvider.shared.configurationStore.saveEtag("", for: configuration)
        switch configuration {
        case .privacyConfiguration:
            guard try await AppDependencyProvider.shared.configurationManager.fetchPrivacyConfiguration() else {
                throw DebugOptionError(code: .refreshFailed, message: "The downloaded privacy configuration was not applied; the app used its embedded fallback.")
            }
            let config = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
            return .object(["processed": .bool(true), "version": config.version.map(DebugValue.string) ?? .null,
                            "etag": .string(config.identifier), "contentBlockerCompilation": .string("scheduled")])
        case .remoteMessagingConfig:
            guard let refresh = Self.remoteMessagingRefresh else {
                throw DebugOptionError(code: .unavailable, message: "Remote messaging has not initialized.")
            }
            try await refresh()
            return .object(["processed": .bool(true)])
        default:
            throw DebugOptionError(code: .unavailable, message: "This configuration cannot be refreshed by the iOS adapter.")
        }
    }

    private init() {
        let flagger = AppDependencyProvider.shared.featureFlagger
        featureFlags = FeatureFlagDebugOptions(featureFlagger: flagger, flags: FeatureFlag.allCases,
                                               requiresRelaunch: { $0 == .sitePermissions || $0 == .promoPresentationCoordination })
        featureFlags.changes.merge(with: configurations.changes).sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    static func configure(remoteMessagingService: RemoteMessagingService) {
        remoteMessagingRefresh = { try await remoteMessagingService.refreshRemoteMessagesForDebug() }
        #if DEBUG
        shared.startServer()
        #endif
    }

    var isInternalUser: Bool { featureFlags.featureFlagger.internalUserDecider.isInternalUser }

    func setInternalUser(_ value: Bool) {
        guard isInternalUser != value else { return }
        (featureFlags.featureFlagger.internalUserDecider as? DefaultInternalUserDecider)?.debugSetInternalUserState(value)
        objectWillChange.send()
    }

    func report(_ error: Error) {
        ActionMessageView.present(message: error.localizedDescription)
    }

    #if DEBUG
    private func registerInternalUser(in registry: DebugOptionRegistry) throws {
        try registry.register(.init(id: "general.internalUser", title: "Internal User", group: "General", activation: "nextFeatureEvaluation", actions: [
            .init(id: "get", description: "Read the app's internal-user debug state. This state never authorizes the HTTP server."),
            .init(id: "set", description: "Set internal-user debug state to enable feature and configuration overrides.",
                  parametersSchema: .init(properties: ["value": .init(type: .boolean)], required: ["value"])),
        ]), handlers: [
            "get": { [weak self] _ in .object(["value": .bool(self?.isInternalUser ?? false)]) },
            "set": { [weak self] parameters in
                guard let self, case .bool(let value) = parameters["value"] else {
                    throw DebugOptionError(code: .invalidParameters, message: "A Boolean value is required.")
                }
                setInternalUser(value)
                return .object(["value": .bool(isInternalUser)])
            },
        ])
    }

    private var server: DebugHTTPServer?
    private var sessionFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugOptions/session.json")
    }

    private func startServer() {
        guard server == nil else { return }
        try? FileManager.default.removeItem(at: sessionFileURL)
        let token = UUID().uuidString + UUID().uuidString
        do {
            let registry = DebugOptionRegistry()
            try featureFlags.register(in: registry)
            try configurations.register(in: registry)
            try registerInternalUser(in: registry)
            let handler = try DebugOptionsHTTPHandler(registry: registry, token: token)
            let newServer = DebugHTTPServer(port: 8475, loopbackOnly: true)
            handler.register(on: newServer)
            newServer.stateDidChange = { [weak self] state in
                Task { @MainActor in self?.updateServerState(state, token: token) }
            }
            server = newServer
            try newServer.start()
        } catch {
            stopServer()
            Self.logger.error("Debug options server startup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopServer() {
        server?.stateDidChange = nil
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: sessionFileURL)
    }

    private func updateServerState(_ state: ServerState, token: String) {
        guard server != nil else { return }
        switch state {
        case .running(let port):
            let endpoint = "http://127.0.0.1:\(port)/api/v1/debug-options"
            do {
                let directory = sessionFileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let data = try JSONSerialization.data(withJSONObject: ["url": endpoint, "token": token])
                try data.write(to: sessionFileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path)
                Self.logger.notice("Debug options API ready at \(endpoint, privacy: .public); credentials in Library/Caches/DebugOptions/session.json")
            } catch {
                stopServer()
                Self.logger.error("Could not write debug connection details: \(error.localizedDescription, privacy: .public)")
            }
        case .failed(let message):
            stopServer()
            Self.logger.error("Debug options server failed: \(message, privacy: .public)")
        default: break
        }
    }
    #endif
}
