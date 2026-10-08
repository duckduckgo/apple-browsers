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

import Combine
import Foundation
import os.log
import PrivacyConfig

/// The `-privacyConfigURL` launch argument, used by local tooling to point the browser at a locally built privacy configuration.
///
/// - `-privacyConfigURL <http(s) URL>` sets the privacy configuration override and fetches it immediately.
/// - `-privacyConfigURL reset` clears the override and fetches the default configuration.
///
/// Only internal users can use it. The override is never refreshed automatically: it changes only when the
/// app is launched with the argument again or the configuration is refreshed by hand.
public enum PrivacyConfigurationOverrideCommand: Equatable {
    case set(URL)
    case reset

    public static let launchArgumentKey = "privacyConfigURL"
    static let resetValue = "reset"

    /// Returns nil when the value is missing or is not an http(s) URL with a host.
    public init?(launchArgumentValue value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value == Self.resetValue {
            self = .reset
            return
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            Logger.config.error("Ignoring -\(Self.launchArgumentKey, privacy: .public): invalid URL \(value, privacy: .public)")
            return nil
        }
        self = .set(url)
    }

    /// Reads the launch argument from the argument domain of `userDefaults`.
    public init?(userDefaults: UserDefaults) {
        self.init(launchArgumentValue: userDefaults.string(forKey: Self.launchArgumentKey))
    }

    var url: URL? {
        guard case .set(let url) = self else { return nil }
        return url
    }

    /// Writes the override.
    /// - Returns: true when the caller must fetch the privacy configuration now, false when the command was ignored.
    @discardableResult
    public func apply(to urlSetter: CustomConfigurationURLSetting) -> Bool {
        guard urlSetter.isCustomURLEnabled else {
            Logger.config.log("Ignoring -\(Self.launchArgumentKey, privacy: .public): not an internal user")
            return false
        }
        do {
            try urlSetter.setCustomURL(url, for: .privacyConfiguration)
        } catch {
            Logger.config.error("Failed to set privacy configuration override: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }
}

public extension CustomConfigurationURLSetting {

    /// True while an internal user has a custom privacy configuration URL.
    /// Scheduled refreshes skip the privacy configuration in this state.
    var isPrivacyConfigurationOverridden: Bool {
        isCustomURLEnabled && isURLOverridden(for: .privacyConfiguration)
    }
}

/// Logs one `CONFIG_OVERRIDE_APPLIED` line each time a privacy configuration is applied while an override is active,
/// and one more when the content blocking rules built from it are ready. Local tooling waits for these lines.
public final class PrivacyConfigurationOverrideReporter {

    public enum Stage: String {
        case config
        case contentBlocking
    }

    struct AppliedConfig: Equatable {
        let version: String?
        let etag: String
        let source: URL
    }

    public static let logPrefix = "CONFIG_OVERRIDE_APPLIED"

    public static func logLine(stage: Stage, version: String?, etag: String, source: URL) -> String {
        let fields = [
            "stage=\(stage.rawValue)",
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
    private let urlProvider: CustomConfigurationURLProviding
    private let scheduleCompilation: () -> String
    private let log: (String) -> Void
    private let lock = NSLock()
    private var lastReportedConfig: AppliedConfig?
    private var configsAwaitingCompilation = [String: AppliedConfig]()
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - contentBlockingUpdates: completion tokens of each finished content blocking rules compilation.
    ///   - scheduleCompilation: schedules a rules compilation and returns its completion token.
    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                urlProvider: CustomConfigurationURLProviding,
                contentBlockingUpdates: AnyPublisher<[String], Never>,
                scheduleCompilation: @escaping () -> String,
                log: @escaping (String) -> Void = { Logger.config.log("\($0, privacy: .public)") }) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.urlProvider = urlProvider
        self.scheduleCompilation = scheduleCompilation
        self.log = log

        privacyConfigurationManager.updatesPublisher
            .sink { [weak self] in self?.reportConfigApplied() }
            .store(in: &cancellables)
        contentBlockingUpdates
            .sink { [weak self] tokens in self?.reportContentBlockingUpdated(completionTokens: tokens) }
            .store(in: &cancellables)
    }

    /// Applies `command` now, then runs `fetch` in a task. `fetch` must fetch and apply the privacy configuration.
    /// The applied configuration is reported even when the server answered 304 and nothing was reloaded.
    /// - Returns: the fetch task, or nil when the command was ignored.
    @discardableResult
    public func handle(_ command: PrivacyConfigurationOverrideCommand, fetch: @escaping () async throws -> Void) -> Task<Void, Never>? {
        guard command.apply(to: urlProvider) else { return nil }
        return Task {
            do {
                try await fetch()
            } catch {
                Logger.config.error("Failed to fetch privacy configuration override: \(error.localizedDescription, privacy: .public)")
                return
            }
            reportConfigApplied()
        }
    }

    /// Logs the current configuration unless the override is inactive or it was already reported.
    public func reportConfigApplied() {
        guard let config = currentAppliedConfig() else { return }

        lock.lock()
        defer { lock.unlock() }
        guard config != lastReportedConfig else { return }
        lastReportedConfig = config
        log(Self.logLine(stage: .config, version: config.version, etag: config.etag, source: config.source))

        // Hold the lock so the compilation can't report back before its token is recorded.
        configsAwaitingCompilation[scheduleCompilation()] = config
    }

    func reportContentBlockingUpdated(completionTokens: [String]) {
        lock.lock()
        defer { lock.unlock() }
        for token in completionTokens {
            guard let config = configsAwaitingCompilation.removeValue(forKey: token) else { continue }
            log(Self.logLine(stage: .contentBlocking, version: config.version, etag: config.etag, source: config.source))
        }
    }

    private func currentAppliedConfig() -> AppliedConfig? {
        guard urlProvider.isPrivacyConfigurationOverridden else { return nil }
        // Fell back to the embedded configuration, so nothing from the override was applied.
        if let manager = privacyConfigurationManager as? PrivacyConfigurationManager, manager.fetchedConfigData == nil {
            return nil
        }
        let privacyConfig = privacyConfigurationManager.privacyConfig
        return AppliedConfig(version: privacyConfig.version,
                             etag: privacyConfig.identifier,
                             source: urlProvider.url(for: .privacyConfiguration))
    }
}
