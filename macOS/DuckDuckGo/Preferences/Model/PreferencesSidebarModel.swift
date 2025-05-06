//
//  PreferencesSidebarModel.swift
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
import Common
import Combine
import DDGSync
import SwiftUI
import Subscription
import NetworkProtectionIPC
import LoginItems
import PreferencesUI_macOS

final class PreferencesSidebarModel: ObservableObject {

    let tabSwitcherTabs: [Tab.TabContent]

    @Published private(set) var sections: [PreferencesSection] = []
    @Published var selectedTabIndex: Int = 0
    @Published private(set) var selectedPane: PreferencePaneIdentifier = .defaultBrowser
    private let vpnGatekeeper: VPNFeatureGatekeeper
    let vpnTunnelIPCClient: VPNControllerXPCClient

    private(set) var currentSubscriptionState: PreferencesSidebarSubscriptionState = .initial

    private let personalInformationRemovalSubject = PassthroughSubject<StatusIndicator, Never>()
    public let personalInformationRemovalUpdates: AnyPublisher<StatusIndicator, Never>

    private let identityTheftRestorationSubject = PassthroughSubject<StatusIndicator, Never>()
    public let identityTheftRestorationUpdates: AnyPublisher<StatusIndicator, Never>


    var selectedTabContent: AnyPublisher<Tab.TabContent, Never> {
        $selectedTabIndex.map { [tabSwitcherTabs] in tabSwitcherTabs[$0] }.eraseToAnyPublisher()
    }

    // MARK: - Initializers

    init(
        loadSections: @escaping (PreferencesSidebarSubscriptionState) -> [PreferencesSection],
        tabSwitcherTabs: [Tab.TabContent],
        privacyConfigurationManager: PrivacyConfigurationManaging,
        syncService: DDGSyncing,
        vpnGatekeeper: VPNFeatureGatekeeper = DefaultVPNFeatureGatekeeper(subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge),
        vpnTunnelIPCClient: VPNControllerXPCClient = .shared
    ) {
        self.loadSections = loadSections
        self.tabSwitcherTabs = tabSwitcherTabs
        self.vpnGatekeeper = vpnGatekeeper
        self.vpnTunnelIPCClient = vpnTunnelIPCClient

        self.personalInformationRemovalUpdates = personalInformationRemovalSubject.eraseToAnyPublisher()
        self.identityTheftRestorationUpdates = identityTheftRestorationSubject.eraseToAnyPublisher()

        resetTabSelectionIfNeeded()

        refreshSections()
        refreshSubscriptionStateAndSectionsIfNeeded()

        subscribeToFeatureFlagChanges(syncService: syncService,
                                      privacyConfigurationManager: privacyConfigurationManager)
        subscribeToSubscriptionChanges()

        setupVPNPaneVisibility()
    }

    @MainActor
    convenience init(
        tabSwitcherTabs: [Tab.TabContent] = Tab.TabContent.displayableTabTypes,
        privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
        syncService: DDGSyncing,
        vpnGatekeeper: VPNFeatureGatekeeper,
        includeDuckPlayer: Bool,
        includeAIChat: Bool,
        userDefaults: UserDefaults = .netP
    ) {
        let loadSections = { currentSubscriptionFeatures in
            let includingVPN = vpnGatekeeper.isInstalled

            return PreferencesSection.defaultSections(
                includingDuckPlayer: includeDuckPlayer,
                includingSync: syncService.featureFlags.contains(.userInterface),
                includingVPN: includingVPN,
                includingAIChat: includeAIChat,
                subscriptionState: currentSubscriptionFeatures
            )
        }

        self.init(loadSections: loadSections,
                  tabSwitcherTabs: tabSwitcherTabs,
                  privacyConfigurationManager: privacyConfigurationManager,
                  syncService: syncService,
                  vpnGatekeeper: vpnGatekeeper)
    }

    // MARK: - Setup

    private func subscribeToFeatureFlagChanges(syncService: DDGSyncing,
                                               privacyConfigurationManager: PrivacyConfigurationManaging) {
        let duckPlayerFeatureFlagDidChange = featureFlagDidChange(with: privacyConfigurationManager, on: .duckPlayer)
        let aiChatFeatureFlagDidChange = featureFlagDidChange(with: privacyConfigurationManager, on: .aiChat)

        let syncFeatureFlagsDidChange = syncService.featureFlagsPublisher.map { $0.contains(.userInterface) }
            .removeDuplicates()
            .asVoid()

        Publishers.Merge(duckPlayerFeatureFlagDidChange, syncFeatureFlagsDidChange)
            .merge(with: aiChatFeatureFlagDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshSections()
            }
            .store(in: &cancellables)
    }

