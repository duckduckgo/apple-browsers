//
//  DBPUIViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import WebKit
import BrowserServicesKit
import Common
import os.log
import DataBrokerProtectionCore
import Subscription

private struct EditablePartialProfile {
    var names: [DBPUIUserProfileName] = []
    var birthYear: DBPUIBirthYear?
    var addresses: [DBPUIUserProfileAddress] = []
}

public protocol DBPUIViewModelDelegate: AnyObject {
    func isUserAuthenticated() -> Bool
    func getUserProfile() throws -> DataBrokerProtectionProfile?
    func getAllDataBrokers() throws -> [DataBroker]
    func getAllBrokerProfileQueryData() throws -> [BrokerProfileQueryData]
    func saveProfile(_ profile: DataBrokerProtectionProfile) async throws
    func deleteAllUserProfileData() throws
    func matchRemovedByUser(with id: Int64) throws
}

public final class DBPUIViewModel {

    private weak var delegate: DBPUIViewModelDelegate?
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let contentScopeProperties: ContentScopeProperties
    private var communicationLayer: DBPUICommunicationLayer?
    private let webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>

    private var editablePartialProfile: EditablePartialProfile

    public init(delegate: DBPUIViewModelDelegate,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                privacyConfigManager: PrivacyConfigurationManaging,
                contentScopeProperties: ContentScopeProperties) {
        self.delegate = delegate
        self.webUISettings = webUISettings
        self.pixelHandler = pixelHandler
        self.privacyConfigManager = privacyConfigManager
        self.contentScopeProperties = contentScopeProperties

        self.editablePartialProfile = .init()
        let profile = try? delegate.getUserProfile()
        if let profile = profile {
            self.editablePartialProfile = .init(from: profile)
        }
    }

    @MainActor func setupCommunicationLayer() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.applyDBPUIConfiguration(privacyConfig: privacyConfigManager,
                                              prefs: contentScopeProperties,
                                              delegate: self,
                                              webUISettings: webUISettings,
                                              vpnBypassService: nil)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        if let dbpUIContentController = configuration.userContentController as? DBPUIUserContentController {
            communicationLayer = dbpUIContentController.dbpUIUserScripts.dbpUICommunicationLayer
        }

        return configuration
    }
}

extension DBPUIViewModel: DBPUICommunicationDelegate {
    public func getHandshakeUserData() -> DBPUIHandshakeUserData? {
        let isUserAuthenticated = delegate?.isUserAuthenticated() ?? false
        return DBPUIHandshakeUserData(isAuthenticatedUser: isUserAuthenticated)
    }
    
    public func saveProfile() async throws {
        guard let profile = DataBrokerProtectionProfile(fromEditablePartialProfile: editablePartialProfile) else {
            assertionFailure("Couldn't save profile")
            return
        }
        try await delegate?.saveProfile(profile)
    }
    
    public func getUserProfile() -> DBPUIUserProfile? {
        do {
            let profile = try delegate?.getUserProfile()

            guard let profile = profile else { return nil }
            return DBPUIUserProfile(fromDataBrokerProtectionProfile: profile)
        } catch {
            return nil
        }
    }
    
    public func deleteProfileData() throws {
        try delegate?.deleteAllUserProfileData()

        // Clear the in memory data
        editablePartialProfile = EditablePartialProfile()
    }

    public func addNameToCurrentUserProfile(_ name: DBPUIUserProfileName) -> Bool {
        let success = editablePartialProfile.addName(name)
        return success
    }
    
    public func setNameAtIndexInCurrentUserProfile(_ payload: DBPUINameAtIndex) -> Bool {
        let success = editablePartialProfile.setNameAtIndex(payload)
        return success
    }
    
    public func removeNameAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool {
        let success = editablePartialProfile.removeNameAtIndex(index.index)
        return success
    }
    
    public func setBirthYearForCurrentUserProfile(_ year: DBPUIBirthYear) -> Bool {
        editablePartialProfile.birthYear = year
        return true
    }
    
    public func addAddressToCurrentUserProfile(_ address: DBPUIUserProfileAddress) -> Bool {
        let success = editablePartialProfile.addAddress(address)
        return success
    }
    
    public func setAddressAtIndexInCurrentUserProfile(_ payload: DBPUIAddressAtIndex) -> Bool {
        let success = editablePartialProfile.setAddressAtIndex(payload)
        return success
    }
    
    public func removeAddressAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool {
        let success = editablePartialProfile.removeAddressAtIndex(index.index)
        return success
    }
    
    public func getInitialScanState() async -> DBPUIInitialScanState {
        do {
            let allQueryData = try delegate?.getAllBrokerProfileQueryData() ?? []
            return DBPUIInitialScanState(from: allQueryData)
        } catch {
            assertionFailure("Failed to fetch broker profile query data")
            return DBPUIInitialScanState.emptyInitialScanState()
        }
    }
    
