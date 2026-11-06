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
struct PrivacyConfigurationOverrideArgumentTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses an http(s) URL", .timeLimit(.minutes(1)), arguments: [
        "http://localhost:8080/ios-config.json",
        "http://127.0.0.1:8080/macos-config.json",
        "https://example.com/config.json",
    ])
    func parsesURL(value: String) {
        #expect(PrivacyConfigurationOverrideArgument.url(fromLaunchArgument: value) == URL(string: value)!)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Rejects missing or invalid values", .timeLimit(.minutes(1)), arguments: [
        nil, "", "  ", "not a url", "localhost:8080/config.json", "file:///tmp/config.json", "ftp://example.com/config.json", "http://", "reset",
    ])
    func rejectsInvalidValue(value: String?) {
        #expect(PrivacyConfigurationOverrideArgument.url(fromLaunchArgument: value) == nil)
    }
}

@Suite("Privacy configuration override failure log lines")
struct PrivacyConfigurationOverrideFailureTests {

    @available(iOS 16, macOS 13, *)
    @Test("Ends with source", .timeLimit(.minutes(1)))
    func formatsLine() {
        let line = PrivacyConfigurationOverrideFailure.downloadFailed.logLine(source: "http://localhost:8080/ios-config.json")
        #expect(line == "CONFIG_OVERRIDE_FAILED action=set_url reason=download_failed source=http://localhost:8080/ios-config.json")
    }
}

@Suite("Privacy configuration override marker")
struct PrivacyConfigurationOverrideMarkerTests {

    @available(iOS 16, macOS 13, *)
    @Test("Without a valid argument, removes the stored configuration and clears the marker", .timeLimit(.minutes(1)), arguments: [
        nil, "", "reset", "not a url",
    ])
    func resetsWithoutValidArgument(argument: String?) throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: argument)
        defer { cleanUp() }
        marker.set(true)
        var removals = 0

        #expect(marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: true) { removals += 1 })
        #expect(removals == 1)
        #expect(!marker.isSet)
        #expect(!marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: true) { removals += 1 })
        #expect(removals == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With a valid argument, keeps the stored configuration and the marker", .timeLimit(.minutes(1)))
    func keepsWithValidArgument() throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: "http://localhost:8080/ios-config.json")
        defer { cleanUp() }
        marker.set(true, source: URL(string: "http://localhost:8080/ios-config.json")!)

        #expect(!marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: true) { Issue.record("Unexpected removal") })
        #expect(marker.isSet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A non-internal launch discards an earlier override", .timeLimit(.minutes(1)))
    func resetsForNonInternalUser() throws {
        let url = "http://localhost:8080/ios-config.json"
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: url)
        defer { cleanUp() }
        marker.set(true, source: URL(string: url)!)
        var removals = 0

        #expect(marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: false) { removals += 1 })
        #expect(removals == 1)
        #expect(!marker.isSet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new override URL discards cached configuration", .timeLimit(.minutes(1)), arguments: [nil, "http://localhost:9090/old.json"])
    func resetsWhenOverrideURLChanges(previousSource: String?) throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: "http://localhost:8080/ios-config.json")
        defer { cleanUp() }
        if let previousSource {
            marker.set(true, source: URL(string: previousSource)!)
        }
        var removals = 0

        #expect(marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: true) { removals += 1 })
        #expect(removals == 1)
        #expect(!marker.isSet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without the marker, leaves the stored configuration alone", .timeLimit(.minutes(1)))
    func keepsWithoutMarker() throws {
        let (marker, launchArguments, cleanUp) = try makeMarker(argument: nil)
        defer { cleanUp() }

        #expect(!marker.resetIfNeeded(userDefaults: launchArguments, isInternalUser: true) { Issue.record("Unexpected removal") })
    }

    private func makeMarker(argument: String?) throws -> (PrivacyConfigurationOverrideMarker, UserDefaults, () -> Void) {
        let markerSuite = UUID().uuidString
        let argumentSuite = UUID().uuidString
        let markerDefaults = try #require(UserDefaults(suiteName: markerSuite))
        let launchArguments = try #require(UserDefaults(suiteName: argumentSuite))
        if let argument {
            launchArguments.set(argument, forKey: PrivacyConfigurationOverrideArgument.launchArgumentKey)
        }
        let cleanUp = {
            markerDefaults.removePersistentDomain(forName: markerSuite)
            launchArguments.removePersistentDomain(forName: argumentSuite)
        }
        return (PrivacyConfigurationOverrideMarker(defaults: markerDefaults), launchArguments, cleanUp)
    }
}

@Suite("Privacy configuration override handler")
final class PrivacyConfigurationOverrideHandlerTests {

    let overrideArgument = "http://localhost:8080/ios-config.json"
    let appliedLine = "CONFIG_OVERRIDE_APPLIED version=1700000000001 etag=abc123 source=http://localhost:8080/ios-config.json"
    let downloadFailedLine = "CONFIG_OVERRIDE_FAILED action=set_url reason=download_failed source=http://localhost:8080/ios-config.json"
    let privacyConfig = MockPrivacyConfiguration()
    let privacyConfigurationManager: OverridePrivacyConfigurationManagerMock
    let provider: ConfigurationURLProvider
    let store: MockCustomConfigurationURLStore
    let internalUserDecider = MockInternalUserDecider(isInternalUser: true)
    let markerSuiteName = UUID().uuidString
    let marker: PrivacyConfigurationOverrideMarker
    var lines = [String]()
    var handler: PrivacyConfigurationOverrideHandler!

