//
//  ScriptSourceProviding.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Core
import Combine
import BrowserServicesKit
import PrivacyConfig
import AIChat
import DDGSync
import enum UserScript.UserScriptError
import WebExtensions

public protocol ScriptSourceProviding {

    var loginDetectionEnabled: Bool { get }
    var sendDoNotSell: Bool { get }
    var sync: DDGSyncing { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var autofillSourceProvider: AutofillUserScriptSourceProvider { get }
    var contentScopeProperties: ContentScopeProperties { get }
    var sessionKey: String { get }
    var messageSecret: String { get }
    var currentCohorts: [ContentScopeExperimentData] { get }
    var syncErrorHandler: SyncErrorHandling { get }
    var webExtensionAvailability: WebExtensionAvailabilityProviding? { get }
    var trackerProtectionDataSource: TrackerProtectionDataSource? { get }
    var aiChatBonusOffer: AIChatBonusOfferDependencies { get }
    var aiChatLocalModel: AIChatLocalModelDependencies? { get }
    /// Read once at launch, so a change applies after an app restart.
    var isBlankFrameOptimizationEnabled: Bool { get }

}

struct DefaultScriptSourceProvider: ScriptSourceProviding {

    struct Dependencies {
        let appSettings: AppSettings
        let sync: DDGSyncing
        let privacyConfigurationManager: PrivacyConfigurationManaging
        let contentBlockingManager: ContentBlockerRulesManagerProtocol
        let fireproofing: Fireproofing
        let contentScopeExperimentsManager: ContentScopeExperimentsManaging
        let internalUserDecider: InternalUserDecider
        let syncErrorHandler: SyncErrorHandling
        let webExtensionAvailability: WebExtensionAvailabilityProviding?
        let aiChatBonusOffer: AIChatBonusOfferDependencies
        var aiChatLocalModel: AIChatLocalModelDependencies?
        var isBlankFrameOptimizationEnabled: Bool = false
    }

    var loginDetectionEnabled: Bool { fireproofing.loginDetectionEnabled }
    let sendDoNotSell: Bool

    var sync: DDGSyncing

    let autofillSourceProvider: AutofillUserScriptSourceProvider
    let contentScopeProperties: ContentScopeProperties
    let sessionKey: String
    let messageSecret: String

    let privacyConfigurationManager: PrivacyConfigurationManaging
    let contentBlockingManager: ContentBlockerRulesManagerProtocol
    let fireproofing: Fireproofing
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    var currentCohorts: [ContentScopeExperimentData] = []
    let syncErrorHandler: SyncErrorHandling
    let webExtensionAvailability: WebExtensionAvailabilityProviding?
    let trackerProtectionDataSource: TrackerProtectionDataSource?
    let aiChatBonusOffer: AIChatBonusOfferDependencies
    let aiChatLocalModel: AIChatLocalModelDependencies?
    let isBlankFrameOptimizationEnabled: Bool

    init(dependencies: Dependencies) {

        sendDoNotSell = dependencies.appSettings.sendDoNotSell

        self.sync = dependencies.sync
        self.privacyConfigurationManager = dependencies.privacyConfigurationManager
        self.contentBlockingManager = dependencies.contentBlockingManager
        self.fireproofing = dependencies.fireproofing
        self.contentScopeExperimentsManager = dependencies.contentScopeExperimentsManager

        sessionKey = Self.generateSessionKey()
        messageSecret = Self.generateSessionKey()
        currentCohorts = Self.generateCurrentCohorts(experimentManager: contentScopeExperimentsManager)
        syncErrorHandler = dependencies.syncErrorHandler
        webExtensionAvailability = dependencies.webExtensionAvailability
        aiChatBonusOffer = dependencies.aiChatBonusOffer
        aiChatLocalModel = dependencies.aiChatLocalModel
        isBlankFrameOptimizationEnabled = dependencies.isBlankFrameOptimizationEnabled
        trackerProtectionDataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: contentBlockingManager
        )

        contentScopeProperties = ContentScopeProperties(gpcEnabled: dependencies.appSettings.sendDoNotSell,
                                                        sessionKey: sessionKey,
                                                        messageSecret: messageSecret,
                                                        isInternalUser: dependencies.internalUserDecider.isInternalUser,
                                                        debug: AppUserDefaults().contentScopeDebugStateEnabled,
                                                        featureToggles: ContentScopeFeatureToggles.supportedFeaturesOniOS,
                                                        currentCohorts: currentCohorts)
        autofillSourceProvider = Self.makeAutofillSource(privacyConfigurationManager: privacyConfigurationManager,
                                                         properties: contentScopeProperties,
                                                         isBlankFrameOptimizationEnabled: dependencies.isBlankFrameOptimizationEnabled)
    }

    private static func generateSessionKey() -> String { UUID().uuidString }
    
    private static func makeAutofillSource(privacyConfigurationManager: PrivacyConfigurationManaging,
                                           properties: ContentScopeProperties,
                                           isBlankFrameOptimizationEnabled: Bool) -> AutofillUserScriptSourceProvider {
        do {
            return try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                             properties: properties,
                                                             isDebug: AppUserDefaults().autofillDebugScriptEnabled)
            .withJSLoading()
            .withBlankFrameOptimization(isBlankFrameOptimizationEnabled)
            .build()
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to build DefaultAutofillSourceProvider: \(error)")
        }
    }
    
    private static func generateCurrentCohorts(experimentManager: ContentScopeExperimentsManaging) -> [ContentScopeExperimentData] {
        let experiments = experimentManager.resolveContentScopeScriptActiveExperiments()
        return experiments.map {
            ContentScopeExperimentData(feature: $0.value.parentID, subfeature: $0.key, cohort: $0.value.cohortID)
        }
    }

}
