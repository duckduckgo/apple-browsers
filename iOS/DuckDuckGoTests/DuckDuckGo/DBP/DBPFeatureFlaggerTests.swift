//
//  DBPFeatureFlaggerTests.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Common
import Configuration
import Core
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import FeatureFlags_iOS
import PageRefreshMonitor
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyDashboard
import Subscription
import Testing
import VPN
import WideEvent
@testable import DuckDuckGo

@Suite("DBP feature flagger")
struct DBPFeatureFlaggerTests {

    private func makeFlagger(enabledFeatureFlags: [FeatureFlag]) -> DBPFeatureFlagger {
        DBPFeatureFlagger(appDependencies: FeatureFlaggerOverridingDependencies(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFeatureFlags)),
                          freemiumPIRDebugSettings: FreemiumPIRDebugSettings(keyValueStore: MockKeyValueFileStore()))
    }

    @available(iOS 16, *)
    @Test("Email opt-out is on when the dbpEmailOptOut flag is on", .timeLimit(.minutes(1)))
    func emailOptOutIsOnWhenTheFlagIsOn() {
        #expect(makeFlagger(enabledFeatureFlags: [.dbpEmailOptOut]).isEmailOptOutEnabled)
    }

    @available(iOS 16, *)
    @Test("Email opt-out is off when the dbpEmailOptOut flag is off", .timeLimit(.minutes(1)))
    func emailOptOutIsOffWhenTheFlagIsOff() {
        #expect(!makeFlagger(enabledFeatureFlags: []).isEmailOptOutEnabled)
    }
}

/// The app's dependencies with only the feature flagger replaced, since DBPFeatureFlagger reads nothing else.
private struct FeatureFlaggerOverridingDependencies: DependencyProvider {
    let featureFlagger: FeatureFlagger
    private let app = AppDependencyProvider.shared

    var appSettings: AppSettings { app.appSettings }
    var variantManager: VariantManager { app.variantManager }
    var internalUserDecider: InternalUserDecider { app.internalUserDecider }
    var mainMenuService: MainMenuService? { app.mainMenuService }
    var isSitePermissionsEnabled: Bool { app.isSitePermissionsEnabled }
    var findInPageImplementation: FindInPageImplementation { app.findInPageImplementation }
    var configurationURLProvider: CustomConfigurationURLProviding { app.configurationURLProvider }
    var contentScopeExperimentsManager: ContentScopeExperimentsManaging { app.contentScopeExperimentsManager }
    var storageCache: StorageCache { app.storageCache }
    var downloadManager: DownloadManager { app.downloadManager }
    var autofillLoginSession: AutofillLoginSession { app.autofillLoginSession }
    var autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager { app.autofillNeverPromptWebsitesManager }
    var configurationManager: ConfigurationManager { app.configurationManager }
    var configurationStore: ConfigurationStore { app.configurationStore }
    var pageRefreshMonitor: PageRefreshMonitor { app.pageRefreshMonitor }
    var vpnFeatureVisibility: DefaultNetworkProtectionVisibility { app.vpnFeatureVisibility }
    var networkProtectionTunnelController: NetworkProtectionTunnelController { app.networkProtectionTunnelController }
    var networkSignalsProvider: NetworkSignalsProviding { app.networkSignalsProvider }
    var memoryPressureProvider: MemoryPressureProviding { app.memoryPressureProvider }
    var connectionObserver: ConnectionStatusObserver { app.connectionObserver }
    var serverInfoObserver: ConnectionServerInfoObserver { app.serverInfoObserver }
    var connectionErrorObserver: ConnectionErrorObserver { app.connectionErrorObserver }
    var vpnSettings: VPNSettings { app.vpnSettings }
    var wideEvent: WideEventManaging { app.wideEvent }
    var freeTrialConversionService: FreeTrialConversionInstrumentationService { app.freeTrialConversionService }
    var subscriptionManager: any SubscriptionManager { app.subscriptionManager }
    var tokenHandlerProvider: any SubscriptionTokenHandling { app.tokenHandlerProvider }
    var subscriptionExpirationReminderScheduler: SubscriptionExpirationReminderScheduling { app.subscriptionExpirationReminderScheduler }
    var dbpSettings: DataBrokerProtectionSettings { app.dbpSettings }
    var syncAutoRestoreDecisionManager: SyncAutoRestoreDecisionManaging { app.syncAutoRestoreDecisionManager }
    var internalFeedbackAttachmentsProvider: InternalFeedbackAttachmentsProvider { app.internalFeedbackAttachmentsProvider }
    var internalFeedbackTabCountProvider: InternalFeedbackTabCountProvider { app.internalFeedbackTabCountProvider }
    var subscriptionOnboardingSession: SubscriptionOnboardingSessionStateManaging { app.subscriptionOnboardingSession }
}
