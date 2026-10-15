//
//  PrivacyConfigurationOverrideTests.swift
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
import PrivacyConfig
import Testing
@testable import Configuration

@Suite("Privacy configuration override launch argument")
struct PrivacyConfigurationOverrideCommandTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses an http(s) URL", .timeLimit(.minutes(1)), arguments: [
        "http://localhost:8080/ios-config.json",
        "http://127.0.0.1:8080/macos-config.json",
        "https://example.com/config.json",
    ])
    func parsesURL(value: String) {
        #expect(PrivacyConfigurationOverrideCommand(launchArgumentValue: value) == .set(URL(string: value)!))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Rejects missing or invalid values", .timeLimit(.minutes(1)), arguments: [
        nil, "", "  ", "not a url", "localhost:8080/config.json", "file:///tmp/config.json", "ftp://example.com/config.json", "http://", "reset",
    ])
    func rejectsInvalidValue(value: String?) {
        #expect(PrivacyConfigurationOverrideCommand(launchArgumentValue: value) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reads the launch argument from user defaults", .timeLimit(.minutes(1)))
    func readsFromUserDefaults() throws {
        let suiteName = "PrivacyConfigurationOverrideCommandTests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(PrivacyConfigurationOverrideCommand(userDefaults: defaults) == nil)
        defaults.set("http://localhost:8080/ios-config.json", forKey: "privacyConfigURL")
        #expect(PrivacyConfigurationOverrideCommand(userDefaults: defaults) == .set(URL(string: "http://localhost:8080/ios-config.json")!))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sets a session override for internal users", .timeLimit(.minutes(1)))
    func setsSessionOverrideForInternalUser() {
        let (provider, store) = makeURLProvider(isInternalUser: true)
        let url = URL(string: "http://localhost:8080/ios-config.json")!

        #expect(PrivacyConfigurationOverrideCommand.set(url).apply(to: provider))
        #expect(provider.url(for: .privacyConfiguration) == url)
        #expect(provider.isPrivacyConfigurationOverridden)
        #expect(store.customPrivacyConfigurationURL == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A session override is not kept for the next launch", .timeLimit(.minutes(1)))
    func sessionOverrideIsNotPersisted() {
        let (provider, store) = makeURLProvider(isInternalUser: true)
        PrivacyConfigurationOverrideCommand.set(URL(string: "http://localhost:8080/ios-config.json")!).apply(to: provider)

        let nextLaunch = ConfigurationURLProvider(defaultProvider: MockConfigurationURLProvider(),
                                                  internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                                  store: store)
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(!nextLaunch.isPrivacyConfigurationOverridden)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The session override wins over the debug custom URL, which returns after the launch", .timeLimit(.minutes(1)))
    func sessionOverrideWinsOverDebugCustomURL() {
        let (provider, store) = makeURLProvider(isInternalUser: true)
        let debugURL = URL(string: "http://localhost:9090/debug-config.json")!
        let sessionURL = URL(string: "http://localhost:8080/ios-config.json")!
        store.customPrivacyConfigurationURL = debugURL
        #expect(provider.url(for: .privacyConfiguration) == debugURL)

        PrivacyConfigurationOverrideCommand.set(sessionURL).apply(to: provider)
        #expect(provider.url(for: .privacyConfiguration) == sessionURL)
        #expect(store.customPrivacyConfigurationURL == debugURL)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ignores the argument for non-internal users", .timeLimit(.minutes(1)))
    func ignoresNonInternalUser() {
        let (provider, store) = makeURLProvider(isInternalUser: false)

        #expect(!PrivacyConfigurationOverrideCommand.set(URL(string: "http://localhost:8080/ios-config.json")!).apply(to: provider))
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(!provider.isPrivacyConfigurationOverridden)
    }
}

@Suite("Privacy configuration override failure log lines")
struct PrivacyConfigurationOverrideFailureTests {

    @available(iOS 16, macOS 13, *)
    @Test("Ends with source", .timeLimit(.minutes(1)), arguments: [
        (PrivacyConfigurationOverrideFailure.invalidURL, "invalid_url"),
        (.notInternal, "not_internal"),
        (.downloadFailed, "download_failed"),
    ])
    func formatsLine(failure: PrivacyConfigurationOverrideFailure, reason: String) {
        let line = failure.logLine(source: "http://localhost:8080/ios-config.json")
        #expect(line == "CONFIG_OVERRIDE_FAILED action=set_url reason=\(reason) source=http://localhost:8080/ios-config.json")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Invalid source is the raw argument without whitespace", .timeLimit(.minutes(1)), arguments: [
        ("", ""), ("  ", ""), ("not a url", "notaurl"), (" reset\n", "reset"), ("ftp://example.com/c.json", "ftp://example.com/c.json"),
    ])
    func invalidSource(value: String, expected: String) {
        #expect(PrivacyConfigurationOverrideCommand.invalidArgumentSource(value) == expected)
    }
}

@Suite("Privacy configuration override marker")
struct PrivacyConfigurationOverrideMarkerTests {

    @available(iOS 16, macOS 13, *)
    @Test("Is set and cleared", .timeLimit(.minutes(1)))
    func setAndClear() throws {
        let suiteName = "PrivacyConfigurationOverrideMarkerTests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let marker = PrivacyConfigurationOverrideMarker(defaults: defaults)

        #expect(!marker.isSet)
        marker.set(true)
        #expect(marker.isSet)
        marker.set(false)
        #expect(!marker.isSet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without a valid argument, removes the stored configuration and clears the marker", .timeLimit(.minutes(1)), arguments: [
        nil, "", "reset", "not a url",
    ])
    func resetsWithoutValidArgument(argument: String?) throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: argument)
        defer { cleanUp() }
        marker.set(true)
        var removals = 0

        #expect(marker.resetIfNeeded(userDefaults: launchArguments) { removals += 1 })
        #expect(removals == 1)
        #expect(!marker.isSet)
        #expect(!marker.resetIfNeeded(userDefaults: launchArguments) { removals += 1 })
        #expect(removals == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With a valid argument, keeps the stored configuration and the marker", .timeLimit(.minutes(1)))
    func keepsWithValidArgument() throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: "http://localhost:8080/ios-config.json")
        defer { cleanUp() }
        marker.set(true)

        #expect(!marker.resetIfNeeded(userDefaults: launchArguments) { Issue.record("Unexpected removal") })
        #expect(marker.isSet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without the marker, leaves the stored configuration alone", .timeLimit(.minutes(1)))
    func keepsWithoutMarker() throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: nil)
        defer { cleanUp() }

        #expect(!marker.resetIfNeeded(userDefaults: launchArguments) { Issue.record("Unexpected removal") })
    }

    private func makeMarker(argument: String?) throws -> (PrivacyConfigurationOverrideMarker, UserDefaults, () -> Void) {
        let markerSuite = UUID().uuidString
        let argumentSuite = UUID().uuidString
        let markerDefaults = try #require(UserDefaults(suiteName: markerSuite))
        let launchArguments = try #require(UserDefaults(suiteName: argumentSuite))
        if let argument {
            launchArguments.set(argument, forKey: PrivacyConfigurationOverrideCommand.launchArgumentKey)
        }
        let cleanUp = {
            markerDefaults.removePersistentDomain(forName: markerSuite)
            launchArguments.removePersistentDomain(forName: argumentSuite)
        }
        return (PrivacyConfigurationOverrideMarker(defaults: markerDefaults), launchArguments, cleanUp)
    }
}

