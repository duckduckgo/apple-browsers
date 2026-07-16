//
//  ContentBlockingTabExtension.swift
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

import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import ContentBlocking
import Foundation
import Navigation
import PrivacyConfig
import Subscription
import TrackerRadarKit
import os.log

struct DetectedTracker {
    enum TrackerType {
        case tracker
        case trackerWithSurrogate(host: String)
        case thirdPartyRequest
    }
    let request: DetectedRequest
    let type: TrackerType
}

protocol ContentBlockingAssetsInstalling: AnyObject {
    var contentBlockingAssetsInstalled: Bool { get }
    var awaitContentBlockingAssetsInstalled: () async -> Void { get }
}
extension UserContentController: ContentBlockingAssetsInstalling {}

final class ContentBlockingTabExtension: NSObject {
    private static var idCounter: UInt64 = 0
    private let identifier: UInt64 = {
        defer { idCounter += 1 }
        return ContentBlockingTabExtension.idCounter
    }()

    private weak var userContentController: ContentBlockingAssetsInstalling?
    private let cbaTimeReporter: ContentBlockingAssetsCompilationTimeReporter?
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let fbBlockingEnabledProvider: FbBlockingEnabledProvider
    private let tld: TLD
    private let contentBlockingManager: ContentBlockerRulesManagerProtocol
    private let homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor = HomepageSearchModeSeedUserDefaultsPersistor()

    private var cachedMapper: TrackerProtectionEventMapper?
    private var cachedMapperVendor: String?
    private var cachedMapperAttributionTrackerData: TrackerData?
    private var cachedMapperFbBlockingEnabled: Bool?

    private func mapper(forAttributionTrackerData attributionTrackerData: TrackerData?,
                        vendor: String?) -> TrackerProtectionEventMapper? {
        let fbBlockingEnabled = fbBlockingEnabledProvider.fbBlockingEnabled
        if let cachedMapper,
           cachedMapperVendor == vendor,
           cachedMapperAttributionTrackerData == attributionTrackerData,
           cachedMapperFbBlockingEnabled == fbBlockingEnabled {
            return cachedMapper
        }
        let mapper = makeMapper(attributionTrackerData: attributionTrackerData)
        cachedMapper = mapper
        cachedMapperVendor = vendor
        cachedMapperAttributionTrackerData = attributionTrackerData
        cachedMapperFbBlockingEnabled = fbBlockingEnabled
        return mapper
    }

    private func makeMapper(attributionTrackerData: TrackerData?) -> TrackerProtectionEventMapper? {
        let tdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        let ctlListName = DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName
        let rules = contentBlockingManager.currentRules
        guard let mainTrackerData = rules.first(where: { $0.name == tdsName })?.trackerData else { return nil }

        var supplementary: [TrackerData] = []
        if fbBlockingEnabledProvider.fbBlockingEnabled,
           let ctlTrackerData = rules.first(where: { $0.name == ctlListName })?.trackerData {
            supplementary.append(ctlTrackerData)
        }
        if let attributionTrackerData {
            supplementary.append(attributionTrackerData)
        }

        let privacyConfig = privacyConfigurationManager.privacyConfig
        let tempList = privacyConfig.tempUnprotectedDomains + privacyConfig.exceptionsList(forFeature: .contentBlocking)
        return TrackerProtectionEventMapper(tld: tld,
                                            mainTrackerData: mainTrackerData,
                                            supplementaryTrackerData: supplementary,
                                            unprotectedSites: privacyConfig.userUnprotectedDomains,
                                            tempList: tempList,
                                            contentBlockingEnabled: privacyConfig.isEnabled(featureKey: .contentBlocking),
                                            trackerAllowlist: privacyConfig.trackerAllowlist.entries)
    }
    private var trackersSubject = PassthroughSubject<DetectedTracker, Never>()

    private var cancellables = Set<AnyCancellable>()

#if DEBUG
    /// set this to true when Navigation-related decision making is expected to take significant time to avoid assertions
    /// used by BSK: Navigation.DistributedNavigationDelegate
    var shouldDisableLongDecisionMakingChecks: Bool = false
    func disableLongDecisionMakingChecks() { shouldDisableLongDecisionMakingChecks = true }
    func enableLongDecisionMakingChecks() { shouldDisableLongDecisionMakingChecks = false }
#else
    func disableLongDecisionMakingChecks() {}
    func enableLongDecisionMakingChecks() {}
#endif

    init(fbBlockingEnabledProvider: FbBlockingEnabledProvider,
         userContentControllerFuture: some Publisher<some ContentBlockingAssetsInstalling, Never>,
         cbaTimeReporter: ContentBlockingAssetsCompilationTimeReporter?,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         trackerProtectionSubfeaturePublisher: some Publisher<TrackerProtectionSubfeature?, Never>,
         tld: TLD,
         contentBlockingManager: ContentBlockerRulesManagerProtocol) {

        self.cbaTimeReporter = cbaTimeReporter
        self.fbBlockingEnabledProvider = fbBlockingEnabledProvider
        self.privacyConfigurationManager = privacyConfigurationManager
        self.tld = tld
        self.contentBlockingManager = contentBlockingManager
        super.init()

        userContentControllerFuture.sink { [weak self] userContentController in
            self?.userContentController = userContentController
        }.store(in: &cancellables)
        trackerProtectionSubfeaturePublisher.sink { [weak self] trackerProtectionSubfeature in
            trackerProtectionSubfeature?.delegate = self
        }.store(in: &cancellables)
    }

