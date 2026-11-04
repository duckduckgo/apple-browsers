//
//  ConfigurationDebugOptions.swift
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

import Combine
import Configuration
import DebugOptions
import Foundation

/// URL persistence is shared; each app supplies its own configuration download and processing operation.
@MainActor
public final class ConfigurationDebugOptions {
    public typealias Refresh = @MainActor (Configuration) async throws -> DebugValue
    private let urlProvider: CustomConfigurationURLProviding
    private let configurations: [Configuration]
    private let refreshHandler: Refresh
    private var inProgress = Set<Configuration>()
    private var refreshDates: [Configuration: Date] = [:]
    private var refreshResults: [Configuration: DebugValue] = [:]
    private let changeSubject = PassthroughSubject<Void, Never>()
    public var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    public init(urlProvider: CustomConfigurationURLProviding, configurations: [Configuration], refresh: @escaping Refresh) {
        self.urlProvider = urlProvider
        self.configurations = configurations
        self.refreshHandler = refresh
    }

    public func lastRefreshDate(for configuration: Configuration) -> Date? {
        refreshDates[configuration]
    }

    public func state(for configuration: Configuration) -> DebugValue {
        let state = urlProvider.state(for: configuration)
        return .object([
            "savedOverrideURL": state.savedOverrideURL.map { .string($0.absoluteString) } ?? .null,
            "sessionOverrideURL": state.sessionOverrideURL.map { .string($0.absoluteString) } ?? .null,
            "defaultURL": .string(state.defaultURL.absoluteString),
            "resolvedURL": .string(state.resolvedURL.absoluteString),
            "overridesEnabled": .bool(state.overridesEnabled),
            "refreshInProgress": .bool(inProgress.contains(configuration)),
            "lastRefresh": refreshResults[configuration] ?? .null,
        ])
    }

    public func setURL(_ value: String, for configuration: Configuration) async throws -> DebugValue {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else {
            throw DebugOptionError(code: .invalidParameters, message: "Use an HTTP(S) URL with a host and no embedded credentials.")
        }
        return try await update(configuration, newURL: url)
    }

    public func reset(_ configuration: Configuration) async throws -> DebugValue {
        try await update(configuration, newURL: nil)
    }

    public func refresh(_ configuration: Configuration) async throws -> DebugValue {
        try requireAvailable(configuration)
        inProgress.insert(configuration)
        defer { inProgress.remove(configuration); changeSubject.send() }
        return try await performRefresh(configuration, overrideSaved: false)
    }

    public func register(in registry: DebugOptionRegistry) throws {
        for configuration in configurations {
            let descriptor = DebugOptionDescriptor(id: "configuration.\(configuration.rawValue).url",
                                                   title: configuration.rawValue, group: "Configuration", activation: "afterRefresh", actions: [
                .init(id: "get", description: "Read saved, session, and resolved URLs and the last refresh result."),
                .init(id: "set", description: "Save a URL override, then fetch and process the configuration.",
                      parametersSchema: .init(properties: ["value": .init(type: .string, description: "HTTP(S) URL with a host")], required: ["value"])),
                .init(id: "reset", description: "Remove the saved override, then refresh from the default URL."),
                .init(id: "refresh", description: "Fetch and process configuration from the resolved URL."),
            ])
            try registry.register(descriptor, availability: { [self] action in
                action == "get" ? nil : availabilityError(configuration, changingURL: action != "refresh")
            }, handlers: [
                "get": { [self] _ in state(for: configuration) },
                "set": { [self] parameters in
                    guard case .string(let url) = parameters["value"] else {
                        throw DebugOptionError(code: .invalidParameters, message: "A URL value is required.")
                    }
                    return try await setURL(url, for: configuration)
                },
                "reset": { [self] _ in try await reset(configuration) },
                "refresh": { [self] _ in try await refresh(configuration) },
            ])
        }
    }

    private func update(_ configuration: Configuration, newURL: URL?) async throws -> DebugValue {
        try requireAvailable(configuration, changingURL: true)
        try urlProvider.setCustomURL(newURL, for: configuration)
        inProgress.insert(configuration)
        changeSubject.send()
        defer { inProgress.remove(configuration); changeSubject.send() }
        return try await performRefresh(configuration, overrideSaved: true)
    }

    private func performRefresh(_ configuration: Configuration, overrideSaved: Bool) async throws -> DebugValue {
        let sourceURL = urlProvider.url(for: configuration)
        do {
            try Task.checkCancellation()
            let result = try await refreshHandler(configuration)
            let completedAt = Date()
            refreshDates[configuration] = completedAt
            refreshResults[configuration] = .object(["status": .string("completed"), "result": result,
                                                       "completedAt": .string(ISO8601DateFormatter().string(from: completedAt)),
                                                       "sourceURL": .string(sourceURL.absoluteString)])
            // The response describes the state after this operation releases its mutation lock.
            inProgress.remove(configuration)
            return state(for: configuration)
        } catch {
            refreshResults[configuration] = .object(["status": .string("failed"), "message": .string(error.localizedDescription)])
            inProgress.remove(configuration)
            throw DebugOptionError(code: .refreshFailed, message: error.localizedDescription,
                                   details: .object(["overrideSaved": .bool(overrideSaved), "state": state(for: configuration)]))
        }
    }

    private func availabilityError(_ configuration: Configuration, changingURL: Bool) -> DebugOptionError? {
        if !urlProvider.isCustomURLEnabled {
            return .init(code: .unavailable, message: "Enable general.internalUser first.")
        }
        if inProgress.contains(configuration) {
            return .init(code: .busy, message: "A configuration operation is already running.")
        }
        if changingURL && urlProvider.state(for: configuration).sessionOverrideURL != nil {
            return .init(code: .conflict, message: "A launch-session override masks this setting. Relaunch without that override first.")
        }
        return nil
    }

    private func requireAvailable(_ configuration: Configuration, changingURL: Bool = false) throws {
        guard configurations.contains(configuration) else {
            throw DebugOptionError(code: .unknownOption, message: "Unsupported configuration.")
        }
        if let error = availabilityError(configuration, changingURL: changingURL) { throw error }
    }
}
