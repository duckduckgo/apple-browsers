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

/// The `-privacyConfigURL <url>` launch argument, used by local tooling to point the browser at a locally built privacy configuration.
///
/// The override lasts for one launch: it is not persisted, so a launch without the argument fetches production again.
/// Only internal users can use it.
public enum PrivacyConfigurationOverrideCommand: Equatable {
    case set(URL)

    public static let launchArgumentKey = "privacyConfigURL"

    /// Returns nil when the value is missing or is not an http(s) URL with a host.
    public init?(launchArgumentValue value: String?) {
        guard let value else { return nil }
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            logFailure(.invalidURL)
            return nil
        }
        self = .set(url)
    }

    /// Reads the launch argument from the argument domain of `userDefaults`.
    public init?(userDefaults: UserDefaults) {
        self.init(launchArgumentValue: userDefaults.string(forKey: Self.launchArgumentKey))
    }

    /// Sets the override for this launch only.
    /// - Returns: true when the caller must fetch the privacy configuration now, false when the command was ignored.
    @discardableResult
    public func apply(to urlSetter: CustomConfigurationURLSetting) -> Bool {
        guard urlSetter.isCustomURLEnabled else {
            logFailure(.notInternal)
            return false
        }
        switch self {
        case .set(let url):
            urlSetter.setSessionURL(url, for: .privacyConfiguration)
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

/// Remembers that the stored privacy configuration came from a launch-argument override,
/// so the next launch without the argument replaces it with production.
public struct PrivacyConfigurationOverrideMarker {

    private static let key = "PrivacyConfigurationOverride.storedFromLaunchArgument"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var isSet: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func set(_ isSet: Bool) {
        defaults.set(isSet, forKey: Self.key)
    }
}

/// Logs one `CONFIG_OVERRIDE_APPLIED` line each time a privacy configuration fetched in this launch is applied,
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
    private let overrideMarker: PrivacyConfigurationOverrideMarker
    private let log: (String) -> Void
    private let lock = NSLock()
    private var isOverrideFetched = false
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
                overrideMarker: PrivacyConfigurationOverrideMarker,
                log: @escaping (String) -> Void = { Logger.config.log("\($0, privacy: .public)") }) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.urlProvider = urlProvider
        self.scheduleCompilation = scheduleCompilation
        self.overrideMarker = overrideMarker
        self.log = log

        privacyConfigurationManager.updatesPublisher
            .sink { [weak self] in self?.reportConfigApplied() }
            .store(in: &cancellables)
        contentBlockingUpdates
            .sink { [weak self] tokens in self?.reportContentBlockingUpdated(completionTokens: tokens) }
            .store(in: &cancellables)
    }

    /// Applies `command` now, then runs `fetch` in a task. `fetch` must fetch and apply the privacy configuration.
    ///
    /// Without a command, the task runs only when the stored configuration came from an earlier override,
    /// so that production replaces it. Call this on every cold launch, before any scheduled refresh.
    /// - Returns: the fetch task, or nil when there is nothing to fetch.
    @discardableResult
    public func handle(_ command: PrivacyConfigurationOverrideCommand?,
                       fetch: @escaping () async throws -> Void) -> Task<Void, Never>? {
        if let command {
            guard command.apply(to: urlProvider) else { return nil }
            Logger.config.log("privacy config override: launch argument handled")
        } else {
            guard overrideMarker.isSet else { return nil }
            Logger.config.log("privacy config override: replacing earlier override with production")
        }
        return Task {
            Logger.config.log("privacy config override: fetch started")
            do {
                try await fetch()
            } catch {
                if command == nil {
                    Logger.config.error("Failed to fetch production privacy configuration: \(error.localizedDescription, privacy: .public)")
                } else {
                    logFailure(.downloadFailed)
                }
                return
            }
            Logger.config.log("privacy config override: fetch finished")
            finishFetch(for: command)
        }
    }

    /// Logs the current configuration unless the override is inactive or it was already reported.
    public func reportConfigApplied() {
        guard let config = currentAppliedConfig() else { return }

        lock.lock()
        defer { lock.unlock() }
        guard isOverrideFetched, config != lastReportedConfig else { return }
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

    private func finishFetch(for command: PrivacyConfigurationOverrideCommand?) {
        guard command != nil else {
            overrideMarker.set(false)
            return
        }
        // Fell back to the embedded configuration, so nothing from the override was applied.
        guard currentAppliedConfig() != nil else {
            logFailure(.downloadFailed)
            return
        }
        overrideMarker.set(true)
        lock.lock()
        isOverrideFetched = true
        lock.unlock()
        reportConfigApplied()
    }

    private func currentAppliedConfig() -> AppliedConfig? {
        guard urlProvider.isPrivacyConfigurationOverridden else { return nil }
        if let manager = privacyConfigurationManager as? PrivacyConfigurationManager, manager.fetchedConfigData == nil {
            return nil
        }
        let privacyConfig = privacyConfigurationManager.privacyConfig
        return AppliedConfig(version: privacyConfig.version,
                             etag: privacyConfig.identifier,
                             source: urlProvider.url(for: .privacyConfiguration))
    }
}

/// The `CONFIG_OVERRIDE_FAILED` reasons. Each failure logs one line.
enum PrivacyConfigurationOverrideFailure: String {
    case invalidURL = "invalid_url"
    case notInternal = "not_internal"
    case downloadFailed = "download_failed"

    var logLine: String {
        "CONFIG_OVERRIDE_FAILED action=set_url reason=\(rawValue)"
    }
}

private func logFailure(_ failure: PrivacyConfigurationOverrideFailure) {
    Logger.config.error("\(failure.logLine, privacy: .public)")
}