    deinit {
        cbaTimeReporter?.tabWillClose(identifier)
    }

}

extension ContentBlockingTabExtension: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        if !navigationAction.url.isDuckDuckGo
            // ContentScopeUserScript needs to be loaded for https://duckduckgo.com/email/
            || navigationAction.url.absoluteString.hasPrefix(URL.duckDuckGoEmailLogin.absoluteString)
            // ContentScopeUserScript needs to be loaded for https://duckduckgo.com/subscriptions
            || navigationAction.url.absoluteString.hasPrefix(SubscriptionURL.baseURL.subscriptionURL(environment: .production).absoluteString)
            // ContentScopeUserScript needs to be loaded for https://duckduckgo.com/identity-theft-restoration
            || navigationAction.url.absoluteString.hasPrefix(SubscriptionURL.identityTheftRestoration.subscriptionURL(environment: .production).absoluteString)
            // ContentScopeUserScript needs to be loaded for Duck.ai
            || navigationAction.url.isDuckAIURL
            // HomepageSearchModeToggleSeedUserScript must install before the homepage reads its settings
            || (navigationAction.url.isDuckDuckGo && homepageSearchModeSeedPersistor.pendingShowSearchModeToggle != nil) {
            await prepareForContentBlocking()
        }

        return .next
    }

    @MainActor
    private func prepareForContentBlocking() async {
        // Ensure Content Blocking Assets (WKContentRuleList&UserScripts) are installed
        if userContentController?.contentBlockingAssetsInstalled == false
            && privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking) {
            Logger.contentBlocking.log("\(self.identifier) tabWillWaitForRulesCompilation")
            cbaTimeReporter?.tabWillWaitForRulesCompilation(identifier)

            disableLongDecisionMakingChecks()
            defer {
                enableLongDecisionMakingChecks()
            }

            await userContentController?.awaitContentBlockingAssetsInstalled()
            Logger.contentBlocking.log("\(self.identifier) Rules Compilation done")
            cbaTimeReporter?.reportWaitTimeForTabFinishedWaitingForRules(identifier)
        } else {
            cbaTimeReporter?.reportNavigationDidNotWaitForRules()
        }
    }

}

extension ContentBlockingTabExtension: TrackerProtectionSubfeatureDelegate {

    func trackerProtectionShouldProcessTrackers(_ subfeature: TrackerProtectionSubfeature) -> Bool {
        return true
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didObserveResource observation: TrackerProtectionSubfeature.ResourceObservation) {
        guard let mapper = mapper(forAttributionTrackerData: subfeature.currentAttributionTrackerData,
                                  vendor: subfeature.currentAdClickAttributionVendor) else { return }

        if let detected = mapper.classifyResource(observation,
                                                   adClickAttributionVendor: subfeature.currentAdClickAttributionVendor) {
            trackersSubject.send(DetectedTracker(request: detected, type: .tracker))
            if detected.state == .blocked && detected.ownerName == fbBlockingEnabledProvider.fbEntity {
                fbBlockingEnabledProvider.trackerDetected()
            }
        } else if let thirdParty = mapper.makeThirdPartyRequest(from: observation) {
            trackersSubject.send(DetectedTracker(request: thirdParty, type: .thirdPartyRequest))
        }
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didInjectSurrogate surrogate: TrackerProtectionSubfeature.SurrogateInjection) {
        guard let mapper = mapper(forAttributionTrackerData: subfeature.currentAttributionTrackerData,
                                  vendor: subfeature.currentAdClickAttributionVendor),
              let detected = mapper.classifySurrogate(surrogate,
                                                      adClickAttributionVendor: subfeature.currentAdClickAttributionVendor),
              let host = mapper.surrogateHost(from: surrogate) else { return }
        trackersSubject.send(DetectedTracker(request: detected, type: .trackerWithSurrogate(host: host)))
    }
}

protocol ContentBlockingExtensionProtocol: AnyObject, NavigationResponder {
    var trackersPublisher: AnyPublisher<DetectedTracker, Never> { get }
}

extension ContentBlockingTabExtension: TabExtension, ContentBlockingExtensionProtocol {
    typealias PublicProtocol = ContentBlockingExtensionProtocol

    func getPublicProtocol() -> PublicProtocol { self }

    var trackersPublisher: AnyPublisher<DetectedTracker, Never> {
        trackersSubject.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var contentBlockingAndSurrogates: ContentBlockingExtensionProtocol? {
        resolve(ContentBlockingTabExtension.self)
    }
}

extension Tab {
    var trackersPublisher: AnyPublisher<DetectedTracker, Never> {
        self.contentBlockingAndSurrogates?.trackersPublisher ?? PassthroughSubject().eraseToAnyPublisher()
    }
}
