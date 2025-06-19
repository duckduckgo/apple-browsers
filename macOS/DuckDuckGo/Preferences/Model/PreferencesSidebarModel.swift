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
import Networking
import Subscription
import NetworkProtectionIPC
import LoginItems
import PixelKit
import PreferencesUI_macOS
import SubscriptionUI

final class PreferencesSidebarModel: ObservableObject {

    let tabSwitcherTabs: [Tab.TabContent]

    @Published private(set) var sections: [PreferencesSection] = []
    @Published var selectedTabIndex: Int = 0
    @Published private(set) var selectedPane: PreferencePaneIdentifier = .defaultBrowser {
        didSet {
            isInitialSelectedPanePixelFired = true
            switch selectedPane {
            case .aiChat:
                pixelFiring?.fire(AIChatPixel.aiChatSettingsDisplayed, frequency: .dailyAndCount)
            default:
                pixelFiring?.fire(SettingsPixel.settingsPaneOpened(selectedPane), frequency: .daily)
            }
        }
    }

    let vpnTunnelIPCClient: VPNControllerXPCClient
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    let settingsIconProvider: SettingsIconsProviding

    @Published private(set) var currentSubscriptionState: PreferencesSidebarSubscriptionState = .initial

    private let personalInformationRemovalSubject = PassthroughSubject<StatusIndicator, Never>()
    public let personalInformationRemovalUpdates: AnyPublisher<StatusIndicator, Never>

    private let identityTheftRestorationSubject = PassthroughSubject<StatusIndicator, Never>()
    public let identityTheftRestorationUpdates: AnyPublisher<StatusIndicator, Never>

    private let paidAIChatSubject = PassthroughSubject<StatusIndicator, Never>()
    public let paidAIChatUpdates: AnyPublisher<StatusIndicator, Never>

    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring?
    private var isInitialSelectedPanePixelFired = false
    private let featureFlagger: FeatureFlagger

    var selectedTabContent: AnyPublisher<Tab.TabContent, Never> {
        $selectedTabIndex.map { [tabSwitcherTabs] in tabSwitcherTabs[$0] }.eraseToAnyPublisher()
    }

    // MARK: - Initializers

    init(
        loadSections: @escaping (PreferencesSidebarSubscriptionState) -> [PreferencesSection],
        tabSwitcherTabs: [Tab.TabContent],
        privacyConfigurationManager: PrivacyConfigurationManaging,
        syncService: DDGSyncing,
        vpnTunnelIPCClient: VPNControllerXPCClient = .shared,
        subscriptionManager: any SubscriptionAuthV1toV2Bridge,
        notificationCenter: NotificationCenter = .default,
        featureFlagger: FeatureFlagger,
        settingsIconProvider: SettingsIconsProviding = NSApp.delegateTyped.visualStyle.iconsProvider.settingsIconProvider,
        pixelFiring: PixelFiring?
    ) {
        self.loadSections = loadSections
        self.tabSwitcherTabs = tabSwitcherTabs
        self.vpnTunnelIPCClient = vpnTunnelIPCClient
        self.subscriptionManager = subscriptionManager
        self.notificationCenter = notificationCenter
        self.settingsIconProvider = settingsIconProvider
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger

        self.personalInformationRemovalUpdates = personalInformationRemovalSubject.eraseToAnyPublisher()
        self.identityTheftRestorationUpdates = identityTheftRestorationSubject.eraseToAnyPublisher()
        self.paidAIChatUpdates = paidAIChatSubject.eraseToAnyPublisher()

        resetTabSelectionIfNeeded()

        refreshSections()

        subscribeToFeatureFlagChanges(syncService: syncService,
                                      privacyConfigurationManager: privacyConfigurationManager)
        subscribeToSubscriptionChanges()

        forceSelectedPanePixelIfNeeded()
    }

