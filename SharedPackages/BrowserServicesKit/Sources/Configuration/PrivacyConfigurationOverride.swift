//
//  PrivacyConfigurationOverride.swift
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
import PrivacyConfig

/// The `-privacyConfigURL <url>` launch argument, used by local tooling to point the browser at a locally built privacy configuration.
///
/// The override lasts for one launch: it is not persisted, so a launch without the argument fetches production again.
/// Only internal users can use it.
public enum PrivacyConfigurationOverrideArgument {

    public static let launchArgumentKey = "privacyConfigURL"

    /// Parses the argument without logging. Returns nil unless the value is an http(s) URL with a host.
    public static func url(fromLaunchArgument value: String?) -> URL? {
        guard let value,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// Remembers that the stored privacy configuration came from a launch-argument override,
/// so the next launch without the argument replaces it with production.
public struct PrivacyConfigurationOverrideMarker {

    private static let key = "PrivacyConfigurationOverride.storedFromLaunchArgument"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isSet: Bool {
        defaults.bool(forKey: Self.key)
    }

    func set(_ isSet: Bool) {
        defaults.set(isSet, forKey: Self.key)
    }

    /// Drops a stored privacy configuration that came from an earlier override, when this launch has no valid argument.
    ///
    /// Call it before anything reads the stored configuration, so the app starts on its embedded configuration
    /// and fetches production as usual.
    /// - Returns: true when the stored configuration was removed.
    @discardableResult
    public func resetIfNeeded(userDefaults: UserDefaults, removeStoredConfiguration: () -> Void) -> Bool {
        guard isSet else { return false }
        let argument = userDefaults.string(forKey: PrivacyConfigurationOverrideArgument.launchArgumentKey)
        guard PrivacyConfigurationOverrideArgument.url(fromLaunchArgument: argument) == nil else { return false }
        removeStoredConfiguration()
        set(false)
        Logger.config.log("privacy config override: removed stored override configuration")
        return true
    }
}

/// Handles the launch argument and logs one `CONFIG_OVERRIDE_APPLIED` or `CONFIG_OVERRIDE_FAILED` line for it.
/// Local tooling waits for these lines.
public final class PrivacyConfigurationOverrideHandler {

    static let logPrefix = "CONFIG_OVERRIDE_APPLIED"

    static func logLine(version: String?, etag: String, source: URL) -> String {
        let fields = [
            "stage=config",
            "version=\(sanitized(version ?? "unknown"))",
            "etag=\(sanitized(etag))",
            "source=\(sanitized(source.absoluteString))",
        ]
        return ([logPrefix] + fields).joined(separator: " ")
    }

    /// Values are unquoted and space-separated, so drop quotes (ETags are usually quoted) and whitespace.
    private static func sanitized(_ value: String) -> String {
        value.filter { $0 != "\"" && !$0.isWhitespace }
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let urlProvider: CustomConfigurationURLSetting
    private let overrideMarker: PrivacyConfigurationOverrideMarker
    private let log: (String) -> Void
    private let logError: (String) -> Void

    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                urlProvider: CustomConfigurationURLSetting,
                overrideMarker: PrivacyConfigurationOverrideMarker,
                log: @escaping (String) -> Void = { Logger.config.log("\($0, privacy: .public)") },
                logError: @escaping (String) -> Void = { Logger.config.error("\($0, privacy: .public)") }) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.urlProvider = urlProvider
        self.overrideMarker = overrideMarker
        self.log = log
        self.logError = logError
    }

    /// Sets the override for this launch, then runs `fetch` in a task.
    ///
    /// `fetch` must fetch and apply the privacy configuration, and return true when the applied configuration is
    /// the downloaded one. Without an argument there is nothing to do: `PrivacyConfigurationOverrideMarker.resetIfNeeded`
    /// has already dropped any stored override. Call this on every cold launch, before any scheduled refresh.
    /// - Returns: the fetch task, or nil when there is nothing to fetch.
    @discardableResult
    public func handle(argument: String?, fetch: @escaping () async throws -> Bool) -> Task<Void, Never>? {
        guard let argument else { return nil }
        guard let url = PrivacyConfigurationOverrideArgument.url(fromLaunchArgument: argument) else {
            // The raw argument without whitespace, so the value stays one field of the log line.
            logFailure(.invalidURL, source: argument.filter { !$0.isWhitespace })
            return nil
        }
        guard urlProvider.isCustomURLEnabled else {
            logFailure(.notInternal, source: url.absoluteString)
            return nil
        }
        urlProvider.setSessionURL(url, for: .privacyConfiguration)
        // Set before the fetch: any later fetch this launch, including a scheduled refresh, stores the override config.
        overrideMarker.set(true)
        Logger.config.log("privacy config override: launch argument handled")

        return Task {
            Logger.config.log("privacy config override: fetch started")
            // False means the app fell back to the embedded configuration, so nothing from the override was applied.
            guard (try? await fetch()) == true else {
                logFailure(.downloadFailed, source: url.absoluteString)
                return
            }
            Logger.config.log("privacy config override: fetch finished")
            let privacyConfig = privacyConfigurationManager.privacyConfig
            log(Self.logLine(version: privacyConfig.version, etag: privacyConfig.identifier, source: url))
        }
    }

    private func logFailure(_ failure: PrivacyConfigurationOverrideFailure, source: String) {
        logError(failure.logLine(source: source))
    }
}

/// The `CONFIG_OVERRIDE_FAILED` reasons. Each failure logs one line.
enum PrivacyConfigurationOverrideFailure: String {
    case invalidURL = "invalid_url"
    case notInternal = "not_internal"
    case downloadFailed = "download_failed"

    func logLine(source: String) -> String {
        "CONFIG_OVERRIDE_FAILED action=set_url reason=\(rawValue) source=\(source)"
    }
}
