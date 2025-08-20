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
import enum UserScript.UserScriptError

protocol ScriptSourceProviding {

    var loginDetectionEnabled: Bool { get }
    var sendDoNotSell: Bool { get }
    var contentBlockerRulesConfig: ContentBlockerUserScriptConfig { get }
    var surrogatesConfig: SurrogatesUserScriptConfig { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var autofillSourceProvider: AutofillUserScriptSourceProvider { get }
    var contentScopeProperties: ContentScopeProperties { get }
    var sessionKey: String { get }
    var messageSecret: String { get }
    var currentCohorts: [ContentScopeExperimentData] { get }

}

struct DefaultScriptSourceProvider: ScriptSourceProviding {

    var loginDetectionEnabled: Bool { fireproofing.loginDetectionEnabled }
    let sendDoNotSell: Bool
    
    let contentBlockerRulesConfig: ContentBlockerUserScriptConfig
    let surrogatesConfig: SurrogatesUserScriptConfig
    let autofillSourceProvider: AutofillUserScriptSourceProvider
    let contentScopeProperties: ContentScopeProperties
    let sessionKey: String
    let messageSecret: String

    let privacyConfigurationManager: PrivacyConfigurationManaging
    let contentBlockingManager: ContentBlockerRulesManagerProtocol
    let fireproofing: Fireproofing
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    var currentCohorts: [ContentScopeExperimentData] = []

    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         contentBlockingManager: ContentBlockerRulesManagerProtocol = ContentBlocking.shared.contentBlockingManager,
         fireproofing: Fireproofing,
         contentScopeExperimentsManager: ContentScopeExperimentsManaging = AppDependencyProvider.shared.contentScopeExperimentsManager) {

        sendDoNotSell = appSettings.sendDoNotSell
        
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingManager = contentBlockingManager
        self.fireproofing = fireproofing
        self.contentScopeExperimentsManager = contentScopeExperimentsManager

        contentBlockerRulesConfig = Self.buildContentBlockerRulesConfig(contentBlockingManager: contentBlockingManager,
                                                                        privacyConfigurationManager: privacyConfigurationManager)
        surrogatesConfig = Self.buildSurrogatesConfig(contentBlockingManager: contentBlockingManager,
                                                      privacyConfigurationManager: privacyConfigurationManager)
        sessionKey = Self.generateSessionKey()
        messageSecret = Self.generateSessionKey()
        currentCohorts = Self.generateCurrentCohorts(experimentManager: contentScopeExperimentsManager)

        contentScopeProperties = ContentScopeProperties(gpcEnabled: appSettings.sendDoNotSell,
                                                        sessionKey: sessionKey,
                                                        messageSecret: messageSecret,
                                                        featureToggles: ContentScopeFeatureToggles.supportedFeaturesOniOS,
                                                        currentCohorts: currentCohorts)
        autofillSourceProvider = Self.makeAutofillSource(privacyConfigurationManager: privacyConfigurationManager,
                                                         properties: contentScopeProperties)
    }

    private static func generateSessionKey() -> String { UUID().uuidString }
    
    private static func makeAutofillSource(privacyConfigurationManager: PrivacyConfigurationManaging,
                                           properties: ContentScopeProperties) -> AutofillUserScriptSourceProvider {
        do {
            return try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                             properties: properties,
                                                             isDebug: AppUserDefaults().autofillDebugScriptEnabled)
            .withJSLoading()
            .build()
        } catch {
            if case let UserScriptError.failedToLoadJS(jsFile, filePath, error) = error {
                let params = [PixelParameters.jsFile: jsFile, PixelParameters.path: filePath]
                Pixel.fire(pixel: .userScriptLoadJSFailed, error: error, withAdditionalParameters: params)
                Thread.sleep(forTimeInterval: 1.0) // give time for the pixel to be sent
            }
            fatalError("Failed to build DefaultAutofillSourceProvider: \(error)")
        }
    }
    
    private static func buildContentBlockerRulesConfig(contentBlockingManager: ContentBlockerRulesManagerProtocol,
                                                       privacyConfigurationManager: PrivacyConfigurationManaging) -> ContentBlockerUserScriptConfig {
        
        let currentMainRules = contentBlockingManager.currentMainRules
        let privacyConfig = privacyConfigurationManager.privacyConfig

        do {
            return try DefaultContentBlockerUserScriptConfig(privacyConfiguration: privacyConfig,
                                                             trackerData: currentMainRules?.trackerData,
                                                             ctlTrackerData: nil,
                                                             tld: AppDependencyProvider.shared.storageCache.tld,
                                                             trackerDataManager: ContentBlocking.shared.trackerDataManager)
        } catch {
            if case let UserScriptError.failedToLoadJS(jsFile, filePath, error) = error {
                let params = [PixelParameters.jsFile: jsFile, PixelParameters.path: filePath]
                Pixel.fire(pixel: .userScriptLoadJSFailed, error: error, withAdditionalParameters: params)
                Thread.sleep(forTimeInterval: 1.0) // give time for the pixel to be sent
            }
            fatalError("Failed to initialize DefaultContentBlockerUserScriptConfig: \(error)")
        }
    }

    private static func buildSurrogatesConfig(contentBlockingManager: ContentBlockerRulesManagerProtocol,
                                              privacyConfigurationManager: PrivacyConfigurationManaging) -> SurrogatesUserScriptConfig {

        let surrogates = FileStore().loadAsString(for: .surrogates) ?? ""
        let currentMainRules = contentBlockingManager.currentMainRules

        do {
            let surrogatesConfig = try DefaultSurrogatesUserScriptConfig(privacyConfig: privacyConfigurationManager.privacyConfig,
                                                                         surrogates: surrogates,
                                                                         trackerData: currentMainRules?.trackerData,
                                                                         encodedSurrogateTrackerData: currentMainRules?.encodedTrackerData,
                                                                         trackerDataManager: ContentBlocking.shared.trackerDataManager,
                                                                         tld: AppDependencyProvider.shared.storageCache.tld,
                                                                         isDebugBuild: isDebugBuild)

            return surrogatesConfig
        } catch {
            if case let UserScriptError.failedToLoadJS(jsFile, filePath, error) = error {
                let params = [PixelParameters.jsFile: jsFile, PixelParameters.path: filePath]
                Pixel.fire(pixel: .userScriptLoadJSFailed, error: error, withAdditionalParameters: params)
                Thread.sleep(forTimeInterval: 1.0) // give time for the pixel to be sent
            }
            fatalError("Failed to initialize DefaultSurrogatesUserScriptConfig: \(error)")
        }
    }

    private static func generateCurrentCohorts(experimentManager: ContentScopeExperimentsManaging) -> [ContentScopeExperimentData] {
        let experiments = experimentManager.resolveContentScopeScriptActiveExperiments()
        return experiments.map {
            ContentScopeExperimentData(feature: $0.value.parentID, subfeature: $0.key, cohort: $0.value.cohortID)
        }
    }

}