    private func subscribeToSubscriptionChanges() {
        subscriptionEventsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshSubscriptionStateAndSectionsIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func setupVPNPaneVisibility() {
        vpnGatekeeper.onboardStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                self.refreshSections()
            }
            .store(in: &cancellables)
    }

    func shouldEnableItem(_ pane: PreferencePaneIdentifier) -> Bool {
        switch pane {
        case .vpn:
            currentSubscriptionState.userEntitlements.contains(.networkProtection)
        case .personalInformationRemoval:
            currentSubscriptionState.userEntitlements.contains(.dataBrokerProtection)
        case .identityTheftRestoration:
            currentSubscriptionState.userEntitlements.contains(.identityTheftRestoration)
        default:
            true
        }
    }

    func privacyProItemProtectionStatus(_ pane: PreferencePaneIdentifier) -> PrivacyProtectionStatus? {
        switch pane {
        case .vpn:
            vpnProtectionStatus()
        case .personalInformationRemoval:
            PrivacyProtectionStatus(statusIndicator: currentSubscriptionState.personalInformationRemovalStatus)
        case .identityTheftRestoration:
            PrivacyProtectionStatus(statusIndicator: currentSubscriptionState.identityTheftRestorationStatus)
        default:
            nil
        }
    }

    func vpnProtectionStatus() -> PrivacyProtectionStatus {
        let recentConnectionStatus = vpnTunnelIPCClient.connectionStatusObserver.recentValue
        let initialValue: Bool

        if case .connected = recentConnectionStatus {
            initialValue = true
        } else {
            initialValue = false
        }

        return PrivacyProtectionStatus(
            statusPublisher: vpnTunnelIPCClient.connectionStatusObserver.publisher.receive(on: RunLoop.main),
            initialValue: initialValue ? .on : .off
        ) { newStatus in
            if case .connected = newStatus {
                return .on
            } else {
                return .off
            }
        }
    }

    // MARK: - Refreshing logic

    private func featureFlagDidChange(with privacyConfigurationManager: PrivacyConfigurationManaging,
                                      on featureKey: PrivacyFeature) -> AnyPublisher<Void, Never> {
        return privacyConfigurationManager.updatesPublisher
            .map { [weak privacyConfigurationManager] in
                privacyConfigurationManager?.privacyConfig.isEnabled(featureKey: featureKey) == true
            }
            .removeDuplicates()
            .asVoid()
            .eraseToAnyPublisher()
    }

    private func subscriptionEventsPublisher() -> AnyPublisher<Void, Never> {
        return Publishers.Merge7(NotificationCenter.default.publisher(for: .accountDidSignIn),
                                 NotificationCenter.default.publisher(for: .accountDidSignOut),
                                 NotificationCenter.default.publisher(for: .availableAppStoreProductsDidChange),
                                 NotificationCenter.default.publisher(for: .subscriptionDidChange),
                                 NotificationCenter.default.publisher(for: .entitlementsDidChange),
                                 NotificationCenter.default.publisher(for: .dbpLoginItemEnabled),
                                 NotificationCenter.default.publisher(for: .dbpLoginItemDisabled))
        .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
        .asVoid()
        .eraseToAnyPublisher()
    }