    init() {
        privacyConfig.identifier = "\"abc123\""
        privacyConfig.version = "1700000000001"
        privacyConfigurationManager = OverridePrivacyConfigurationManagerMock(privacyConfig: privacyConfig)
        (provider, store) = makeURLProvider(internalUserDecider: internalUserDecider)
        marker = PrivacyConfigurationOverrideMarker(defaults: UserDefaults(suiteName: markerSuiteName)!)
        handler = PrivacyConfigurationOverrideHandler(
            privacyConfigurationManager: privacyConfigurationManager,
            urlProvider: provider,
            overrideMarker: marker,
            log: { [unowned self] in lines.append($0) },
            logError: { [unowned self] in lines.append($0) }
        )
    }

    deinit {
        UserDefaults(suiteName: markerSuiteName)?.removePersistentDomain(forName: markerSuiteName)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Formats the log line", .timeLimit(.minutes(1)))
    func formatsLogLine() {
        let line = PrivacyConfigurationOverrideHandler.logLine(version: "1700000000001", etag: "W/\"abc 123\"", source: URL(string: overrideArgument)!)
        #expect(line == "CONFIG_OVERRIDE_APPLIED version=1700000000001 etag=W/abc123 source=http://localhost:8080/ios-config.json")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sets a session override, fetches, and logs the applied config", .timeLimit(.minutes(1)))
    func logsAppliedConfig() async {
        var didFetch = false
        let fetchTask = handler.handle(argument: overrideArgument) {
            didFetch = true
            return true
        }
        await fetchTask?.value

        #expect(didFetch)
        #expect(provider.url(for: .privacyConfiguration) == URL(string: overrideArgument)!)
        #expect(store.customPrivacyConfigurationURL == nil)
        #expect(marker.isSet)
        #expect(lines == [appliedLine])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The session override wins over the debug custom URL, which is kept", .timeLimit(.minutes(1)))
    func sessionOverrideWinsOverDebugCustomURL() async {
        let debugURL = URL(string: "http://localhost:9090/debug-config.json")!
        store.customPrivacyConfigurationURL = debugURL
        #expect(provider.url(for: .privacyConfiguration) == debugURL)

        await handler.handle(argument: overrideArgument) { true }?.value
        #expect(provider.url(for: .privacyConfiguration) == URL(string: overrideArgument)!)
        #expect(store.customPrivacyConfigurationURL == debugURL)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sets the marker before the fetch runs and keeps it when the fetch fails", .timeLimit(.minutes(1)))
    func setsMarkerBeforeFetch() async {
        struct FetchError: Error {}
        var wasMarkerSetDuringFetch = false
        let fetchTask = handler.handle(argument: overrideArgument) { [marker] in
            wasMarkerSetDuringFetch = marker.isSet
            throw FetchError()
        }
        await fetchTask?.value

        #expect(wasMarkerSetDuringFetch)
        #expect(marker.isSet)
        #expect(lines == [downloadFailedLine])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Logs download_failed and no APPLIED line when the app falls back to the embedded config", .timeLimit(.minutes(1)))
    func embeddedFallbackLogsFailure() async {
        await handler.handle(argument: overrideArgument) { false }?.value

        #expect(lines == [downloadFailedLine])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an argument, does nothing", .timeLimit(.minutes(1)))
    func noFetchWithoutArgument() {
        let fetchTask = handler.handle(argument: nil) {
            Issue.record("Unexpected fetch")
            return true
        }

        #expect(fetchTask == nil)
        #expect(!provider.isURLOverridden(for: .privacyConfiguration))
        #expect(!marker.isSet)
        #expect(lines.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An invalid argument logs invalid_url once and does nothing else", .timeLimit(.minutes(1)))
    func invalidArgument() {
        let fetchTask = handler.handle(argument: " not a url\n") {
            Issue.record("Unexpected fetch")
            return true
        }

        #expect(fetchTask == nil)
        #expect(!provider.isURLOverridden(for: .privacyConfiguration))
        #expect(!marker.isSet)
        #expect(lines == ["CONFIG_OVERRIDE_FAILED action=set_url reason=invalid_url source=notaurl"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("For non-internal users, logs not_internal once and does nothing else", .timeLimit(.minutes(1)))
    func nonInternalUser() {
        internalUserDecider.isInternalUser = false
        let fetchTask = handler.handle(argument: overrideArgument) {
            Issue.record("Unexpected fetch")
            return true
        }

        #expect(fetchTask == nil)
        #expect(!provider.isURLOverridden(for: .privacyConfiguration))
        #expect(!marker.isSet)
        #expect(lines == ["CONFIG_OVERRIDE_FAILED action=set_url reason=not_internal source=http://localhost:8080/ios-config.json"])
    }
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

    let privacyConfig: PrivacyConfiguration
    let internalUserDecider: InternalUserDecider = MockInternalUserDecider()

    init(privacyConfig: PrivacyConfiguration) {
        self.privacyConfig = privacyConfig
    }

    var currentConfig: Data { Data() }
    var updatesPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult { .downloaded }
}