@Suite("Privacy configuration override log lines")
final class PrivacyConfigurationOverrideReporterTests {

    let overrideURL = URL(string: "http://localhost:8080/ios-config.json")!
    let privacyConfig = MockPrivacyConfiguration()
    let privacyConfigurationManager: OverridePrivacyConfigurationManagerMock
    let provider: ConfigurationURLProvider
    let store: MockCustomConfigurationURLStore
    let internalUserDecider = MockInternalUserDecider(isInternalUser: true)
    let contentBlockingUpdates = PassthroughSubject<[String], Never>()
    let markerSuiteName = UUID().uuidString
    let marker: PrivacyConfigurationOverrideMarker
    var scheduledTokens = [String]()
    var lines = [String]()
    var reporter: PrivacyConfigurationOverrideReporter!

    init() {
        privacyConfig.identifier = "\"abc123\""
        privacyConfig.version = "1700000000001"
        privacyConfigurationManager = OverridePrivacyConfigurationManagerMock(privacyConfig: privacyConfig)
        (provider, store) = makeURLProvider(internalUserDecider: internalUserDecider)
        marker = PrivacyConfigurationOverrideMarker(defaults: UserDefaults(suiteName: markerSuiteName)!)
        reporter = PrivacyConfigurationOverrideReporter(
            privacyConfigurationManager: privacyConfigurationManager,
            urlProvider: provider,
            contentBlockingUpdates: contentBlockingUpdates.eraseToAnyPublisher(),
            scheduleCompilation: { [unowned self] in
                let token = "token-\(scheduledTokens.count)"
                scheduledTokens.append(token)
                return token
            },
            overrideMarker: marker,
            log: { [unowned self] in lines.append($0) }
        )
    }

