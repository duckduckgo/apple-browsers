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

public protocol DBPUIViewModelOpenFeedbackFormDelegate: AnyObject {
    func openSendFeedbackForm()
}

public final class DBPUIViewModel {

    private weak var authenticationDelegate: DBPIOSInterface.AuthenticationDelegate?
    private weak var databaseDelegate: DBPIOSInterface.DatabaseDelegate?
    private weak var feedbackFormDelegate: DBPUIViewModelOpenFeedbackFormDelegate?
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let contentScopeProperties: ContentScopeProperties
    private var communicationLayer: DBPUICommunicationLayer?
    private let webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>

    private var editablePartialProfile: DBPUIEditablePartialProfile

    public init(authenticationDelegate: DBPIOSInterface.AuthenticationDelegate,
                databaseDelegate: DBPIOSInterface.DatabaseDelegate,
                feedbackFormDelegate: DBPUIViewModelOpenFeedbackFormDelegate,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                privacyConfigManager: PrivacyConfigurationManaging,
                contentScopeProperties: ContentScopeProperties) {
        self.authenticationDelegate = authenticationDelegate
        self.databaseDelegate = databaseDelegate
        self.feedbackFormDelegate = feedbackFormDelegate
        self.webUISettings = webUISettings
        self.pixelHandler = pixelHandler
        self.privacyConfigManager = privacyConfigManager
        self.contentScopeProperties = contentScopeProperties

        self.editablePartialProfile = .init()
        let profile = try? databaseDelegate.getUserProfile()
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
        let isUserAuthenticated = authenticationDelegate?.isUserAuthenticated() ?? false
        return DBPUIHandshakeUserData(isAuthenticatedUser: isUserAuthenticated)
    }
    
    public func saveProfile() async throws {
        guard let profile = DataBrokerProtectionProfile(from: editablePartialProfile) else {
            assertionFailure("Couldn't save profile")
            return
        }
        try await databaseDelegate?.saveProfile(profile)
    }
    
    public func getUserProfile() -> DBPUIUserProfile? {
        do {
            let profile = try databaseDelegate?.getUserProfile()

            guard let profile = profile else { return nil }
            return DBPUIUserProfile(from: profile)
        } catch {
            return nil
        }
    }
    
    public func deleteProfileData() throws {
        try databaseDelegate?.deleteAllUserProfileData()

        // Clear the in memory data
        editablePartialProfile = DBPUIEditablePartialProfile()
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
            let allQueryData = try databaseDelegate?.getAllBrokerProfileQueryData() ?? []
            return DBPUIInitialScanState(from: allQueryData)
        } catch {
            assertionFailure("Failed to fetch broker profile query data")
            return DBPUIInitialScanState.emptyInitialScanState()
        }
    }

    public func getMaintenanceScanState() async -> DBPUIScanAndOptOutMaintenanceState {
        do {
            let allQueryData = try databaseDelegate?.getAllBrokerProfileQueryData() ?? []
            return DBPUIScanAndOptOutMaintenanceState(from: allQueryData)
        } catch {
            assertionFailure("Failed to fetch broker profile query data")
            return DBPUIScanAndOptOutMaintenanceState.emptyMaintenanceState()
        }
    }
    
    public func getDataBrokers() async -> [DBPUIDataBroker] {
        do {
            let brokers = try databaseDelegate?.getAllDataBrokers() ?? []
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
            try databaseDelegate?.matchRemovedByUser(with: id)
        } catch {
            assertionFailure("Failed to add removed match to DB: \(error)")
        }
    }

    public func openSendFeedbackModal() async {
        feedbackFormDelegate?.openSendFeedbackForm()
    }

    public func getBackgroundAgentMetadata() async -> DBPUIDebugMetadata {
        // Return no information as we think this is unused
        DBPUIDebugMetadata(lastRunAppVersion: "")
    }

    public func startScanAndOptOut() -> Bool {
        // No op, as we decided the web UI shouldn't issue commands directly
        return true
    }

    public func applyVPNBypassSetting(_ bypass: Bool) async {
        // No op, we don't have a VPN bypass on iOS
    }
}