    public func getMaintenanceScanState() async -> DBPUIScanAndOptOutMaintenanceState {
        do {
            let allQueryData = try delegate?.getAllBrokerProfileQueryData() ?? []
            return DBPUIScanAndOptOutMaintenanceState(from: allQueryData)
        } catch {
            assertionFailure("Failed to fetch broker profile query data")
            return DBPUIScanAndOptOutMaintenanceState.emptyMaintenanceState()
        }
    }
    
    public func getDataBrokers() async -> [DBPUIDataBroker] {
        do {
            let brokers = try delegate?.getAllDataBrokers() ?? []
            let result = brokers.flatMap {
                return DBPUIDataBroker.brokerWithMirrorSites(from: $0)
            }
            return result
        } catch {
            assertionFailure("Failed to fetch data brokers")
            return []
        }
    }

    public func removeOptOutFromDashboard(_ id: Int64) async {
        do {
            try delegate?.matchRemovedByUser(with: id)
        } catch {
            assertionFailure("Failed to add removed match to DB: \(error)")
        }
    }

    public func getBackgroundAgentMetadata() async -> DBPUIDebugMetadata {
        // Return no information as we think this is unused
        DBPUIDebugMetadata(lastRunAppVersion: "")
    }

    public func startScanAndOptOut() -> Bool {
        // No op, as we decided the web UI shouldn't issue commands directly
        return true
    }

    public func openSendFeedbackModal() async {
        // No op, as there's now a web feedback model
    }

    public func applyVPNBypassSetting(_ bypass: Bool) async {
        // No op, we don't have a VPN bypass on iOS
    }
}

extension EditablePartialProfile {

    init(from profile: DataBrokerProtectionProfile) {
        let names = profile.names.map { DBPUIUserProfileName(first: $0.firstName, middle: $0.middleName, last: $0.lastName, suffix: $0.suffix) }
        let addresses = profile.addresses.map { DBPUIUserProfileAddress(street: $0.street, city: $0.city, state: $0.state, zipCode: $0.zipCode) }
        let birthYear = DBPUIBirthYear(year: profile.birthYear)
        self.init(names: names, birthYear: birthYear, addresses: addresses)
    }

    mutating func addName(_ name: DBPUIUserProfileName) -> Bool {
        guard !name.requiredComponentsAreBlank() else { return false }

        // Duplicates not allowed
        guard names.firstIndex(where: { $0 == name }) == nil else { return false }

        names.append(name)
        return true
    }

    mutating func setNameAtIndex(_ nameAtIndex: DBPUINameAtIndex) -> Bool {
        guard nameAtIndex.index < names.count else {
            assertionFailure("Attempted to set name at index \(nameAtIndex.index) but only have \(names.count) names")
            return false
        }

        names[nameAtIndex.index] = nameAtIndex.name
        return true
    }

    mutating func removeNameAtIndex(_ index: Int) -> Bool {
        guard index < names.count else {
            assertionFailure("Attempted to remove name at index \(index) but only have \(names.count) names")
            return false
        }

        names.remove(at: index)
        return true
    }

    mutating func addAddress(_ address: DBPUIUserProfileAddress) -> Bool {
        guard !address.requiredComponentsAreBlank() else { return false }

        // Duplicates not allowed
        guard addresses.firstIndex(of: address) == nil else { return false }

        addresses.append(address)
        return true
    }

    mutating func setAddressAtIndex(_ addressAtIndex: DBPUIAddressAtIndex) -> Bool {
        guard addressAtIndex.index < addresses.count else {
            assertionFailure("Attempted to set address at index \(addressAtIndex.index) but only have \(addresses.count) addresses")
            return false
        }

        addresses[addressAtIndex.index] = addressAtIndex.address
        return true
    }

    mutating func removeAddressAtIndex(_ index: Int) -> Bool {
        guard index < addresses.count else {
            assertionFailure("Attempted to remove address at index \(index) but only have \(addresses.count) addresses")
            return false
        }

        addresses.remove(at: index)
        return true
    }
}

private extension DataBrokerProtectionProfile {
    init?(fromEditablePartialProfile profile: EditablePartialProfile) {
        guard let birthYear = profile.birthYear else {
            assertionFailure("No birth year specified")
            return nil
        }

        let names = profile.names.map { Name(firstName: $0.first, lastName: $0.last, middleName: $0.middle, suffix: $0.suffix) }
        let addresses = profile.addresses.map { Address(city: $0.city, state: $0.state, street: $0.street, zipCode: $0.zipCode) }
        self.init(names: names, addresses: addresses, phones: [], birthYear: birthYear.year)
    }
}
