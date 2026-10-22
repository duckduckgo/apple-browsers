//
//  WebExtensionRemoteDisableEnforcerTests.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import WebExtensions
import WebExtensionsTestSupport

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionRemoteDisableEnforcerTests: XCTestCase {

    private let listedStoreID = String(repeating: "a", count: 32)
    private let otherStoreID = String(repeating: "b", count: 32)
    private var manager: MockWebExtensionManaging!
    private var configurationManager: MockPrivacyConfigurationManager!
    private var appDisabledIDs: Set<String> = []
    private let appDisabledIDsDidChange = PassthroughSubject<Void, Never>()

    override func setUp() async throws {
        try await super.setUp()
        manager = MockWebExtensionManaging()
        configurationManager = MockPrivacyConfigurationManager(privacyConfig: try makeConfiguration(disabledIDs: [listedStoreID]))
    }

    override func tearDown() async throws {
        manager = nil
        configurationManager = nil
        appDisabledIDs = []
        try await super.tearDown()
    }

    // MARK: - Enforcement

    func testWhenListedExtensionIsEnabled_ThenItIsDisabled() async {
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed"])
        XCTAssertEqual(manager.installedExtension(identifier: "listed")?.isDisabled, true)
    }

    func testWhenEveryListedExtensionIsEnabled_ThenAllAreDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID, otherStoreID])
        install(storeExtension("listed", storeID: listedStoreID), storeExtension("other", storeID: otherStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed", "other"])
    }

    func testWhenListedExtensionIsAlreadyDisabled_ThenItIsNotDisabledAgain() async {
        install(storeExtension("listed", storeID: listedStoreID, isDisabled: true))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, [])
    }

    func testWhenExtensionIsNotListed_ThenItStaysEnabled() async {
        install(storeExtension("other", storeID: otherStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, [])
    }

    func testWhenListedIDDiffersInCase_ThenExtensionIsDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID.uppercased()])
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed"])
    }

    func testWhenExtensionHasNoStoreIdentity_ThenItIsNotDisabled() async {
        install(InstalledWebExtension(uniqueIdentifier: listedStoreID, filename: "extension.zip", name: nil, version: nil))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, [])
    }

    func testWhenExtensionManagementIsNotLaunched_ThenNothingIsDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID], launchedState: "disabled")
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, [])
        XCTAssertEqual(enforcer.remotelyDisabledExtensionIDs, [])
    }

    func testWhenDisablingFails_ThenOtherListedExtensionsAreStillDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID, otherStoreID])
        install(storeExtension("listed", storeID: listedStoreID), storeExtension("other", storeID: otherStoreID))
        manager.disableExtensionError = NSError(domain: "test", code: 1)

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed", "other"])
    }

    // MARK: - Disabled by the App

    func testWhenTheAppDisablesAnExtension_ThenItIsDisabledEvenIfExtensionManagementIsNotLaunched() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [], launchedState: "disabled")
        appDisabledIDs = [otherStoreID.uppercased()]
        install(storeExtension("other", storeID: otherStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["other"])
    }

    func testWhenTheAppStartsDisablingAnExtension_ThenItIsDisabled() async {
        install(storeExtension("other", storeID: otherStoreID))
        let enforcer = makeEnforcer()
        enforcer.start()
        await enforcer.enforcementTask?.value
        let disabled = expectation(description: "Extension disabled")
        manager.disableExtensionHandler = { _ in disabled.fulfill() }

        appDisabledIDs = [otherStoreID]
        appDisabledIDsDidChange.send()

        await fulfillment(of: [disabled], timeout: 5)
        XCTAssertEqual(manager.disabledIdentifiers, ["other"])
    }

    // MARK: - One-way

    func testWhenIDLeavesTheList_ThenExtensionStaysDisabled() async throws {
        install(storeExtension("listed", storeID: listedStoreID))
        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [])
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.installedExtension(identifier: "listed")?.isDisabled, true)
        XCTAssertEqual(manager.enabledIdentifiers, [])
        XCTAssertFalse(enforcer.isRemotelyDisabled(try XCTUnwrap(manager.installedExtension(identifier: "listed"))))
    }

    func testWhileExtensionIsListed_ThenItIsReportedAsRemotelyDisabled() {
        let enforcer = makeEnforcer()

        XCTAssertTrue(enforcer.isRemotelyDisabled(storeExtension("listed", storeID: listedStoreID)))
        XCTAssertFalse(enforcer.isRemotelyDisabled(storeExtension("other", storeID: otherStoreID)))
    }

    // MARK: - Triggers

    func testWhenStarted_ThenListedExtensionIsDisabled() async {
        install(storeExtension("listed", storeID: listedStoreID))
        let enforcer = makeEnforcer()

        enforcer.start()
        await enforcer.enforcementTask?.value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed"])
    }

    func testWhenConfigurationUpdatesWithNewListedID_ThenExtensionIsDisabled() async throws {
        install(storeExtension("other", storeID: otherStoreID))
        let enforcer = makeEnforcer()
        enforcer.start()
        await enforcer.enforcementTask?.value
        let disabled = expectation(description: "Extension disabled")
        manager.disableExtensionHandler = { _ in disabled.fulfill() }

        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [otherStoreID])
        configurationManager.updatesSubject.send()

        await fulfillment(of: [disabled], timeout: 5)
        XCTAssertEqual(manager.disabledIdentifiers, ["other"])
    }

    func testWhenUserEnablesListedExtension_ThenItIsDisabledAgain() async throws {
        install(storeExtension("listed", storeID: listedStoreID))
        let enforcer = makeEnforcer()
        enforcer.start()
        await enforcer.enforcementTask?.value
        let disabledAgain = expectation(description: "Extension disabled again")
        manager.disableExtensionHandler = { _ in disabledAgain.fulfill() }

        try await manager.enableExtension(identifier: "listed")
        NotificationCenter.default.post(name: .webExtensionsDidChangeLoadedExtensions, object: manager)

        await fulfillment(of: [disabledAgain], timeout: 5)
        XCTAssertEqual(manager.disabledIdentifiers, ["listed", "listed"])
        XCTAssertEqual(manager.installedExtension(identifier: "listed")?.isDisabled, true)
    }

    // MARK: - Helpers

    private func makeEnforcer() -> WebExtensionRemoteDisableEnforcer {
        WebExtensionRemoteDisableEnforcer(manager: manager,
                                          configurationManager: configurationManager,
                                          disabledExtensionIDs: { [unowned self] in appDisabledIDs },
                                          disabledExtensionIDsDidChange: appDisabledIDsDidChange.eraseToAnyPublisher())
    }

    private func install(_ extensions: InstalledWebExtension...) {
        manager.installedExtensions = extensions
        manager.webExtensionIdentifiers = extensions.map(\.uniqueIdentifier)
    }

    private func storeExtension(_ identifier: String, storeID: String, isDisabled: Bool = false) -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: identifier,
                              filename: "extension.zip",
                              name: nil,
                              version: nil,
                              storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: storeID),
                              isDisabled: isDisabled)
    }

    private func makeConfiguration(disabledIDs: [String], launchedState: String = "enabled") throws -> AppPrivacyConfiguration {
        let json: [String: Any] = [
            "features": [
                "extensionManagement": [
                    "state": "enabled",
                    "settings": ["disabledExtensionIds": disabledIDs],
                    "features": [
                        "isLaunchedExtensions": ["state": launchedState]
                    ]
                ]
            ]
        ]
        let data = try PrivacyConfigurationData(data: JSONSerialization.data(withJSONObject: json))
        return AppPrivacyConfiguration(data: data, identifier: "test", localProtection: MockDomainsProtectionStore(),
                                       internalUserDecider: MockInternalUserDecider())
    }
}