    private func refreshSubscriptionStateAndSectionsIfNeeded() {
        Task { @MainActor in
            let subscriptionManager = Application.appDelegate.subscriptionAuthV1toV2Bridge
            let currentSubscriptionFeatures = await subscriptionManager.currentSubscriptionFeatures()
            let shouldHideSubscriptionPurchase = subscriptionManager.currentEnvironment.purchasePlatform == .appStore && subscriptionManager.canPurchase == false

            let updatedState: PreferencesSidebarSubscriptionState

            if subscriptionManager.isUserAuthenticated {
                var currentUserEntitlements: [Entitlement.ProductName] = []
                let entitlements: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .identityTheftRestorationGlobal]

                for entitlement in entitlements {
                    if let hasEntitlement = try? await subscriptionManager.isEnabled(feature: entitlement), hasEntitlement {
                        currentUserEntitlements.append(entitlement)
                    }
                }

                let currentPersonalInformationRemovalStatus = LoginItem.dbpBackgroundAgent.isRunning ? StatusIndicator.on : StatusIndicator.off

                let isIdentityTheftRestorationActive = currentUserEntitlements.contains(.identityTheftRestoration) || currentUserEntitlements.contains(.identityTheftRestorationGlobal)
                let currentIdentityTheftRestorationStatus = isIdentityTheftRestorationActive ? StatusIndicator.on : StatusIndicator.off

                updatedState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                   subscriptionFeatures: currentSubscriptionFeatures,
                                                                   userEntitlements: currentUserEntitlements,
                                                                   shouldHideSubscriptionPurchase: shouldHideSubscriptionPurchase,
                                                                   personalInformationRemovalStatus: currentPersonalInformationRemovalStatus,
                                                                   identityTheftRestorationStatus: currentIdentityTheftRestorationStatus)
            } else {
                updatedState = PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                                   subscriptionFeatures: currentSubscriptionFeatures,
                                                                   userEntitlements: [],
                                                                   shouldHideSubscriptionPurchase: shouldHideSubscriptionPurchase,
                                                                   personalInformationRemovalStatus: .off,
                                                                   identityTheftRestorationStatus: .off)
            }

            if self.currentSubscriptionState != updatedState {
                if self.currentSubscriptionState.personalInformationRemovalStatus != updatedState.personalInformationRemovalStatus {
                    personalInformationRemovalSubject.send(updatedState.personalInformationRemovalStatus)
                }

                if self.currentSubscriptionState.identityTheftRestorationStatus != updatedState.identityTheftRestorationStatus {
                    identityTheftRestorationSubject.send(updatedState.identityTheftRestorationStatus)
                }

                self.currentSubscriptionState = updatedState
                self.refreshSections()
            }
        }
    }

    func refreshSections() {
        sections = loadSections(currentSubscriptionState)
        adjustSelectedPaneIfNeeded()
    }

    func adjustSelectedPaneIfNeeded() {
        let allPanes = sections.flatMap(\.panes)

        if !allPanes.contains(selectedPane) {
            // Adjust Privacy Pro selection when subscribed/unsubscribed state changes
            if selectedPane == .subscriptionSettings, allPanes.contains(.privacyPro) {
                selectedPane = .privacyPro
            } else if selectedPane == .privacyPro, allPanes.contains(.subscriptionSettings) {
                selectedPane = .subscriptionSettings
            } else if let firstPane = sections.first?.panes.first {
                selectedPane = firstPane
            }
        }

        // Adjust Privacy Pro selection for missing entitlements
        let entitlements = currentSubscriptionState.userEntitlements
        if (selectedPane == .vpn && !entitlements.contains(.networkProtection)) ||
            (selectedPane == .personalInformationRemoval && !entitlements.contains(.dataBrokerProtection)) ||
            (selectedPane == .identityTheftRestoration && !(entitlements.contains(.identityTheftRestoration) || entitlements.contains(.identityTheftRestorationGlobal))) {

            selectedPane = currentSubscriptionState.hasSubscription ? .subscriptionSettings : .privacyPro
        }
    }

    @MainActor
    func selectPane(_ identifier: PreferencePaneIdentifier) {
        // Open a new tab in case of special panes
        if identifier.rawValue.hasPrefix(URL.NavigationalScheme.https.rawValue),
            let url = URL(string: identifier.rawValue) {
            WindowControllersManager.shared.show(url: url,
                                                 source: .ui,
                                                 newTab: true)
        }

        if sections.flatMap(\.panes).contains(identifier), identifier != selectedPane {
            selectedPane = identifier
        }
    }

    func resetTabSelectionIfNeeded() {
        if let preferencesTabIndex = tabSwitcherTabs.firstIndex(of: .anySettingsPane) {
            if preferencesTabIndex != selectedTabIndex {
                selectedTabIndex = preferencesTabIndex
            }
        }
    }

    private let loadSections: (PreferencesSidebarSubscriptionState) -> [PreferencesSection]
    private var cancellables = Set<AnyCancellable>()
}

struct PreferencesSidebarSubscriptionState: Equatable {
    let hasSubscription: Bool
    let subscriptionFeatures: [Entitlement.ProductName]?
    let userEntitlements: [Entitlement.ProductName]
    let shouldHideSubscriptionPurchase: Bool

    let personalInformationRemovalStatus: StatusIndicator
    let identityTheftRestorationStatus: StatusIndicator

    static var initial: Self {
        .init(hasSubscription: false,
              subscriptionFeatures: nil,
              userEntitlements: [],
              shouldHideSubscriptionPurchase: true,
              personalInformationRemovalStatus: .off,
              identityTheftRestorationStatus: .off)
    }
}
