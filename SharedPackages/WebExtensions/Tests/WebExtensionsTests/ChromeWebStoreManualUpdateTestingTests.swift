//
//  ChromeWebStoreManualUpdateTestingTests.swift
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

#if DEBUG && os(macOS)
import Combine
import Foundation
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class ChromeWebStoreManualUpdateTestingTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var domain: String!
    private var testing: ChromeWebStoreManualUpdateTesting!
    private var managers: [WebExtensionManager] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        domain = "ChromeWebStoreManualUpdateTestingTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        testing = ChromeWebStoreManualUpdateTesting(directory: directory, defaults: defaults)
        try testing.setUp()
        try runScript(["prepare"])
    }

    override func tearDown() async throws {
        for manager in managers {
            manager.unloadAllExtensions()
            let types = WKWebExtensionController.allExtensionDataTypes
            let records = await manager.controller.dataRecords(ofTypes: types)
            await manager.controller.removeData(ofTypes: types, from: records)
            await manager.controller.configuration.defaultWebsiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        managers = []
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.removeItem(at: directory)
    }

    func testUnsignedOverrideOnlyAcceptsTheManualFixtureAndStillValidatesArchives() throws {
        let package = try Data(contentsOf: directory.appendingPathComponent("v2.zip"))
        let identifier = ChromeWebStoreManualUpdateTesting.extensionID
        let verifier = ChromeWebStorePackageVerifier(allowUnsignedManualTestFixture: true)

        XCTAssertEqual(try verifier.verifiedArchive(in: package, extensionID: identifier).version, "2.0")
        XCTAssertThrowsError(try ChromeWebStorePackageVerifier().verifiedArchive(in: package, extensionID: identifier))
        XCTAssertThrowsError(try verifier.verifiedArchive(in: package, extensionID: ChromeWebStoreID.bitwarden.rawValue))
        XCTAssertThrowsError(try verifier.verifiedArchive(in: Data("not a ZIP".utf8), extensionID: identifier))
    }

    func testFactoryUsesIndependentInventoryAndWebKitData() throws {
        let first = makeManager()
        let second = makeManager()

        XCTAssertTrue(testing.owns(first))
        XCTAssertEqual(first.extensionsDirectory, testing.extensionsDirectory)
        XCTAssertTrue(first.installationStore.installedExtensions.isEmpty)
        XCTAssertEqual(first.controller.configuration.identifier, second.controller.configuration.identifier)
        XCTAssertNotEqual(first.controller.configuration.identifier, WKWebExtensionController.Configuration.default().identifier)
        XCTAssertEqual(first.chromeWebStore?.catalogExtensionIDs, [ChromeWebStoreManualUpdateTesting.extensionID])
    }

    func testBootstrapAndStartupUpdateUseTheLocalSource() async throws {
        let server = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        let controlURL = try await server.start()
        defer { server.stop() }
        let first = makeManager()
        defer { first.unloadAllExtensions() }
        await first.loadInstalledExtensions()
        try await testing.installVersionOne(in: first)
        let original = try XCTUnwrap(first.installationStore.installedExtensions.first)
        XCTAssertEqual(original.version, "1.0")
        XCTAssertNotNil(first.context(for: original.uniqueIdentifier))
        await first.chromeWebStore?.checkForUpdatesNow()
        let (initialPage, _) = try await URLSession.shared.data(from: controlURL)
        let initialHTML = try XCTUnwrap(String(bytes: initialPage, encoding: .utf8))
        XCTAssertTrue(initialHTML.contains("class=\"version\">1.0"))
        var request = URLRequest(url: controlURL.appendingPathComponent("offer"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("version=2.0".utf8)
        let (updatedPage, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let updatedHTML = try XCTUnwrap(String(bytes: updatedPage, encoding: .utf8))
        XCTAssertTrue(updatedHTML.contains("class=\"version\">2.0"))
        request.httpBody = Data("version=9.0".utf8)
        let (_, invalidResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 400)
        request.httpBody = Data("version=1.0".utf8)
        request.setValue("https://example.com", forHTTPHeaderField: "Origin")
        let (_, crossOriginResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((crossOriginResponse as? HTTPURLResponse)?.statusCode, 403)

        await first.chromeWebStore?.checkForUpdatesNow()
        first.unloadAllExtensions()
        server.stop()
        let relaunched = makeManager()
        defer { relaunched.unloadAllExtensions() }
        await relaunched.loadInstalledExtensions()

        let updated = try XCTUnwrap(relaunched.installationStore.installedExtensions.first)
        XCTAssertEqual(updated.uniqueIdentifier, original.uniqueIdentifier)
        XCTAssertEqual(updated.version, "2.0")
        XCTAssertFalse(updated.isDisabled)
        XCTAssertEqual(relaunched.context(for: updated.uniqueIdentifier)?.webExtension.version, "2.0")
    }

    func testLocalUpdateAppliesWhenActivityAllowsWithoutRelaunching() async throws {
        let server = ChromeWebStoreManualUpdateServer(testing: testing, notificationCenter: NotificationCenter())
        let controlURL = try await server.start()
        defer { server.stop() }
        let activity = PassthroughSubject<Void, Never>()
        var isInactive = false
        let manager = makeManager(updateApplicationPolicy: { _ in { _ in isInactive } },
                                  activityUpdates: activity.eraseToAnyPublisher())
        await manager.loadInstalledExtensions()
        try await testing.installVersionOne(in: manager)
        let original = try XCTUnwrap(manager.installationStore.installedExtensions.first)
        var request = URLRequest(url: controlURL.appendingPathComponent("offer"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("version=2.0".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let store = try XCTUnwrap(manager.chromeWebStore as? ChromeWebStoreService)
        await store.checkForUpdatesNow()
        let pending = try await store.pendingUpdates.allPendingUpdates()
        XCTAssertEqual(pending.map(\.version), ["2.0"])
        XCTAssertEqual(manager.context(for: original.uniqueIdentifier)?.webExtension.version, "1.0")

        let applied = expectation(description: "The local update loads without relaunching")
        let observation = NotificationCenter.default.publisher(for: .webExtensionsDidChangeLoadedExtensions, object: manager)
            .sink { _ in
                if manager.context(for: original.uniqueIdentifier)?.webExtension.version == "2.0" { applied.fulfill() }
            }
        defer { observation.cancel() }
        isInactive = true
        activity.send(())
        await fulfillment(of: [applied], timeout: 15)
        await manager.updateInstaller?.cancelAndWait()

        let updated = try XCTUnwrap(manager.installationStore.installedExtensions.first)
        XCTAssertEqual(updated.uniqueIdentifier, original.uniqueIdentifier)
        XCTAssertEqual(updated.version, "2.0")
        XCTAssertEqual(manager.context(for: updated.uniqueIdentifier)?.webExtension.version, "2.0")
        let remaining = try await store.pendingUpdates.allPendingUpdates()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func makeManager(updateApplicationPolicy: ((WebExtensionManager) -> (@MainActor (String) -> Bool))? = nil,
                             activityUpdates: AnyPublisher<Void, Never>? = nil) -> WebExtensionManager {
        let manager = testing.makeManager(configuration: WebExtensionConfigurationProvidingMock(), windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                          permissionPrompter: NoPrompt(), enforcesPermissions: false, presenter: NoPresenter(),
                                          updateApplicationPolicy: updateApplicationPolicy, updateApplicationActivityUpdates: activityUpdates)
        managers.append(manager)
        return manager
    }

    private func runScript(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [directory.appendingPathComponent("serve_updates.py").path] + arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

}

@available(macOS 15.4, *)
@MainActor
private struct NoPrompt: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        XCTFail("This test uses legacy implicit consent")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult { .denied }
}

@available(macOS 15.4, *)
@MainActor
private struct NoPresenter: ChromeWebStorePresenting {
    func confirmRemoval(name: String, webExtension: WKWebExtension?) async -> Bool { false }
    func showError(_ error: Error) async { XCTFail("Unexpected installation error: \(error)") }
}
#endif