    deinit {
        UserDefaults(suiteName: markerSuiteName)?.removePersistentDomain(forName: markerSuiteName)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Formats the log line", .timeLimit(.minutes(1)))
    func formatsLogLine() {
        let line = PrivacyConfigurationOverrideReporter.logLine(stage: .config, version: "1700000000001", etag: "W/\"abc 123\"", source: overrideURL)
        #expect(line == "CONFIG_OVERRIDE_APPLIED stage=config version=1700000000001 etag=W/abc123 source=http://localhost:8080/ios-config.json")

        let contentBlockingLine = PrivacyConfigurationOverrideReporter.logLine(stage: .contentBlocking, version: nil, etag: "abc", source: overrideURL)
        #expect(contentBlockingLine == "CONFIG_OVERRIDE_APPLIED stage=contentBlocking version=unknown etag=abc source=http://localhost:8080/ios-config.json")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Logs once per applied config, then once when its rules compile", .timeLimit(.minutes(1)))
    func logsConfigThenContentBlocking() async {
        let fetchTask = reporter.handle(.set(overrideURL)) {}
        await fetchTask?.value

        privacyConfigurationManager.updatesSubject.send()
        privacyConfigurationManager.updatesSubject.send()

        #expect(lines == ["CONFIG_OVERRIDE_APPLIED stage=config version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json"])
        #expect(scheduledTokens == ["token-0"])

        contentBlockingUpdates.send(["unrelated"])
        #expect(lines.count == 1)

        contentBlockingUpdates.send(["unrelated", "token-0"])
        contentBlockingUpdates.send(["token-0"])
        #expect(lines == [
            "CONFIG_OVERRIDE_APPLIED stage=config version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json",
            "CONFIG_OVERRIDE_APPLIED stage=contentBlocking version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json",
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Logs again when a new config is applied", .timeLimit(.minutes(1)))
    func logsNewConfig() async {
        let fetchTask = reporter.handle(.set(overrideURL)) {}
        await fetchTask?.value

        privacyConfig.identifier = "def456"
        privacyConfig.version = "1700000000002"
        privacyConfigurationManager.updatesSubject.send()

        #expect(lines.count == 2)
        #expect(lines.last == "CONFIG_OVERRIDE_APPLIED stage=config version=1700000000002 etag=def456 source=http://localhost:8080/ios-config.json")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Does not log a config loaded from disk at startup", .timeLimit(.minutes(1)))
    func silentForDiskLoadedConfig() {
        provider.setSessionURL(overrideURL, for: .privacyConfiguration)

        privacyConfigurationManager.updatesSubject.send()
        reporter.reportConfigApplied()

        #expect(lines.isEmpty)
        #expect(scheduledTokens.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stays silent without an override", .timeLimit(.minutes(1)))
    func silentWithoutOverride() {
        privacyConfigurationManager.updatesSubject.send()
        reporter.reportConfigApplied()

        #expect(lines.isEmpty)
        #expect(scheduledTokens.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stays silent for non-internal users", .timeLimit(.minutes(1)))
    func silentForNonInternalUser() {
        provider.setSessionURL(overrideURL, for: .privacyConfiguration)
        internalUserDecider.isInternalUser = false

        privacyConfigurationManager.updatesSubject.send()

        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command sets a session override, fetches, marks the store, and reports even without a reload", .timeLimit(.minutes(1)))
    func handleReportsAfterFetch() async {
        var didFetch = false
        let fetchTask = reporter.handle(.set(overrideURL)) { didFetch = true }
        await fetchTask?.value

        #expect(didFetch)
        #expect(provider.isPrivacyConfigurationOverridden)
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(marker.isSet)
        #expect(lines == ["CONFIG_OVERRIDE_APPLIED stage=config version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command reports nothing and leaves the marker unset when the fetch fails", .timeLimit(.minutes(1)))
    func handleFetchFailure() async {
        struct FetchError: Error {}
        let fetchTask = reporter.handle(.set(overrideURL)) { throw FetchError() }
        await fetchTask?.value

        #expect(!marker.isSet)
        #expect(lines.isEmpty)
        #expect(scheduledTokens.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an argument, does nothing", .timeLimit(.minutes(1)))
    func noFetchWithoutArgument() {
        marker.set(true)
        let fetchTask = reporter.handle(nil) { Issue.record("Unexpected fetch") }

        #expect(fetchTask == nil)
        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command does nothing for non-internal users", .timeLimit(.minutes(1)))
    func handleNonInternalUser() {
        internalUserDecider.isInternalUser = false
        let fetchTask = reporter.handle(.set(overrideURL)) { Issue.record("Unexpected fetch") }

        #expect(fetchTask == nil)
        #expect(!provider.isPrivacyConfigurationOverridden)
        #expect(!marker.isSet)
        #expect(lines.isEmpty)
    }
}

private func makeURLProvider(isInternalUser: Bool) -> (ConfigurationURLProvider, MockCustomConfigurationURLStore) {
    makeURLProvider(internalUserDecider: MockInternalUserDecider(isInternalUser: isInternalUser))
}

private func makeURLProvider(internalUserDecider: MockInternalUserDecider) -> (ConfigurationURLProvider, MockCustomConfigurationURLStore) {
    let store = MockCustomConfigurationURLStore()
    let defaultProvider = MockConfigurationURLProvider()
    defaultProvider.url = URL(string: "https://staticcdn.duckduckgo.com/trackerblocking/config/v4/ios-config.json")!
    let provider = ConfigurationURLProvider(defaultProvider: defaultProvider,
                                            internalUserDecider: internalUserDecider,
                                            store: store)
    return (provider, store)
}

final class OverridePrivacyConfigurationManagerMock: PrivacyConfigurationManaging {

    let updatesSubject = PassthroughSubject<Void, Never>()
    let privacyConfig: PrivacyConfiguration
    let internalUserDecider: InternalUserDecider = MockInternalUserDecider()

    init(privacyConfig: PrivacyConfiguration) {
        self.privacyConfig = privacyConfig
    }

    var currentConfig: Data { Data() }
    var updatesPublisher: AnyPublisher<Void, Never> { updatesSubject.eraseToAnyPublisher() }

    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult { .downloaded }
}
