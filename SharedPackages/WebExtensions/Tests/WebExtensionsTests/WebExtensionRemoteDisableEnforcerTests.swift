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
    private var isExtensionsEnabled = true
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
        isExtensionsEnabled = true
        try await super.tearDown()
    }

    // MARK: - Pixels

    func testWhenListedExtensionIsDisabled_ThenRemotelyDisabledPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        install(storeExtension("listed", storeID: listedStoreID), storeExtension("other", storeID: otherStoreID))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        // The mock manager has no store catalog, so the extension is reported as other.
        XCTAssertEqual(pixels.remotelyDisabled, ["other"])
    }

    func testWhenListedExtensionIsAlreadyDisabled_ThenNoPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        install(storeExtension("listed", storeID: listedStoreID, isDisabled: true))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(pixels.remotelyDisabled, [])
    }

    func testWhenDisablingFails_ThenNoPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        manager.disableExtensionError = NSError(domain: "test", code: 1)
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(pixels.remotelyDisabled, [])
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

    func testWhenExtensionsAreEnabledButNotLaunchedInConfiguration_ThenListedExtensionsAreDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID], launchedState: "disabled")
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed"])
        XCTAssertEqual(enforcer.remotelyDisabledExtensionIDs, [listedStoreID.lowercased()])
    }

    func testWhenExtensionsAreNotEnabledAndNotLaunchedInConfiguration_ThenTheListIsIgnored() throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [listedStoreID], launchedState: "disabled")
        isExtensionsEnabled = false

        XCTAssertEqual(makeEnforcer().remotelyDisabledExtensionIDs, [])
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

    // MARK: - Extensions Not Enabled

    func testWhenExtensionsAreNotEnabled_ThenEveryEnabledStoreExtensionIsDisabled() async throws {
        configurationManager.privacyConfig = try makeConfiguration(disabledIDs: [])
        isExtensionsEnabled = false
        install(storeExtension("store", storeID: listedStoreID),
                storeExtension("other", storeID: otherStoreID),
                storeExtension("alreadyDisabled", storeID: otherStoreID, isDisabled: true),
                InstalledWebExtension(uniqueIdentifier: "sideloaded", filename: "extension.zip", name: nil, version: nil))

        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["store", "other"])
        XCTAssertEqual(manager.installedExtension(identifier: "sideloaded")?.isDisabled, false)
    }

    func testWhenExtensionsAreNotEnabled_ThenOneKillSwitchPixelFiresWithTheSweptCount() async {
        let pixels = RemoteDisablePixelRecorder()
        isExtensionsEnabled = false
        install(storeExtension("listed", storeID: listedStoreID),
                storeExtension("other", storeID: otherStoreID),
                storeExtension("third", storeID: String(repeating: "c", count: 32)),
                storeExtension("alreadyDisabled", storeID: otherStoreID, isDisabled: true))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.disabledIdentifiers, ["listed", "other", "third"])
        XCTAssertEqual(pixels.remotelyDisabled, ["other"])
        XCTAssertEqual(pixels.killSwitchDisabled, [2])
    }

    func testWhenSweepDisablesNothing_ThenNoKillSwitchPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        isExtensionsEnabled = false
        install(storeExtension("alreadyDisabled", storeID: otherStoreID, isDisabled: true))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(pixels.killSwitchDisabled, [])
    }

    func testWhenSweepFailsToDisable_ThenNoKillSwitchPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        manager.disableExtensionError = NSError(domain: "test", code: 1)
        isExtensionsEnabled = false
        install(storeExtension("other", storeID: otherStoreID))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(pixels.killSwitchDisabled, [])
    }

    func testWhenExtensionsAreEnabled_ThenNoKillSwitchPixelFires() async {
        let pixels = RemoteDisablePixelRecorder()
        install(storeExtension("listed", storeID: listedStoreID))

        let enforcer = makeEnforcer(pixelFiring: pixels)
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(pixels.remotelyDisabled, ["other"])
        XCTAssertEqual(pixels.killSwitchDisabled, [])
    }

    func testWhenExtensionsStopBeingEnabled_ThenStoreExtensionIsDisabled() async {
        install(storeExtension("other", storeID: otherStoreID))
        let enforcer = makeEnforcer()
        enforcer.start()
        await enforcer.enforcementTask?.value
        XCTAssertEqual(manager.disabledIdentifiers, [])
        let disabled = expectation(description: "Extension disabled")
        manager.disableExtensionHandler = { _ in disabled.fulfill() }

        isExtensionsEnabled = false
        appDisabledIDsDidChange.send()

        await fulfillment(of: [disabled], timeout: 5)
        XCTAssertEqual(manager.disabledIdentifiers, ["other"])
    }

    func testWhenExtensionsAreEnabledAgain_ThenStoreExtensionStaysDisabled() async {
        isExtensionsEnabled = false
        install(storeExtension("other", storeID: otherStoreID))
        let enforcer = makeEnforcer()
        await enforcer.scheduleEnforcement().value

        isExtensionsEnabled = true
        await enforcer.scheduleEnforcement().value

        XCTAssertEqual(manager.installedExtension(identifier: "other")?.isDisabled, true)
        XCTAssertEqual(manager.enabledIdentifiers, [])
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

    private func makeEnforcer(pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) -> WebExtensionRemoteDisableEnforcer {
        WebExtensionRemoteDisableEnforcer(manager: manager,
                                          configurationManager: configurationManager,
                                          disabledExtensionIDs: { [unowned self] in appDisabledIDs },
                                          disabledExtensionIDsDidChange: appDisabledIDsDidChange.eraseToAnyPublisher(),
                                          isExtensionsEnabled: { [unowned self] in isExtensionsEnabled },
                                          pixelFiring: pixelFiring)
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

@available(macOS 15.4, iOS 18.4, *)
private final class RemoteDisablePixelRecorder: WebExtensionPixelFiring {
    private(set) var remotelyDisabled: [String] = []
    private(set) var killSwitchDisabled: [Int] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .remotelyDisabled(let pixelExtension):
            remotelyDisabled.append(pixelExtension.parameterValue)
        case .killSwitchDisabled(let count):
            killSwitchDisabled.append(count)
        default:
            break
        }
    }
}