    @MainActor
    convenience init(
        tabSwitcherTabs: [Tab.TabContent] = Tab.TabContent.displayableTabTypes,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        featureFlagger: FeatureFlagger,
        syncService: DDGSyncing,
        vpnGatekeeper: VPNFeatureGatekeeper,
        includeDuckPlayer: Bool,
        includeAIChat: Bool,
        userDefaults: UserDefaults = .netP,
        subscriptionManager: any SubscriptionAuthV1toV2Bridge
    ) {
        let loadSections = { currentSubscriptionFeatures in
            return PreferencesSection.defaultSections(
                includingDuckPlayer: includeDuckPlayer,
                includingSync: syncService.featureFlags.contains(.userInterface),
                includingAIChat: includeAIChat,
                subscriptionState: currentSubscriptionFeatures
            )
        }

        self.init(loadSections: loadSections,
                  tabSwitcherTabs: tabSwitcherTabs,
                  privacyConfigurationManager: privacyConfigurationManager,
                  syncService: syncService,
                  subscriptionManager: subscriptionManager,
                  featureFlagger: featureFlagger,
                  pixelFiring: PixelKit.shared
        )
    }

    public func onAppear() {
        refreshSubscriptionStateAndSectionsIfNeeded()
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

    private func forceSelectedPanePixelIfNeeded() {
        if !isInitialSelectedPanePixelFired {
            selectedPane = selectedPane
        }
    }

    func isSidebarItemEnabled(for pane: PreferencePaneIdentifier) -> Bool {
        switch pane {
        case .vpn:
            currentSubscriptionState.userEntitlements.contains(.networkProtection)
        case .personalInformationRemoval:
            currentSubscriptionState.userEntitlements.contains(.dataBrokerProtection)
        case .paidAIChat:
            currentSubscriptionState.userEntitlements.contains(.paidAIChat)
        case .identityTheftRestoration:
            currentSubscriptionState.userEntitlements.contains(.identityTheftRestoration) ||
            currentSubscriptionState.userEntitlements.contains(.identityTheftRestorationGlobal)
        default:
            true
        }
    }

    func protectionStatus(for pane: PreferencePaneIdentifier) -> PrivacyProtectionStatus? {
        switch pane {
        case .defaultBrowser:
            return PrivacyProtectionStatus(statusPublisher: DefaultBrowserPreferences.shared.$isDefault) { isDefault in
                isDefault ? .on : .off
            }
        case .privateSearch:
            return PrivacyProtectionStatus(statusIndicator: .on)
        case .webTrackingProtection:
            return PrivacyProtectionStatus(statusIndicator: .on)
        case .threatProtection:
            return PrivacyProtectionStatus(statusIndicator: .on)
        case .cookiePopupProtection:
            return  PrivacyProtectionStatus(statusPublisher: CookiePopupProtectionPreferences.shared.$isAutoconsentEnabled) { isAutoconsentEnabled in
                isAutoconsentEnabled ? .on : .off
            }
        case .emailProtection:
            let publisher = Publishers.Merge(
                notificationCenter.publisher(for: .emailDidSignIn),
                notificationCenter.publisher(for: .emailDidSignOut)
            )
            return PrivacyProtectionStatus(statusPublisher: publisher, initialValue: EmailManager().isSignedIn ? .on : .off) { _ in
                EmailManager().isSignedIn ? .on : .off
            }
        case .vpn:
            return vpnProtectionStatus()
        case .personalInformationRemoval:
            return PrivacyProtectionStatus(statusIndicator: currentSubscriptionState.personalInformationRemovalStatus)
        case .paidAIChat:
            return PrivacyProtectionStatus(statusIndicator: currentSubscriptionState.paidAIChatStatus)
        case .identityTheftRestoration:
            return PrivacyProtectionStatus(statusIndicator: currentSubscriptionState.identityTheftRestorationStatus)
        default:
            return nil
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
        return Publishers.Merge7(notificationCenter.publisher(for: .accountDidSignIn),
                                 notificationCenter.publisher(for: .accountDidSignOut),
                                 notificationCenter.publisher(for: .availableAppStoreProductsDidChange),
                                 notificationCenter.publisher(for: .subscriptionDidChange),
                                 notificationCenter.publisher(for: .entitlementsDidChange),
                                 notificationCenter.publisher(for: .dbpLoginItemEnabled).delay(for: 2, scheduler: RunLoop.main),
                                 notificationCenter.publisher(for: .dbpLoginItemDisabled).delay(for: 2, scheduler: RunLoop.main))
        .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
        .asVoid()
        .eraseToAnyPublisher()
    }

    private var hasLoadedInitialSubscriptionState: Bool = false

    private func refreshSubscriptionStateAndSectionsIfNeeded() {
        Task { @MainActor in
            let updatedState = await makeSubscriptionState()

            if self.currentSubscriptionState != updatedState {
                hasLoadedInitialSubscriptionState = true

                if self.currentSubscriptionState.personalInformationRemovalStatus != updatedState.personalInformationRemovalStatus {
                    personalInformationRemovalSubject.send(updatedState.personalInformationRemovalStatus)
                }

                if self.currentSubscriptionState.paidAIChatStatus != updatedState.paidAIChatStatus {
                    paidAIChatSubject.send(updatedState.paidAIChatStatus)
                }

                if self.currentSubscriptionState.identityTheftRestorationStatus != updatedState.identityTheftRestorationStatus {
                    identityTheftRestorationSubject.send(updatedState.identityTheftRestorationStatus)
                }

                self.currentSubscriptionState = updatedState
                self.refreshSections()
            }
        }
    }

    private func makeSubscriptionState() async -> PreferencesSidebarSubscriptionState {
        let currentSubscriptionFeatures = await subscriptionManager.currentSubscriptionFeatures()
        let shouldHideSubscriptionPurchase = subscriptionManager.currentEnvironment.purchasePlatform == .appStore && subscriptionManager.canPurchase == false

        if subscriptionManager.isUserAuthenticated {
            // Calculate current user entitlements
            var currentUserEntitlements: [SubscriptionEntitlement] = []
            let entitlements: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .identityTheftRestorationGlobal, .paidAIChat]

            if let subscriptionManagerV2 = subscriptionManager as? SubscriptionManagerV2,
               let tokenContainer = try? await subscriptionManagerV2.getTokenContainer(policy: .localValid) {

                for entitlement in entitlements where tokenContainer.decodedAccessToken.hasEntitlement(entitlement) {
                    currentUserEntitlements.append(entitlement)

                }
            } else {
                for entitlement in entitlements {
                    if let hasEntitlement = try? await subscriptionManager.isEnabled(feature: entitlement.product), hasEntitlement == true {
                        currentUserEntitlements.append(entitlement)
                    }
                }
            }

            // Calculate PIR protection status
            let currentPersonalInformationRemovalStatus = LoginItem.dbpBackgroundAgent.isRunning ? StatusIndicator.on : StatusIndicator.off

            // Calculate ITR protection status
            let isIdentityTheftRestorationActive = currentUserEntitlements.contains(.identityTheftRestoration) || currentUserEntitlements.contains(.identityTheftRestorationGlobal)
            let currentIdentityTheftRestorationStatus = isIdentityTheftRestorationActive ? StatusIndicator.on : StatusIndicator.off

            // Calculate DAP protection status
            let currentPaidAIChatStatus = currentUserEntitlements.contains(.paidAIChat) ? StatusIndicator.on : StatusIndicator.off

            return PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                       subscriptionFeatures: currentSubscriptionFeatures,
                                                       userEntitlements: currentUserEntitlements,
                                                       shouldHideSubscriptionPurchase: shouldHideSubscriptionPurchase,
                                                       personalInformationRemovalStatus: currentPersonalInformationRemovalStatus,
                                                       identityTheftRestorationStatus: currentIdentityTheftRestorationStatus,
                                                       paidAIChatStatus: currentPaidAIChatStatus,
                                                       isPaidAIChatEnabled: featureFlagger.isFeatureOn(.paidAIChat))
        } else {
            return PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                       subscriptionFeatures: currentSubscriptionFeatures,
                                                       userEntitlements: [],
                                                       shouldHideSubscriptionPurchase: shouldHideSubscriptionPurchase,
                                                       personalInformationRemovalStatus: .off,
                                                       identityTheftRestorationStatus: .off,
                                                       paidAIChatStatus: .off,
                                                       isPaidAIChatEnabled: featureFlagger.isFeatureOn(.paidAIChat))
        }
    }

    func refreshSections() {
        sections = loadSections(currentSubscriptionState)
        adjustSelectedPaneIfNeeded()
    }

    func adjustSelectedPaneIfNeeded() {
        let allPanes = sections.flatMap(\.panes)

        if !allPanes.contains(selectedPane) {

            // Required to keep selection since subscription settings need to load its initial state
            if selectedPane == .subscriptionSettings && !hasLoadedInitialSubscriptionState {
                return
            }

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
            Application.appDelegate.windowControllersManager.show(url: url,
                                                 source: .ui,
                                                 newTab: true)
        }

        // Required to keep selection since subscription settings need to load its initial state
        if identifier == .subscriptionSettings && !hasLoadedInitialSubscriptionState {
            selectedPane = identifier
            return
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
