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
    @Test("Parses reset", .timeLimit(.minutes(1)))
    func parsesReset() {
        #expect(PrivacyConfigurationOverrideCommand(launchArgumentValue: "reset") == .reset)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Rejects missing or invalid values", .timeLimit(.minutes(1)), arguments: [
        nil, "", "  ", "not a url", "localhost:8080/config.json", "file:///tmp/config.json", "ftp://example.com/config.json", "http://",
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
    @Test("Sets the override for internal users", .timeLimit(.minutes(1)))
    func setsOverrideForInternalUser() {
        let (provider, store) = makeURLProvider(isInternalUser: true)
        let url = URL(string: "http://localhost:8080/ios-config.json")!

        #expect(PrivacyConfigurationOverrideCommand.set(url).apply(to: provider))
        #expect(store.customPrivacyConfigurationURL == url)
        #expect(provider.isPrivacyConfigurationOverridden)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ignores the argument for non-internal users", .timeLimit(.minutes(1)))
    func ignoresNonInternalUser() {
        let (provider, store) = makeURLProvider(isInternalUser: false)

        #expect(!PrivacyConfigurationOverrideCommand.set(URL(string: "http://localhost:8080/ios-config.json")!).apply(to: provider))
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(!provider.isPrivacyConfigurationOverridden)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reset clears the override", .timeLimit(.minutes(1)))
    func resetClearsOverride() {
        let (provider, store) = makeURLProvider(isInternalUser: true)
        store.customPrivacyConfigurationURL = URL(string: "http://localhost:8080/ios-config.json")

        #expect(PrivacyConfigurationOverrideCommand.reset.apply(to: provider))
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(!provider.isPrivacyConfigurationOverridden)
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
    var scheduledTokens = [String]()
    var lines = [String]()
    var reporter: PrivacyConfigurationOverrideReporter!

    init() {
        privacyConfig.identifier = "\"abc123\""
        privacyConfig.version = "1700000000001"
        privacyConfigurationManager = OverridePrivacyConfigurationManagerMock(privacyConfig: privacyConfig)
        (provider, store) = makeURLProvider(internalUserDecider: internalUserDecider)
        reporter = PrivacyConfigurationOverrideReporter(
            privacyConfigurationManager: privacyConfigurationManager,
            urlProvider: provider,
            contentBlockingUpdates: contentBlockingUpdates.eraseToAnyPublisher(),
            scheduleCompilation: { [unowned self] in
                let token = "token-\(scheduledTokens.count)"
                scheduledTokens.append(token)
                return token
            },
            log: { [unowned self] in lines.append($0) }
        )
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
    func logsConfigThenContentBlocking() {
        store.customPrivacyConfigurationURL = overrideURL

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
    func logsNewConfig() {
        store.customPrivacyConfigurationURL = overrideURL
        privacyConfigurationManager.updatesSubject.send()

        privacyConfig.identifier = "def456"
        privacyConfig.version = "1700000000002"
        privacyConfigurationManager.updatesSubject.send()

        #expect(lines.count == 2)
        #expect(lines.last == "CONFIG_OVERRIDE_APPLIED stage=config version=1700000000002 etag=def456 source=http://localhost:8080/ios-config.json")
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
        store.customPrivacyConfigurationURL = overrideURL
        internalUserDecider.isInternalUser = false

        privacyConfigurationManager.updatesSubject.send()

        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command sets the override, fetches, and reports even without a reload", .timeLimit(.minutes(1)))
    func handleReportsAfterFetch() async {
        var didFetch = false
        await reporter.handle(.set(overrideURL)) { didFetch = true }?.value

        #expect(didFetch)
        #expect(store.customPrivacyConfigurationURL == overrideURL)
        #expect(lines == ["CONFIG_OVERRIDE_APPLIED stage=config version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command reports nothing when the fetch fails", .timeLimit(.minutes(1)))
    func handleFetchFailure() async {
        struct FetchError: Error {}
        await reporter.handle(.set(overrideURL)) { throw FetchError() }?.value

        #expect(store.customPrivacyConfigurationURL == overrideURL)
        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling reset clears the override and reports nothing", .timeLimit(.minutes(1)))
    func handleReset() async {
        store.customPrivacyConfigurationURL = overrideURL
        var didFetch = false
        await reporter.handle(.reset) { didFetch = true }?.value

        #expect(didFetch)
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handling a command does nothing for non-internal users", .timeLimit(.minutes(1)))
    func handleNonInternalUser() async {
        internalUserDecider.isInternalUser = false
        let task = reporter.handle(.set(overrideURL)) { Issue.record("Unexpected fetch") }

        #expect(task == nil)
        #expect(store.customPrivacyConfigurationURL == nil)
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
